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

        // Update friend annotations with clustering and expansion
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
        private var currentMapZoomLevel: Double = 14.0
        
        // Keep track of current location groups for reference
        private var currentLocationGroups: [LocationGroup] = []
        
        // Image cache for async loading
        private var imageCache: [String: UIImage] = [:]
        
        // Animation management
        private var expansionTimers: [String: Timer] = [:]
        private var animationProgress: [String: Double] = [:]
        
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
                
                // Also collapse all expanded clusters
                collapseAllClusters()
            }
        }
        
        @MainActor func handleZoomLevelChanged(newZoomLevel: Double) {
            // Only track zoom level, don't update camera
            if abs(newZoomLevel - currentMapZoomLevel) > 0.5 {
                print("DEBUG: Zoom level changed from \(currentMapZoomLevel) to \(newZoomLevel)")
                currentMapZoomLevel = newZoomLevel
                
                // Update view model zoom level (but don't trigger camera updates)
                viewModel.updateZoomLevel(newZoomLevel)
                
                // Auto-collapse clusters on zoom out
                if newZoomLevel < 12.0 {
                    collapseAllClusters()
                }
            }
        }
        
        // MARK: - Cluster Management
        
        private func collapseAllClusters() {
            // Stop all expansion animations
            for timer in expansionTimers.values {
                timer.invalidate()
            }
            expansionTimers.removeAll()
            animationProgress.removeAll()
            
            // Clear expanded annotations
            expandedClusterAnnotationManager?.annotations = []
            expandedClusterAnnotations.removeAll()
            
            // Collapse all clusters in view model
            viewModel.friendLocationGrouper.collapseAllClusters()
            
            print("DEBUG: Collapsed all clusters")
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
        
        // Create an annotation for a single friend with avatar
        private func createFriendAnnotation(for friend: User, at coordinate: CLLocationCoordinate2D, mapView: MapboxMaps.MapView, isExpanded: Bool = false) -> PointAnnotation {
            let isOnline = friend.isOnline
            
            // Create marker image for this friend with their avatar
            createFriendMarkerImage(
                for: mapView,
                friendId: friend.id,
                name: friend.fullName,
                isOnline: isOnline,
                profileImageUrl: friend.currentAvatarUrl,
                isExpanded: isExpanded
            )
            
            // Create annotation
            var annotation = PointAnnotation(coordinate: coordinate)
            annotation.iconAnchor = .center
            
            let markerIconId = "friend-marker-\(friend.id)\(isExpanded ? "-expanded" : "")"
            annotation.iconImage = markerIconId
            annotation.iconSize = isExpanded ? 0.8 : 1.0 // Slightly smaller when expanded
            
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

        // Updated method to load friend avatars asynchronously
        func createFriendMarkerImage(for mapView: MapboxMaps.MapView, friendId: String? = nil, name: String? = nil, isOnline: Bool = false, profileImageUrl: String? = nil, isExpanded: Bool = false) {
            let size: CGFloat = isExpanded ? 50 : 55 // Slightly different size for expanded
            
            if let avatarUrlString = profileImageUrl {
                // Load image asynchronously
                loadImageAsync(from: avatarUrlString) { [weak self] avatarImage in
                    let markerImage = self?.generateFriendMarkerImage(
                        size: size,
                        name: name,
                        isOnline: isOnline,
                        avatarImage: avatarImage,
                        isExpanded: isExpanded
                    )
                    
                    guard let image = markerImage else { return }
                    
                    let markerId = friendId != nil ? "friend-marker-\(friendId!)\(isExpanded ? "-expanded" : "")" : "friend-marker-default"
                    
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
                    avatarImage: nil,
                    isExpanded: isExpanded
                )
                
                let markerId = friendId != nil ? "friend-marker-\(friendId!)\(isExpanded ? "-expanded" : "")" : "friend-marker-default"
                
                do {
                    try mapView.mapboxMap.style.addImage(markerImage, id: markerId)
                    print("DEBUG: Successfully added friend marker for \(name ?? "Unknown") without avatar")
                } catch {
                    print("DEBUG: Error adding friend marker image: \(error.localizedDescription)")
                }
            }
        }
        
        private func generateFriendMarkerImage(size: CGFloat, name: String?, isOnline: Bool, avatarImage: UIImage?, isExpanded: Bool = false) -> UIImage {
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
                
                // Draw border around the circle - different style for expanded
                let borderPath = UIBezierPath(
                    roundedRect: rectangle.insetBy(dx: 2, dy: 2),
                    cornerRadius: cornerRadius - 2
                )
                ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
                ctx.cgContext.setLineWidth(isExpanded ? 2.0 : 3.0)
                ctx.cgContext.addPath(borderPath.cgPath)
                ctx.cgContext.strokePath()
                
                // Draw online/offline status border
                let statusPath = UIBezierPath(
                    roundedRect: rectangle.insetBy(dx: 0.5, dy: 0.5),
                    cornerRadius: cornerRadius - 0.5
                )
                let statusColor = isOnline ? UIColor.systemGreen : UIColor.systemGray
                ctx.cgContext.setStrokeColor(statusColor.cgColor)
                ctx.cgContext.setLineWidth(isExpanded ? 1.5 : 2.0)
                ctx.cgContext.addPath(statusPath.cgPath)
                ctx.cgContext.strokePath()
                
                // Add subtle glow for expanded markers
                if isExpanded {
                    let glowPath = UIBezierPath(
                        roundedRect: rectangle.insetBy(dx: -1, dy: -1),
                        cornerRadius: cornerRadius + 1
                    )
                    ctx.cgContext.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.3).cgColor)
                    ctx.cgContext.setLineWidth(1.0)
                    ctx.cgContext.addPath(glowPath.cgPath)
                    ctx.cgContext.strokePath()
                }
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
        
        // MARK: - Friend Annotations Update with Clustering and Animation
        
        @MainActor func updateFriendAnnotations(for mapView: MapboxMaps.MapView, viewModel: LocationViewModel) {
            guard let annotationManager = friendAnnotationManager,
                  let expandedAnnotationManager = expandedClusterAnnotationManager else { return }
            
            print("DEBUG: Updating friend annotations with \(viewModel.friendLocations.count) locations")
            
            // Get location groups from viewModel
            let locationGroups = viewModel.getLocationGroups()
            currentLocationGroups = locationGroups
            
            print("DEBUG: Generated \(locationGroups.count) location groups")
            
            // Clear existing annotations except expanded ones that are animating
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
                        // Start expansion animation if not already expanded
                        if expandedClusterAnnotations[clusterId] == nil {
                            startClusterExpansionAnimation(
                                clusterId: clusterId,
                                group: group,
                                mapView: mapView,
                                expandedAnnotationManager: expandedAnnotationManager
                            )
                        } else {
                            // Already expanded, just update positions
                            let clusterFriends = viewModel.friends.filter { group.friendIds.contains($0.id) }
                            
                            for friend in clusterFriends {
                                if let position = group.relativePositions[friend.id] {
                                    let annotation = createFriendAnnotation(
                                        for: friend,
                                        at: position,
                                        mapView: mapView,
                                        isExpanded: true
                                    )
                                    expandedAnnotations.append(annotation)
                                    friendIdByAnnotationId[annotation.id] = friend.id
                                }
                            }
                            expandedClusterAnnotations[clusterId] = expandedAnnotations
                        }
                        
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
                        
                        // If this cluster was expanded before, start contraction animation
                        if let expandedAnnotations = expandedClusterAnnotations[clusterId] {
                            startClusterContractionAnimation(
                                clusterId: clusterId,
                                targetCenter: group.centerCoordinate,
                                expandedAnnotationManager: expandedAnnotationManager
                            )
                        }
                    }
                }
            }
            
            // Update annotation managers
            annotationManager.annotations = standardAnnotations
            
            // Update expanded annotations if not animating
            for (clusterId, annotations) in expandedClusterAnnotations {
                if expansionTimers[clusterId] == nil {
                    expandedAnnotationManager.annotations = Array(expandedClusterAnnotations.values.flatMap { $0 })
                }
            }
            
            print("DEBUG: Added \(standardAnnotations.count) standard annotations and \(expandedClusterAnnotations.count) expanded clusters")
            
            // Make sure user annotation is updated last so it stays on top
            if let userLocation = viewModel.userLocation {
                updateUserAnnotation(for: mapView, at: userLocation, userName: viewModel.currentUser.fullName)
            }
        }
        
        // MARK: - Cluster Animation Methods
        
        @MainActor private func startClusterExpansionAnimation(
            clusterId: String,
            group: LocationGroup,
            mapView: MapboxMaps.MapView,
            expandedAnnotationManager: PointAnnotationManager
        ) {
            print("DEBUG: Starting expansion animation for cluster \(clusterId)")
            
            // Stop any existing animation for this cluster
            expansionTimers[clusterId]?.invalidate()
            
            let friends = viewModel.friends.filter { group.friendIds.contains($0.id) }
            let animationDuration: TimeInterval = 0.4
            let frameInterval: TimeInterval = 0.016 // ~60fps
            
            // Create initial annotations at cluster center
            var animatingAnnotations: [PointAnnotation] = []
            
            for friend in friends {
                let annotation = createFriendAnnotation(
                    for: friend,
                    at: group.centerCoordinate,
                    mapView: mapView,
                    isExpanded: true
                )
                animatingAnnotations.append(annotation)
                friendIdByAnnotationId[annotation.id] = friend.id
            }
            
            // Store the annotations
            expandedClusterAnnotations[clusterId] = animatingAnnotations
            expandedAnnotationManager.annotations = Array(expandedClusterAnnotations.values.flatMap { $0 })
            
            // Start animation timer
            animationProgress[clusterId] = 0.0
            
            let timer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                let currentProgress = self.animationProgress[clusterId] ?? 0.0
                let newProgress = min(1.0, currentProgress + frameInterval / animationDuration)
                
                // Update positions using eased progress
                let keyframes = group.getExpansionKeyframes(progress: newProgress)
                self.updateExpandedAnnotationPositions(
                    clusterId: clusterId,
                    keyframes: keyframes,
                    expandedAnnotationManager: expandedAnnotationManager
                )
                
                self.animationProgress[clusterId] = newProgress
                
                // Complete animation
                if newProgress >= 1.0 {
                    timer.invalidate()
                    self.expansionTimers.removeValue(forKey: clusterId)
                    self.animationProgress.removeValue(forKey: clusterId)
                    print("DEBUG: Completed expansion animation for cluster \(clusterId)")
                }
            }
            
            expansionTimers[clusterId] = timer
        }
        
        private func startClusterContractionAnimation(
            clusterId: String,
            targetCenter: CLLocationCoordinate2D,
            expandedAnnotationManager: PointAnnotationManager
        ) {
            print("DEBUG: Starting contraction animation for cluster \(clusterId)")
            
            // Stop any existing animation
            expansionTimers[clusterId]?.invalidate()
            
            guard let group = currentLocationGroups.first(where: {
                $0.type == .cluster &&
                $0.friendIds.sorted().joined(separator: "_") == clusterId
            }) else {
                // Remove expanded annotations immediately if no group found
                expandedClusterAnnotations.removeValue(forKey: clusterId)
                expandedAnnotationManager.annotations = Array(expandedClusterAnnotations.values.flatMap { $0 })
                return
            }
            
            let animationDuration: TimeInterval = 0.3
            let frameInterval: TimeInterval = 0.016
            
            animationProgress[clusterId] = 0.0
            
            let timer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                let currentProgress = self.animationProgress[clusterId] ?? 0.0
                let newProgress = min(1.0, currentProgress + frameInterval / animationDuration)
                
                // Update positions using contraction keyframes
                let keyframes = group.getContractionKeyframes(progress: newProgress)
                self.updateExpandedAnnotationPositions(
                    clusterId: clusterId,
                    keyframes: keyframes,
                    expandedAnnotationManager: expandedAnnotationManager
                )
                
                self.animationProgress[clusterId] = newProgress
                
                // Complete animation
                if newProgress >= 1.0 {
                    timer.invalidate()
                    self.expansionTimers.removeValue(forKey: clusterId)
                    self.animationProgress.removeValue(forKey: clusterId)
                    
                    // Remove expanded annotations
                    self.expandedClusterAnnotations.removeValue(forKey: clusterId)
                    expandedAnnotationManager.annotations = Array(self.expandedClusterAnnotations.values.flatMap { $0 })
                    
                    print("DEBUG: Completed contraction animation for cluster \(clusterId)")
                }
            }
            
            expansionTimers[clusterId] = timer
        }
        
        private func updateExpandedAnnotationPositions(
            clusterId: String,
            keyframes: [String: CLLocationCoordinate2D],
            expandedAnnotationManager: PointAnnotationManager
        ) {
            guard var annotations = expandedClusterAnnotations[clusterId] else { return }
            
            // Update positions
            for i in 0..<annotations.count {
                let friendId = friendIdByAnnotationId[annotations[i].id]
                if let friendId = friendId, let newPosition = keyframes[friendId] {
                    annotations[i].point = Point(newPosition)
                }
            }
            
            // Update stored annotations
            expandedClusterAnnotations[clusterId] = annotations
            
            // Update annotation manager
            expandedAnnotationManager.annotations = Array(expandedClusterAnnotations.values.flatMap { $0 })
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
            // Clean up observers, caches, and timers
            NotificationCenter.default.removeObserver(self)
            imageCache.removeAll()
            
            for timer in expansionTimers.values {
                timer.invalidate()
            }
            expansionTimers.removeAll()
            animationProgress.removeAll()
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
