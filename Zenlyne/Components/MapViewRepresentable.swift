//
//  MapViewRepresentable.swift
//  Zenlyne
//
//  Created by admin on 21/3/25.
//

import SwiftUI
import MapboxMaps
import CoreLocation
import FirebaseAuth
import FirebaseFirestoreInternal

struct MapViewRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: LocationViewModel
        
    init(viewModel: LocationViewModel) {
        self.viewModel = viewModel
    }
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        let mapView = MapboxMaps.MapView(frame: .zero)
        
        // Configure the map style
        mapView.mapboxMap.loadStyle(.streets)
        
        // Set delegate for handling tap gestures
        mapView.gestureRecognizers?.forEach { recognizer in
            if let tapGesture = recognizer as? UITapGestureRecognizer {
                tapGesture.addTarget(context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
            }
        }
        
        // Configure map with initial options
        mapView.mapboxMap.onNext(event: .mapLoaded) { _ in
            // Set camera to initial position
            mapView.camera.fly(to: viewModel.cameraOptions, duration: 0.25)
            
            // Setup point annotation manager for markers
            context.coordinator.setupAnnotations(for: mapView)
        }
        
        // Add camera change listener to track zoom level
        mapView.mapboxMap.onEvery(event: .cameraChanged) { event in
            let newZoom = mapView.cameraState.zoom
            context.coordinator.handleZoomLevelChanged(mapView: mapView, newZoomLevel: newZoom)
        }
        
        // Add mapView to container
        containerView.addSubview(mapView)
        mapView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mapView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            mapView.topAnchor.constraint(equalTo: containerView.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        // Store reference to mapView in coordinator
        context.coordinator.mapView = mapView
                
        return containerView
    }
        
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let mapView = context.coordinator.mapView else { return }
        
        print("DEBUG: Updating MapView with \(viewModel.friendLocations.count) friend locations")

        // Update map style according to current state
        mapView.mapboxMap.loadStyle(viewModel.currentMapStyle.mapboxStyle)

        // Update camera position
        mapView.camera.fly(to: viewModel.cameraOptions, duration: 0.25)

        // Update user and friends positions
        if let userLocation = viewModel.userLocation {
            context.coordinator.updateUserAnnotation(
                for: mapView,
                at: userLocation,
                userName: viewModel.currentUser.fullName
            )
        }

        context.coordinator.updateFriendAnnotations(
            for: mapView,
            friendLocations: viewModel.friendLocations,
            friends: viewModel.friends
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    class Coordinator: NSObject {
        private var viewModel: LocationViewModel
        var mapView: MapboxMaps.MapView?
        private var userAnnotationManager: PointAnnotationManager?
        private var friendAnnotationManager: PointAnnotationManager?
        private var expandedClusterAnnotationManager: PointAnnotationManager?
        private var friendIdByAnnotationId: [String: String] = [:]
        private let locationGrouper = FriendLocationGrouper()
        private var clusterIdByAnnotationId: [String: [String]] = [:]
        private var expandedClusterAnnotations: [String: [PointAnnotation]] = [:]
        private var markerAnimationManager = MarkerAnimationManager()
        private var clusterAnimationManager = ClusterAnimationManager()
        private var currentMapZoomLevel: Double = 14.0
        
        // Keep track of current location groups for reference
        private var currentLocationGroups: [LocationGroup] = []
        
        // Image cache for async loading
        private var imageCache: [String: UIImage] = [:]
        
        init(viewModel: LocationViewModel) {
            self.viewModel = viewModel
            super.init()
        }
        
        // MARK: - Map Events Handling
        
        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            // When the user taps on the map (not on a marker),
            // send a notification to close the friend info panel if it's displayed
            NotificationCenter.default.post(name: NSNotification.Name("MapTapped"), object: nil)
        }
        
        @MainActor func handleZoomLevelChanged(mapView: MapboxMaps.MapView, newZoomLevel: Double) {
            // Only react if the zoom level has changed significantly
            if abs(newZoomLevel - currentMapZoomLevel) > 0.5 {
                currentMapZoomLevel = newZoomLevel
                locationGrouper.updateZoomLevel(newZoomLevel)
                
                // Auto-expand clusters at high zoom levels
                let shouldAutoExpandClusters = newZoomLevel >= 16.0
                
                if shouldAutoExpandClusters {
                    // Zoom is high enough to auto-expand all visible clusters
                    autoExpandClustersForZoomLevel(mapView: mapView)
                } else if newZoomLevel < 15.0 {
                    // Zoom is low enough to collapse all clusters
                    collapseAllClusters(mapView: mapView)
                }
                
                // Re-process friend annotations with new zoom level
                updateFriendAnnotations(
                    for: mapView,
                    friendLocations: viewModel.friendLocations,
                    friends: viewModel.friends
                )
            }
        }
        
        // MARK: - Cluster Expansion Management
        
        @MainActor private func autoExpandClustersForZoomLevel(mapView: MapboxMaps.MapView) {
            var expanded = false
            
            // Find all clusters and mark them as expanded
            for group in currentLocationGroups {
                if group.type == .cluster && group.count >= 2 {
                    let clusterId = group.friendIds.sorted().joined(separator: "_")
                    
                    // Only expand if not already expanded
                    if !locationGrouper.isClusterExpanded(clusterId: clusterId) {
                        _ = locationGrouper.toggleClusterExpansion(clusterId: clusterId)
                        expanded = true
                    }
                }
            }
            
            // Update annotations if any clusters were newly expanded
            if expanded {
                updateFriendAnnotations(
                    for: mapView,
                    friendLocations: viewModel.friendLocations,
                    friends: viewModel.friends
                )
            }
        }
        
        @MainActor private func collapseAllClusters(mapView: MapboxMaps.MapView) {
            // Reset all expanded clusters
            locationGrouper.expandedClusterIds = Set<String>()
            
            // Clear any expanded cluster annotations
            if let expandedManager = expandedClusterAnnotationManager {
                expandedManager.annotations = []
            }
            expandedClusterAnnotations = [:]
            
            // Re-process friend annotations with collapsed clusters
            updateFriendAnnotations(
                for: mapView,
                friendLocations: viewModel.friendLocations,
                friends: viewModel.friends
            )
        }
        
        // MARK: - Async Image Loading
        
        private func loadImageAsync(from urlString: String, completion: @escaping (UIImage?) -> Void) {
            // Check cache first
            if let cachedImage = imageCache[urlString] {
                completion(cachedImage)
                return
            }
            
            guard let url = URL(string: urlString) else {
                completion(nil)
                return
            }
            
            URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
                guard let data = data, error == nil, let image = UIImage(data: data) else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                // Cache the image
                self?.imageCache[urlString] = image
                
                DispatchQueue.main.async {
                    completion(image)
                }
            }.resume()
        }
        
        // MARK: - Annotation Creation
        
        @MainActor func createUserMarkerImage(for mapView: MapboxMaps.MapView) {
            let size: CGFloat = 50
            
            // Use current avatar URL with consistent property name
            let avatarUrl = viewModel.currentUser.currentAvatarUrl ?? viewModel.currentUser.profileImageUrl
            
            if let avatarUrlString = avatarUrl {
                // Load image asynchronously
                loadImageAsync(from: avatarUrlString) { [weak self] avatarImage in
                    let annotationImage = self?.generateUserMarkerImage(size: size, avatarImage: avatarImage)
                    guard let image = annotationImage else { return }
                    
                    do {
                        try mapView.mapboxMap.style.addImage(image, id: "user-marker-id")
                        print("DEBUG: Successfully added user marker image with avatar")
                    } catch {
                        print("DEBUG: Error adding user marker image: \(error.localizedDescription)")
                    }
                }
            } else {
                // Generate marker without avatar immediately
                let annotationImage = generateUserMarkerImage(size: size, avatarImage: nil)
                
                do {
                    try mapView.mapboxMap.style.addImage(annotationImage, id: "user-marker-id")
                    print("DEBUG: Successfully added user marker image without avatar")
                } catch {
                    print("DEBUG: Error adding user marker image: \(error.localizedDescription)")
                }
            }
        }
        
        private func generateUserMarkerImage(size: CGFloat, avatarImage: UIImage?) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            
            return renderer.image { ctx in
                let rectangle = CGRect(x: 0, y: 0, width: size, height: size)
                let cornerRadius: CGFloat = 14
                
                // Apply rounded corners for clipping
                let bezierPath = UIBezierPath(
                    roundedRect: rectangle,
                    cornerRadius: cornerRadius
                )
                ctx.cgContext.addPath(bezierPath.cgPath)
                ctx.cgContext.clip()
                
                if let image = avatarImage {
                    // Draw avatar image filling the entire rounded rectangle
                    image.draw(in: rectangle)
                } else {
                    // Create gradient background as fallback
                    let colors = [
                        UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 0.9).cgColor,
                        UIColor(red: 0.0, green: 0.4, blue: 0.9, alpha: 0.9).cgColor
                    ]
                    let gradient = CGGradient(
                        colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: colors as CFArray,
                        locations: [0.0, 1.0]
                    )!
                    
                    // Draw gradient background
                    ctx.cgContext.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: 0, y: 0),
                        end: CGPoint(x: size, y: size),
                        options: []
                    )
                    
                    // Get initials for avatar fallback
                    let initials = viewModel.currentUser.initials
                    
                    // Draw initials in center
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.alignment = .center
                    
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                        .foregroundColor: UIColor.white,
                        .paragraphStyle: paragraphStyle
                    ]
                    
                    let attributedString = NSAttributedString(string: initials, attributes: attributes)
                    
                    // Calculate position to place text in center
                    let textRect = CGRect(x: 0, y: (size - 24) / 2, width: size, height: 24)
                    attributedString.draw(in: textRect)
                }
                
                // Reset clipping path for border
                ctx.cgContext.resetClip()
                
                // Draw glowing border around the rounded rectangle
                let borderPath = UIBezierPath(
                    roundedRect: rectangle.insetBy(dx: 1.5, dy: 1.5),
                    cornerRadius: cornerRadius - 1.5
                )
                ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
                ctx.cgContext.setLineWidth(3.0)
                ctx.cgContext.addPath(borderPath.cgPath)
                ctx.cgContext.strokePath()
            }
        }
        
        @MainActor func updateUserAnnotation(for mapView: MapboxMaps.MapView, at coordinate: CLLocationCoordinate2D, userName: String) {
            guard let annotationManager = userAnnotationManager else {
                print("DEBUG: User annotation manager is nil")
                return
            }
            
            // Recreate user marker image with latest avatar
            createUserMarkerImage(for: mapView)
            
            // Remove existing annotations
            annotationManager.annotations = []
            
            // Create new point annotation for user location
            var pointAnnotation = PointAnnotation(coordinate: coordinate)
            
            // Set the image and anchor for the annotation
            pointAnnotation.iconAnchor = .bottom
            pointAnnotation.iconImage = "user-marker-id"
            pointAnnotation.iconSize = 1.0
            
            // Add the annotation to the manager
            annotationManager.annotations = [pointAnnotation]
            
            print("DEBUG: Updated user annotation at \(coordinate.latitude), \(coordinate.longitude)")
        }
        
        // Create an annotation for a single friend
        private func createFriendAnnotation(for friend: User, at coordinate: CLLocationCoordinate2D, mapView: MapboxMaps.MapView) -> PointAnnotation {
            let isOnline = friend.isOnline
            
            // Create marker image for this friend with their avatar
            createFriendMarkerImage(
                for: mapView,
                friendId: friend.id,
                name: friend.fullName,
                isOnline: isOnline,
                profileImageUrl: friend.currentAvatarUrl ?? friend.profileImageUrl
            )
            
            // Create annotation
            var annotation = PointAnnotation(coordinate: coordinate)
            annotation.iconAnchor = .bottom
            
            let statusText = isOnline ? "online" : "offline"
            let markerIconId = "friend-marker-\(friend.id)-\(statusText)"
            annotation.iconImage = markerIconId
            annotation.iconSize = 1.0
            
            // Save mapping between annotation ID and friend ID
            friendIdByAnnotationId[annotation.id] = friend.id
            
            return annotation
        }

        // Create an annotation for a cluster of friends
        private func createClusterAnnotation(for group: LocationGroup, friends: [User], mapView: MapboxMaps.MapView) -> PointAnnotation {
            // Determine if any friend in the cluster is online
            let anyOnline = friends.contains { $0.isOnline }
            
            // Create a unique ID for this cluster
            let clusterId = group.friendIds.sorted().joined(separator: "_")
            
            // Collect friend initials for display (optional)
            let friendInitials = friends.prefix(3).map { $0.initials }
            
            // Generate and add the cluster marker image to the style
            let clusterImage = ClusterMarkerGenerator.generateClusterMarker(
                count: group.friendIds.count,
                friendInitials: friendInitials,
                isOnline: anyOnline
            )
            
            do {
                try mapView.mapboxMap.style.addImage(clusterImage, id: clusterId)
            } catch {
                print("DEBUG: Error adding cluster marker image: \(error.localizedDescription)")
            }
            
            // Create annotation
            var annotation = PointAnnotation(coordinate: group.centerCoordinate)
            annotation.iconAnchor = .bottom
            annotation.iconImage = clusterId
            annotation.iconSize = 1.0
            
            // Store the cluster ID in the annotation's properties for later reference
            annotation.userInfo?["clusterId"] = clusterId
            
            return annotation
        }

        // Updated method to load friend avatars asynchronously
        func createFriendMarkerImage(for mapView: MapboxMaps.MapView, friendId: String? = nil, name: String? = nil, isOnline: Bool = false, profileImageUrl: String? = nil) {
            let size: CGFloat = 50
            
            if let avatarUrlString = profileImageUrl {
                // Load image asynchronously
                loadImageAsync(from: avatarUrlString) { [weak self] avatarImage in
                    let markerImage = self?.generateFriendMarkerImage(
                        size: size,
                        name: name,
                        isOnline: isOnline,
                        avatarImage: avatarImage
                    )
                    
                    guard let image = markerImage else { return }
                    
                    let statusText = isOnline ? "online" : "offline"
                    let markerId = friendId != nil ? "friend-marker-\(friendId!)-\(statusText)" : "friend-marker-default-\(statusText)"
                    
                    do {
                        try mapView.mapboxMap.style.addImage(image, id: markerId)
                        print("DEBUG: Successfully added friend marker for \(name ?? "Unknown") with avatar")
                    } catch {
                        print("DEBUG: Error adding friend marker image: \(error.localizedDescription)")
                    }
                }
            } else {
                // Generate marker without avatar immediately
                let markerImage = generateFriendMarkerImage(
                    size: size,
                    name: name,
                    isOnline: isOnline,
                    avatarImage: nil
                )
                
                let statusText = isOnline ? "online" : "offline"
                let markerId = friendId != nil ? "friend-marker-\(friendId!)-\(statusText)" : "friend-marker-default-\(statusText)"
                
                do {
                    try mapView.mapboxMap.style.addImage(markerImage, id: markerId)
                    print("DEBUG: Successfully added friend marker for \(name ?? "Unknown") without avatar")
                } catch {
                    print("DEBUG: Error adding friend marker image: \(error.localizedDescription)")
                }
            }
        }
        
        private func generateFriendMarkerImage(size: CGFloat, name: String?, isOnline: Bool, avatarImage: UIImage?) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            
            return renderer.image { ctx in
                let rectangle = CGRect(x: 0, y: 0, width: size, height: size)
                let cornerRadius: CGFloat = 12
                
                // Apply rounded corners for clipping
                let bezierPath = UIBezierPath(
                    roundedRect: rectangle,
                    cornerRadius: cornerRadius
                )
                ctx.cgContext.addPath(bezierPath.cgPath)
                ctx.cgContext.clip()
                
                if let image = avatarImage {
                    // Draw avatar image filling the entire rounded rectangle
                    image.draw(in: rectangle)
                } else {
                    // Create gradient background - different colors for online/offline
                    let colors: [CGColor]
                    if isOnline {
                        // Orange color for online friends
                        colors = [
                            UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 0.9).cgColor,
                            UIColor(red: 0.8, green: 0.3, blue: 0.0, alpha: 0.9).cgColor
                        ]
                    } else {
                        // Gray color for offline friends
                        colors = [
                            UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.9).cgColor,
                            UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 0.9).cgColor
                        ]
                    }
                    
                    let gradient = CGGradient(
                        colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: colors as CFArray,
                        locations: [0.0, 1.0]
                    )!
                    
                    // Draw gradient background
                    ctx.cgContext.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: 0, y: 0),
                        end: CGPoint(x: size, y: size),
                        options: []
                    )
                    
                    // Get initials from name for avatar fallback
                    let fullName = name ?? "Friend"
                    let formatter = PersonNameComponentsFormatter()
                    var initials = ""
                    if let components = formatter.personNameComponents(from: fullName) {
                        formatter.style = .abbreviated
                        initials = formatter.string(from: components)
                    } else {
                        // Fallback if formatter fails
                        let words = fullName.split(separator: " ")
                        if words.count > 1 {
                            initials = String(words[0].prefix(1)) + String(words.last!.prefix(1))
                        } else if !words.isEmpty {
                            initials = String(words[0].prefix(1))
                        } else {
                            initials = "?"
                        }
                    }
                    
                    // Draw initials in center
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.alignment = .center
                    
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                        .foregroundColor: UIColor.white,
                        .paragraphStyle: paragraphStyle
                    ]
                    
                    let attributedString = NSAttributedString(string: initials, attributes: attributes)
                    
                    // Calculate position to place text in center
                    let textRect = CGRect(x: 0, y: (size - 24) / 2, width: size, height: 24)
                    attributedString.draw(in: textRect)
                }
                
                // Reset clipping path for border and status dot
                ctx.cgContext.resetClip()
                
                // Draw glowing border around the rounded rectangle
                let borderPath = UIBezierPath(
                    roundedRect: rectangle.insetBy(dx: 1.5, dy: 1.5),
                    cornerRadius: cornerRadius - 1.5
                )
                ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
                ctx.cgContext.setLineWidth(3.0)
                ctx.cgContext.addPath(borderPath.cgPath)
                ctx.cgContext.strokePath()
                
                // Draw online/offline status dot
                let statusDotSize: CGFloat = 12
                let statusDotX = size - statusDotSize - 2
                let statusDotY = 2 + statusDotSize/2
                
                let statusColor = isOnline ? UIColor.green : UIColor.red
                ctx.cgContext.setFillColor(statusColor.cgColor)
                ctx.cgContext.fillEllipse(in: CGRect(
                    x: statusDotX - statusDotSize/2,
                    y: statusDotY - statusDotSize/2,
                    width: statusDotSize,
                    height: statusDotSize
                ))
                
                // Add white border to status dot
                ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
                ctx.cgContext.setLineWidth(2.0)
                ctx.cgContext.strokeEllipse(in: CGRect(
                    x: statusDotX - statusDotSize/2,
                    y: statusDotY - statusDotSize/2,
                    width: statusDotSize,
                    height: statusDotSize
                ))
            }
        }
        
        @MainActor func refreshUserMarkerWithNewAvatar(for mapView: MapboxMaps.MapView) {
            // Clear cached avatar for current user
            if let avatarUrl = viewModel.currentUser.currentAvatarUrl ?? viewModel.currentUser.profileImageUrl {
                imageCache.removeValue(forKey: avatarUrl)
            }
            
            // Recreate user marker with new avatar
            createUserMarkerImage(for: mapView)
            
            // Update existing user annotation if present
            if let userLocation = viewModel.userLocation {
                updateUserAnnotation(
                    for: mapView,
                    at: userLocation,
                    userName: viewModel.currentUser.fullName
                )
            }
        }
        
        // MARK: - Friend Annotations Update
        
        @MainActor func updateFriendAnnotations(for mapView: MapboxMaps.MapView, friendLocations: [String: UserLocation], friends: [User]) {
            guard let annotationManager = friendAnnotationManager,
                  let expandedAnnotationManager = expandedClusterAnnotationManager else { return }
            
            // Delete all current annotations
            annotationManager.annotations = []
            friendIdByAnnotationId.removeAll()
            clusterIdByAnnotationId.removeAll()
            
            // Group friend locations based on proximity
            let locationGroups = locationGrouper.groupFriendLocations(friendLocations)
            currentLocationGroups = locationGroups
            
            // Create annotations based on group type
            var standardAnnotations: [PointAnnotation] = []
            var expandedAnnotations: [PointAnnotation] = []
            expandedClusterAnnotations = [:]
            
            for group in locationGroups {
                // Generate relative positions for friends in cluster
                var updatedGroup = group
                updatedGroup.generateRelativePositions(radius: 20.0)
                
                // Get unique ID for this group
                let clusterId = group.type == .cluster
                    ? group.friendIds.sorted().joined(separator: "_")
                    : ""
                
                // Check if this is a cluster and if it's expanded
                let isClusterExpanded = group.type == .cluster && locationGrouper.isClusterExpanded(clusterId: clusterId)
                
                switch group.type {
                case .single:
                    // Single friend, add regular marker
                    if let friendId = group.friendIds.first,
                       let friend = friends.first(where: { $0.id == friendId }) {
                        let annotation = createFriendAnnotation(
                            for: friend,
                            at: group.centerCoordinate,
                            mapView: mapView
                        )
                        standardAnnotations.append(annotation)
                    }
                    
                case .cluster:
                    if isClusterExpanded {
                        // Create individual annotations for each friend in the expanded cluster
                        var clusterFriendAnnotations: [PointAnnotation] = []
                        
                        for friendId in group.friendIds {
                            if let friend = friends.first(where: { $0.id == friendId }),
                               let position = updatedGroup.relativePositions[friendId] {
                                
                                let annotation = createFriendAnnotation(
                                    for: friend,
                                    at: position,
                                    mapView: mapView
                                )
                                
                                // Add to the expanded annotations
                                expandedAnnotations.append(annotation)
                                clusterFriendAnnotations.append(annotation)
                                
                                // Store friend ID mapping
                                friendIdByAnnotationId[annotation.id] = friendId
                            }
                        }
                        
                        // Store the expanded annotations for this cluster
                        expandedClusterAnnotations[clusterId] = clusterFriendAnnotations
                        
                    } else {
                        // Show regular cluster marker
                        let clusterFriends = friends.filter { group.friendIds.contains($0.id) }
                        let clusterAnnotation = createClusterAnnotation(
                            for: updatedGroup,
                            friends: clusterFriends,
                            mapView: mapView
                        )
                        standardAnnotations.append(clusterAnnotation)
                        
                        // Store mapping between annotation ID and all friend IDs in this cluster
                        clusterIdByAnnotationId[clusterAnnotation.id] = group.friendIds
                    }
                }
            }
            
            // Add all annotations to appropriate managers
            annotationManager.annotations = standardAnnotations
            expandedAnnotationManager.annotations = expandedAnnotations
            
            // Make sure user annotation is updated last so it stays on top
            if let userLocation = viewModel.userLocation {
                updateUserAnnotation(for: mapView, at: userLocation, userName: viewModel.currentUser.fullName)
            }
        }
        
        // Create an annotation for the current user
        @MainActor private func createUserAnnotation(at coordinate: CLLocationCoordinate2D, userName: String, mapView: MapboxMaps.MapView) -> PointAnnotation {
            // Create user marker image if needed
            createUserMarkerImage(for: mapView)
            
            // Create annotation
            var annotation = PointAnnotation(coordinate: coordinate)
            annotation.iconAnchor = .bottom
            annotation.iconImage = "user-marker-id"
            annotation.iconSize = 1.0
            
            return annotation
        }
        
        // MARK: - Annotation Setup
        
        @MainActor func setupAnnotations(for mapView: MapboxMaps.MapView) {
            print("DEBUG: Setting up annotations")
            
            // Create the annotation managers
            userAnnotationManager = mapView.annotations.makePointAnnotationManager()
            friendAnnotationManager = mapView.annotations.makePointAnnotationManager()
            expandedClusterAnnotationManager = mapView.annotations.makePointAnnotationManager()
            
            // Create the custom image for user location
            createUserMarkerImage(for: mapView)
            
            // Create the custom image for friend locations
            createFriendMarkerImage(for: mapView)
            
            // Update friend markers
            updateFriendAnnotations(
                for: mapView,
                friendLocations: viewModel.friendLocations,
                friends: viewModel.friends
            )
            
            // Set up annotation tap handling through annotationInteractionDelegate
            if let friendManager = friendAnnotationManager {
                friendManager.delegate = self
            }
            
            if let expandedManager = expandedClusterAnnotationManager {
                expandedManager.delegate = self
            }
            
            // Add tap gesture recognizer to handle map taps
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(_:)))
            mapView.addGestureRecognizer(tapGesture)
            
            // Listen for avatar updates
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("AvatarUpdated"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                if let userInfo = notification.userInfo,
                   let userId = userInfo["userId"] as? String,
                   userId == Auth.auth().currentUser?.uid {
                    // Current user's avatar updated, refresh marker
                    self?.refreshUserMarkerWithNewAvatar(for: mapView)
                }
            }
            
            print("DEBUG: Annotations setup complete")
        }
        
        // MARK: - Cluster Animation Helpers
        
        @MainActor private func animateClusterExpansion(
            for clusterId: String,
            at clusterCenter: CLLocationCoordinate2D,
            mapView: MapboxMaps.MapView
        ) {
            // Find the relevant group for this cluster ID
            guard let group = currentLocationGroups.first(where: {
                $0.type == .cluster &&
                $0.friendIds.sorted().joined(separator: "_") == clusterId
            }), let expandedManager = expandedClusterAnnotationManager else {
                return
            }
            
            // Prepare to create expanded annotations for this cluster
            let clusterFriends = viewModel.friends.filter { group.friendIds.contains($0.id) }
            
            var expandedAnnotations: [PointAnnotation] = []
            
            // Create individual friend annotations
            for friendId in group.friendIds {
                if let friend = clusterFriends.first(where: { $0.id == friendId }),
                   let position = group.relativePositions[friendId] {
                    
                    let annotation = createFriendAnnotation(
                        for: friend,
                        at: position,
                        mapView: mapView
                    )
                    
                    // Add cluster info for animation tracking
                    var annotationWithCluster = annotation
                    annotationWithCluster.userInfo?["clusterId"] = clusterId
                    
                    expandedAnnotations.append(annotationWithCluster)
                    
                    // Store mapping for interaction
                    friendIdByAnnotationId[annotationWithCluster.id] = friendId
                }
            }
            
            // Store expanded annotations for reference
            expandedClusterAnnotations[clusterId] = expandedAnnotations
            
            // Start expansion animation
            clusterAnimationManager.animateClusterExpansion(
                annotationManager: expandedManager,
                friendAnnotations: expandedAnnotations,
                clusterCenter: clusterCenter,
                clusterId: clusterId
            )
            
            // Focus camera on the expanded cluster
            mapView.camera.fly(
                to: CameraOptions(
                    center: clusterCenter,
                    zoom: max(15.5, mapView.mapboxMap.cameraState.zoom + 0.5),
                    bearing: mapView.mapboxMap.cameraState.bearing,
                    pitch: mapView.mapboxMap.cameraState.pitch
                ),
                duration: 0.5
            )
        }
        
        private func animateClusterCollapse(
            for clusterId: String,
            at clusterCenter: CLLocationCoordinate2D,
            mapView: MapboxMaps.MapView,
            completion: @escaping () -> Void
        ) {
            guard let expandedAnnotations = expandedClusterAnnotations[clusterId],
                  let expandedManager = expandedClusterAnnotationManager else {
                completion()
                return
            }
            
            // Animate the contraction
            clusterAnimationManager.animateClusterContraction(
                annotationManager: expandedManager,
                friendAnnotations: expandedAnnotations,
                clusterCenter: clusterCenter,
                clusterId: clusterId,
                duration: 0.3,
                completion: completion
            )
        }
        
        // MARK: - Relative Position Calculation
        
        func calculateOffsetPositions(center: CLLocationCoordinate2D, count: Int, radius: Double = 10.0) -> [CLLocationCoordinate2D] {
            guard count > 0 else { return [] }
            
            var positions: [CLLocationCoordinate2D] = []
            
            // If only one friend, return the center
            if count == 1 {
                positions.append(center)
                return positions
            }
            
            // For 2-3 friends, create a more pleasing pattern
            if count == 2 {
                // For 2 friends, place them horizontally next to each other
                let lonFactor = cos(center.latitude * Double.pi / 180.0)
                
                // Friend 1 (left)
                let lonOffset1 = -radius / (111111.0 * lonFactor)
                positions.append(CLLocationCoordinate2D(
                    latitude: center.latitude,
                    longitude: center.longitude + lonOffset1
                ))
                
                // Friend 2 (right)
                let lonOffset2 = radius / (111111.0 * lonFactor)
                positions.append(CLLocationCoordinate2D(
                    latitude: center.latitude,
                    longitude: center.longitude + lonOffset2
                ))
            } else if count == 3 {
                // For 3 friends, place them in a triangle formation
                let lonFactor = cos(center.latitude * Double.pi / 180.0)
                
                // Friend 1 (top)
                let latOffset1 = radius / 111111.0
                positions.append(CLLocationCoordinate2D(
                    latitude: center.latitude + latOffset1,
                    longitude: center.longitude
                ))
                
                // Friend 2 (bottom left)
                let latOffset2 = -radius / (2 * 111111.0)
                let lonOffset2 = -radius / (111111.0 * lonFactor)
                positions.append(CLLocationCoordinate2D(
                    latitude: center.latitude + latOffset2,
                    longitude: center.longitude + lonOffset2
                ))
                
                // Friend 3 (bottom right)
                let latOffset3 = -radius / (2 * 111111.0)
                let lonOffset3 = radius / (111111.0 * lonFactor)
                positions.append(CLLocationCoordinate2D(
                    latitude: center.latitude + latOffset3,
                    longitude: center.longitude + lonOffset3
                ))
            } else {
                // For more than 3 friends, calculate positions in a circle
                let angleStep = (2.0 * Double.pi) / Double(count)
                
                for i in 0..<count {
                    let angle = Double(i) * angleStep
                    
                    // Convert meters to coordinate space
                    // ~111,111 meters per degree of latitude
                    let latOffset = (radius * sin(angle)) / 111111.0
                    
                    // Longitude degrees vary based on latitude
                    let lonFactor = cos(center.latitude * Double.pi / 180.0)
                    let lonOffset = (radius * cos(angle)) / (111111.0 * lonFactor)
                    
                    let position = CLLocationCoordinate2D(
                        latitude: center.latitude + latOffset,
                        longitude: center.longitude + lonOffset
                    )
                    
                    positions.append(position)
                }
            }
            
            return positions
        }
        
        // MARK: - Memory Management
        
        deinit {
            // Clean up observers and caches
            NotificationCenter.default.removeObserver(self)
            imageCache.removeAll()
        }
    }
}

