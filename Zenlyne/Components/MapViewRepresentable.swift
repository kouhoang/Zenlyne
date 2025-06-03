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
        
        // Enable map interactions
        mapView.gestures.options.panEnabled = true
        mapView.gestures.options.pinchEnabled = true
        mapView.gestures.options.rotateEnabled = true
        mapView.gestures.options.pitchEnabled = true
        
        // Configure map with initial options ONLY
        mapView.mapboxMap.onNext(event: .mapLoaded) { _ in
            // Set camera to initial position only once
            mapView.camera.fly(to: viewModel.cameraOptions, duration: 0.25)
            
            // Setup point annotation manager for markers
            context.coordinator.setupAnnotations(for: mapView)
        }
        
        // Add camera change listener to track zoom level (but don't update camera)
        mapView.mapboxMap.onEvery(event: .cameraChanged) { event in
            let newZoom = mapView.cameraState.zoom
            Task { @MainActor in
                context.coordinator.handleZoomLevelChanged(newZoomLevel: newZoom)
            }
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

        // ONLY update camera if explicitly requested via shouldUpdateCamera flag
        if viewModel.shouldUpdateCamera {
            mapView.camera.fly(to: viewModel.cameraOptions, duration: 0.5)
            viewModel.shouldUpdateCamera = false
        }

        // Update user position
        if let userLocation = viewModel.userLocation {
            context.coordinator.updateUserAnnotation(
                for: mapView,
                at: userLocation,
                userName: viewModel.currentUser.fullName
            )
        }

        // Update friend annotations with clustering
        context.coordinator.updateFriendAnnotations(
            for: mapView,
            viewModel: viewModel
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
            handleMapTapSafely(gesture)
        }
        
        @objc func handleMapTapSafely(_ gesture: UITapGestureRecognizer) {
            Task { @MainActor in
                // When the user taps on the map (not on a marker),
                // send a notification to close the friend info panel if it's displayed
                NotificationCenter.default.post(name: NSNotification.Name("MapTapped"), object: nil)
            }
        }
        
        @MainActor func handleZoomLevelChanged(newZoomLevel: Double) {
            // Only track zoom level, don't update camera
            if abs(newZoomLevel - currentMapZoomLevel) > 0.5 {
                print("DEBUG: Zoom level changed from \(currentMapZoomLevel) to \(newZoomLevel)")
                currentMapZoomLevel = newZoomLevel
                
                // Update view model zoom level (but don't trigger camera updates)
                viewModel.updateZoomLevel(newZoomLevel)
            }
        }
        
        // MARK: - Async Image Loading
        
        private func loadImageAsync(from urlString: String, completion: @escaping (UIImage?) -> Void) {
            loadImageAsyncSafely(from: urlString) { image in
                completion(image)
            }
        }
        
        private func loadImageAsyncSafely(from urlString: String, completion: @escaping @MainActor (UIImage?) -> Void) {
            // Check cache first on current queue
            if let cachedImage = imageCache[urlString] {
                Task { @MainActor in
                    completion(cachedImage)
                }
                return
            }
            
            guard let url = URL(string: urlString) else {
                Task { @MainActor in
                    completion(nil)
                }
                return
            }
            
            URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
                guard let data = data, error == nil, let image = UIImage(data: data) else {
                    Task { @MainActor in
                        completion(nil)
                    }
                    return
                }
                
                // Cache the image on main actor
                Task { @MainActor in
                    self?.imageCache[urlString] = image
                    completion(image)
                }
            }.resume()
        }
        
        // MARK: - Annotation Creation
        
        @MainActor func createUserMarkerImage(for mapView: MapboxMaps.MapView) {
            let size: CGFloat = 60
            
            // Use current avatar URL with consistent property name
            let avatarUrl = viewModel.currentUser.currentAvatarUrl
            
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
                let cornerRadius: CGFloat = size/2 // Make it circular
                
                // Apply rounded corners for clipping
                let bezierPath = UIBezierPath(
                    roundedRect: rectangle,
                    cornerRadius: cornerRadius
                )
                ctx.cgContext.addPath(bezierPath.cgPath)
                ctx.cgContext.clip()
                
                if let image = avatarImage {
                    // Draw avatar image filling the entire circle
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
                        .font: UIFont.systemFont(ofSize: size * 0.3, weight: .bold),
                        .foregroundColor: UIColor.white,
                        .paragraphStyle: paragraphStyle
                    ]
                    
                    let attributedString = NSAttributedString(string: initials, attributes: attributes)
                    
                    // Calculate position to place text in center
                    let textRect = CGRect(x: 0, y: (size - size * 0.4) / 2, width: size, height: size * 0.4)
                    attributedString.draw(in: textRect)
                }
                
                // Reset clipping path for border
                ctx.cgContext.resetClip()
                
                // Draw glowing border around the circle
                let borderPath = UIBezierPath(
                    roundedRect: rectangle.insetBy(dx: 2, dy: 2),
                    cornerRadius: cornerRadius - 2
                )
                ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
                ctx.cgContext.setLineWidth(4.0)
                ctx.cgContext.addPath(borderPath.cgPath)
                ctx.cgContext.strokePath()
                
                // Add blue glow for current user
                let glowPath = UIBezierPath(
                    roundedRect: rectangle.insetBy(dx: 0.5, dy: 0.5),
                    cornerRadius: cornerRadius - 0.5
                )
                ctx.cgContext.setStrokeColor(UIColor.systemBlue.cgColor)
                ctx.cgContext.setLineWidth(2.0)
                ctx.cgContext.addPath(glowPath.cgPath)
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
            pointAnnotation.iconAnchor = .center
            pointAnnotation.iconImage = "user-marker-id"
            pointAnnotation.iconSize = 1.0
            
            // Add the annotation to the manager
            annotationManager.annotations = [pointAnnotation]
            
            print("DEBUG: Updated user annotation at \(coordinate.latitude), \(coordinate.longitude)")
        }
        
        // Create an annotation for a single friend (now looks like user annotation)
        private func createFriendAnnotation(for friend: User, at coordinate: CLLocationCoordinate2D, mapView: MapboxMaps.MapView) -> PointAnnotation {
            let isOnline = friend.isOnline
            
            // Create marker image for this friend with their avatar (same style as user)
            createFriendMarkerImage(
                for: mapView,
                friendId: friend.id,
                name: friend.fullName,
                isOnline: isOnline,
                profileImageUrl: friend.currentAvatarUrl
            )
            
            // Create annotation
            var annotation = PointAnnotation(coordinate: coordinate)
            annotation.iconAnchor = .center
            
            let markerIconId = "friend-marker-\(friend.id)"
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
            annotation.iconAnchor = .center
            annotation.iconImage = clusterId
            annotation.iconSize = 1.0
            
            // Store the cluster ID in the annotation's properties for later reference
            annotation.userInfo?["clusterId"] = clusterId
            
            return annotation
        }

        // Updated method to load friend avatars asynchronously (same style as user)
        func createFriendMarkerImage(for mapView: MapboxMaps.MapView, friendId: String? = nil, name: String? = nil, isOnline: Bool = false, profileImageUrl: String? = nil) {
            let size: CGFloat = 55 // Slightly smaller than user
            
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
                    
                    let markerId = friendId != nil ? "friend-marker-\(friendId!)" : "friend-marker-default"
                    
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
                
                let markerId = friendId != nil ? "friend-marker-\(friendId!)" : "friend-marker-default"
                
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
                let cornerRadius: CGFloat = size/2 // Make it circular
                
                // Apply rounded corners for clipping
                let bezierPath = UIBezierPath(
                    roundedRect: rectangle,
                    cornerRadius: cornerRadius
                )
                ctx.cgContext.addPath(bezierPath.cgPath)
                ctx.cgContext.clip()
                
                if let image = avatarImage {
                    // Draw avatar image filling the entire circle
                    image.draw(in: rectangle)
                } else {
                    // Create gradient background - different colors for online/offline
                    let colors: [CGColor]
                    if isOnline {
                        // Green color for online friends
                        colors = [
                            UIColor(red: 0.0, green: 0.8, blue: 0.4, alpha: 0.9).cgColor,
                            UIColor(red: 0.0, green: 0.6, blue: 0.3, alpha: 0.9).cgColor
                        ]
                    } else {
                        // Gray color for offline friends
                        colors = [
                            UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 0.9).cgColor,
                            UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 0.9).cgColor
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
                    let words = fullName.split(separator: " ")
                    let initials: String
                    if words.count >= 2 {
                        initials = String(words[0].prefix(1)).uppercased() + String(words[1].prefix(1)).uppercased()
                    } else if let first = words.first {
                        initials = String(first.prefix(1)).uppercased()
                    } else {
                        initials = "F"
                    }
                    
                    // Draw initials in center
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.alignment = .center
                    
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: size * 0.3, weight: .bold),
                        .foregroundColor: UIColor.white,
                        .paragraphStyle: paragraphStyle
                    ]
                    
                    let attributedString = NSAttributedString(string: initials, attributes: attributes)
                    
                    // Calculate position to place text in center
                    let textRect = CGRect(x: 0, y: (size - size * 0.4) / 2, width: size, height: size * 0.4)
                    attributedString.draw(in: textRect)
                }
                
                // Reset clipping path for border and status dot
                ctx.cgContext.resetClip()
                
                // Draw border around the circle
                let borderPath = UIBezierPath(
                    roundedRect: rectangle.insetBy(dx: 2, dy: 2),
                    cornerRadius: cornerRadius - 2
                )
                ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
                ctx.cgContext.setLineWidth(3.0)
                ctx.cgContext.addPath(borderPath.cgPath)
                ctx.cgContext.strokePath()
                
                // Draw online/offline status border
                let statusPath = UIBezierPath(
                    roundedRect: rectangle.insetBy(dx: 0.5, dy: 0.5),
                    cornerRadius: cornerRadius - 0.5
                )
                let statusColor = isOnline ? UIColor.systemGreen : UIColor.systemGray
                ctx.cgContext.setStrokeColor(statusColor.cgColor)
                ctx.cgContext.setLineWidth(2.0)
                ctx.cgContext.addPath(statusPath.cgPath)
                ctx.cgContext.strokePath()
            }
        }
        
        @MainActor func refreshUserMarkerWithNewAvatar(for mapView: MapboxMaps.MapView) {
            // Clear cached avatar for current user
            if let avatarUrl = viewModel.currentUser.currentAvatarUrl {
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
        
        // MARK: - Friend Annotations Update with Clustering
        
        @MainActor func updateFriendAnnotations(for mapView: MapboxMaps.MapView, viewModel: LocationViewModel) {
            guard let annotationManager = friendAnnotationManager,
                  let expandedAnnotationManager = expandedClusterAnnotationManager else { return }
            
            print("DEBUG: Updating friend annotations with \(viewModel.friendLocations.count) locations")
            
            // Delete all current annotations
            annotationManager.annotations = []
            expandedAnnotationManager.annotations = []
            friendIdByAnnotationId.removeAll()
            clusterIdByAnnotationId.removeAll()
            expandedClusterAnnotations.removeAll()
            
            // Get location groups from viewModel
            let locationGroups = viewModel.getLocationGroups()
            currentLocationGroups = locationGroups
            
            print("DEBUG: Generated \(locationGroups.count) location groups")
            
            // Create annotations based on group type
            var standardAnnotations: [PointAnnotation] = []
            var expandedAnnotations: [PointAnnotation] = []
            
            for group in locationGroups {
                let clusterId = group.type == .cluster
                    ? group.friendIds.sorted().joined(separator: "_")
                    : ""
                
                // Check if this is a cluster and if it's expanded
                let isClusterExpanded = group.type == .cluster && viewModel.isClusterExpanded(clusterId: clusterId)
                
                print("DEBUG: Processing group with \(group.count) friends, type: \(group.type), expanded: \(isClusterExpanded)")
                
                switch group.type {
                case .single:
                    // Single friend, add regular marker (avatar style)
                    if let friendId = group.friendIds.first,
                       let friend = viewModel.friends.first(where: { $0.id == friendId }) {
                        let annotation = createFriendAnnotation(
                            for: friend,
                            at: group.centerCoordinate,
                            mapView: mapView
                        )
                        standardAnnotations.append(annotation)
                        print("DEBUG: Added single friend annotation for \(friend.fullName)")
                    }
                    
                case .cluster:
                    if isClusterExpanded {
                        // Create individual annotations for each friend in the expanded cluster
                        var clusterFriendAnnotations: [PointAnnotation] = []
                        
                        // Generate relative positions for expansion
                        var expandedGroup = group
                        expandedGroup.generateRelativePositions(radius: 30.0)
                        
                        for friendId in group.friendIds {
                            if let friend = viewModel.friends.first(where: { $0.id == friendId }),
                               let position = expandedGroup.relativePositions[friendId] {
                                
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
                                
                                print("DEBUG: Added expanded annotation for \(friend.fullName)")
                            }
                        }
                        
                        // Store the expanded annotations for this cluster
                        expandedClusterAnnotations[clusterId] = clusterFriendAnnotations
                        
                    } else {
                        // Show regular cluster marker
                        let clusterFriends = viewModel.friends.filter { group.friendIds.contains($0.id) }
                        let clusterAnnotation = createClusterAnnotation(
                            for: group,
                            friends: clusterFriends,
                            mapView: mapView
                        )
                        standardAnnotations.append(clusterAnnotation)
                        
                        // Store mapping between annotation ID and all friend IDs in this cluster
                        clusterIdByAnnotationId[clusterAnnotation.id] = group.friendIds
                        
                        print("DEBUG: Added cluster annotation with \(group.friendIds.count) friends")
                    }
                }
            }
            
            // Add all annotations to appropriate managers
            annotationManager.annotations = standardAnnotations
            expandedAnnotationManager.annotations = expandedAnnotations
            
            print("DEBUG: Added \(standardAnnotations.count) standard annotations and \(expandedAnnotations.count) expanded annotations")
            
            // Make sure user annotation is updated last so it stays on top
            if let userLocation = viewModel.userLocation {
                updateUserAnnotation(for: mapView, at: userLocation, userName: viewModel.currentUser.fullName)
            }
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
            updateFriendAnnotations(for: mapView, viewModel: viewModel)
            
            // Set up annotation tap handling through annotationInteractionDelegate
            if let friendManager = friendAnnotationManager {
                friendManager.delegate = self
            }
            
            if let expandedManager = expandedClusterAnnotationManager {
                expandedManager.delegate = self
            }
            
            // Add tap gesture recognizer to handle map taps
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleMapTapSafely(_:)))
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
    @MainActor func annotationManager(_ manager: AnnotationManager, didDetectTappedAnnotations annotations: [Annotation]) {
        guard let annotation = annotations.first else { return }
        
        if manager === friendAnnotationManager {
            // Handle tapping on standard annotations (single friends or clusters)
            if let friendId = friendIdByAnnotationId[annotation.id] {
                // Single friend annotation - show friend info panel
                print("DEBUG: Single friend tapped: \(friendId)")
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
                let isExpanded = viewModel.toggleClusterExpansion(clusterId: clusterId)
                
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
                print("DEBUG: Expanded cluster friend tapped: \(friendId)")
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