// MARK: - AnnotationInteractionDelegate
extension MapViewRepresentable.Coordinator: AnnotationInteractionDelegate {
    func annotationManager(_ manager: AnnotationManager, didDetectTappedAnnotations annotations: [Annotation]) {
        guard let annotation = annotations.first else { return }
        
        if manager === friendAnnotationManager {
            // Handle tapping on standard annotations (single friends or clusters)
            if let friendId = friendIdByAnnotationId[annotation.id] {
                // Single friend annotation - show friend info panel
                NotificationCenter.default.post(
                    name: NSNotification.Name("FriendSelected"),
                    object: nil,
                    userInfo: ["friendId": friendId]
                )
            } else if let clusterFriendIds = clusterIdByAnnotationId[annotation.id] {
                // Get cluster ID
                let clusterId = clusterFriendIds.sorted().joined(separator: "_")
                print("DEBUG: Cluster tapped with \(clusterFriendIds.count) friends")
                
                // Toggle cluster expansion state
                let isExpanded = locationGrouper.toggleClusterExpansion(clusterId: clusterId)
                
                // Find the cluster center
                if let pointAnnotation = annotation as? PointAnnotation {
                    let clusterCenter = pointAnnotation.point.coordinates
                    
                    // Post a notification to handle this in the parent view
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ClusterToggled"),
                        object: nil,
                        userInfo: [
                            "clusterId": clusterId,
                            "isExpanded": isExpanded,
                            "latitude": clusterCenter.latitude,
                            "longitude": clusterCenter.longitude
                        ]
                    )
                }
            }
        } else if manager === expandedClusterAnnotationManager {
            // Handle tapping on annotations in an expanded cluster
            if let friendId = friendIdByAnnotationId[annotation.id] {
                // Show friend info panel for this specific friend
                NotificationCenter.default.post(
                    name: NSNotification.Name("FriendSelected"),
                    object: nil,
                    userInfo: ["friendId": friendId]
                )
            }
        }
    }
}
