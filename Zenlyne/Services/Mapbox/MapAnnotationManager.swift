//
//  MapAnnotationManager.swift
//  Zenlyne
//
//  Created by kou on 4/6/25.
//

import SwiftUI
@preconcurrency import MapboxMaps
import CoreLocation
import FirebaseAuth

@MainActor
class MapAnnotationManager: NSObject {
    private let mapView: MapboxMaps.MapView
    private let viewModel: LocationViewModel
    
    // Annotation managers
    private var userAnnotationManager: PointAnnotationManager?
    private var friendAnnotationManager: PointAnnotationManager?
    private var expandedClusterAnnotationManager: PointAnnotationManager?
    
    // Tracking data
    private var lastUserLocation: CLLocationCoordinate2D?
    private var lastFriendLocations: [String: UserLocation] = [:]
    private var lastLocationGroups: [LocationGroup] = []
    
    // Annotation mappings
    private var friendIdByAnnotationId: [String: String] = [:]
    private var clusterIdByAnnotationId: [String: [String]] = [:]
    private var sameLocationGroupIdByAnnotationId: [String: [String]] = [:]
    private var expandedClusterAnnotations: [String: [PointAnnotation]] = [:]
    
    // Image cache and timers
    private var imageCache: [String: UIImage] = [:]
    private var expansionTimers: [String: Timer] = [:]
    private var animationProgress: [String: Double] = [:]
    
    init(mapView: MapboxMaps.MapView, viewModel: LocationViewModel) {
        self.mapView = mapView
        self.viewModel = viewModel
        super.init()
    }
    
    // MARK: - Setup Methods
    
    func setupAnnotations() {
        print("DEBUG: Setting up annotations")
        
        userAnnotationManager = mapView.annotations.makePointAnnotationManager()
        friendAnnotationManager = mapView.annotations.makePointAnnotationManager()
        expandedClusterAnnotationManager = mapView.annotations.makePointAnnotationManager()
        
        createUserMarkerImage()
        createFriendMarkerImage()
        
        updateFriendAnnotations()
        
        // Set up tap handlers
        setupTapHandlers()
        
        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(_:)))
        mapView.addGestureRecognizer(tapGesture)
        
        setupNotificationObservers()
    }
    
    private func setupTapHandlers() {
        // Modern Mapbox doesn't have onAnnotationTap property
        // All tap handling will be done through gesture recognizer
        print("DEBUG: Setting up annotation tap handling through gesture recognizer")
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AvatarUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let userInfo = notification.userInfo,
               let userId = userInfo["userId"] as? String,
               userId == Auth.auth().currentUser?.uid {
                // Use Task @MainActor to call main actor method
                Task { @MainActor [weak self] in
                    self?.refreshUserMarkerWithNewAvatar()
                }
            }
        }
    }
    
    // MARK: - Update Methods
    
    func updateAnnotations(with viewModel: LocationViewModel) {
        // Update user position if changed
        if let userLocation = viewModel.userLocation {
            let hasUserLocationChanged = hasUserLocationChanged(userLocation)
            if hasUserLocationChanged {
                updateUserAnnotation(at: userLocation, userName: viewModel.currentUser.fullName)
            }
        }
        
        // Update friend annotations with smart diffing
        updateFriendAnnotationsSelectively(viewModel: viewModel)
    }
    
    private func updateFriendAnnotationsSelectively(viewModel: LocationViewModel) {
        guard let _ = friendAnnotationManager,
              let _ = expandedClusterAnnotationManager else { return }
        
        let currentFriendLocations = viewModel.friendLocations
        let hasLocationChanges = !areFriendLocationsSame(currentFriendLocations, lastFriendLocations)
        
        let currentLocationGroups = viewModel.getLocationGroups()
        let hasGroupChanges = !areLocationGroupsSame(currentLocationGroups, lastLocationGroups)
        
        if !hasLocationChanges && !hasGroupChanges {
            print("DEBUG: No changes in friend locations or groups, skipping update")
            return
        }
        
        print("DEBUG: Selective update - locations changed: \(hasLocationChanges), groups changed: \(hasGroupChanges)")
        
        lastFriendLocations = currentFriendLocations
        lastLocationGroups = currentLocationGroups
        
        updateFriendAnnotations()
    }
    
    private func updateFriendAnnotations() {
        guard let annotationManager = friendAnnotationManager,
              let expandedAnnotationManager = expandedClusterAnnotationManager else { return }
        
        print("DEBUG: Updating friend annotations with \(viewModel.friendLocations.count) locations")
        
        let locationGroups = viewModel.getLocationGroups()
        
        var standardAnnotations: [PointAnnotation] = []
        
        // Clear previous mappings
        clusterIdByAnnotationId.removeAll()
        sameLocationGroupIdByAnnotationId.removeAll()
        
        for group in locationGroups {
            let groupId = group.friendIds.sorted().joined(separator: "_")
            
            switch group.type {
            case .single:
                if let friendId = group.friendIds.first,
                   let friend = viewModel.friends.first(where: { $0.id == friendId }) {
                    let annotation = createFriendAnnotation(
                        for: friend,
                        at: group.centerCoordinate,
                        isExpanded: false
                    )
                    standardAnnotations.append(annotation)
                    print("DEBUG: Added single friend annotation for \(friend.fullName)")
                }
                
            case .sameLocation:
                let groupFriends = viewModel.friends.filter { group.friendIds.contains($0.id) }
                let sameLocationAnnotation = createSameLocationAnnotation(
                    for: group,
                    friends: groupFriends
                )
                standardAnnotations.append(sameLocationAnnotation)
                sameLocationGroupIdByAnnotationId[sameLocationAnnotation.id] = group.friendIds
                print("DEBUG: Added same-location annotation with \(group.friendIds.count) friends")
                
            case .cluster:
                let isClusterExpanded = viewModel.isClusterExpanded(clusterId: groupId)
                
                if isClusterExpanded {
                    handleExpandedCluster(group: group, groupId: groupId, expandedAnnotationManager: expandedAnnotationManager)
                } else {
                    let clusterFriends = viewModel.friends.filter { group.friendIds.contains($0.id) }
                    let clusterAnnotation = createClusterAnnotation(for: group, friends: clusterFriends)
                    standardAnnotations.append(clusterAnnotation)
                    clusterIdByAnnotationId[clusterAnnotation.id] = group.friendIds
                    
                    print("DEBUG: Added cluster annotation with \(group.friendIds.count) friends")
                    
                    if expandedClusterAnnotations[groupId] != nil {
                        startClusterContractionAnimation(
                            clusterId: groupId,
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
        for (clusterId, _) in expandedClusterAnnotations {
            if expansionTimers[clusterId] == nil {
                expandedAnnotationManager.annotations = Array(expandedClusterAnnotations.values.flatMap { $0 })
            }
        }
        
        print("DEBUG: Added \(standardAnnotations.count) standard annotations and \(expandedClusterAnnotations.count) expanded clusters")
        
        // Make sure user annotation is updated last so it stays on top
        if let userLocation = viewModel.userLocation {
            updateUserAnnotation(at: userLocation, userName: viewModel.currentUser.fullName)
        }
    }
    
    // MARK: - User Location Updates
    
    private func hasUserLocationChanged(_ newLocation: CLLocationCoordinate2D) -> Bool {
        guard let lastLocation = lastUserLocation else {
            lastUserLocation = newLocation
            return true
        }
        
        let threshold: Double = 0.0001 // ~10 meters
        let hasChanged = abs(lastLocation.latitude - newLocation.latitude) > threshold ||
                       abs(lastLocation.longitude - newLocation.longitude) > threshold
        
        if hasChanged {
            lastUserLocation = newLocation
            print("DEBUG: User location changed significantly")
        }
        
        return hasChanged
    }
    
    private func updateUserAnnotation(at coordinate: CLLocationCoordinate2D, userName: String) {
        guard let annotationManager = userAnnotationManager else {
            print("DEBUG: User annotation manager is nil")
            return
        }
        
        createUserMarkerImage()
        annotationManager.annotations = []
        
        var pointAnnotation = PointAnnotation(coordinate: coordinate)
        pointAnnotation.iconAnchor = .center
        pointAnnotation.iconImage = "user-marker-id"
        pointAnnotation.iconSize = 1.0
        
        annotationManager.annotations = [pointAnnotation]
        
        print("DEBUG: Updated user annotation at \(coordinate.latitude), \(coordinate.longitude)")
    }
    
    // MARK: - Image Creation Methods
    
    func createUserMarkerImage() {
        let size: CGFloat = 60
        let avatarUrl = viewModel.currentUser.currentAvatarUrl
        
        if let avatarUrlString = avatarUrl {
            loadImageAsync(from: avatarUrlString) { [weak self] avatarImage in
                let annotationImage = self?.generateUserMarkerImage(size: size, avatarImage: avatarImage)
                guard let image = annotationImage else { return }
                
                do {
                    try self?.mapView.mapboxMap.addImage(image, id: "user-marker-id")
                    print("DEBUG: Successfully added user marker image with avatar")
                } catch {
                    print("DEBUG: Error adding user marker image: \(error.localizedDescription)")
                }
            }
        } else {
            let annotationImage = generateUserMarkerImage(size: size, avatarImage: nil)
            
            do {
                try mapView.mapboxMap.addImage(annotationImage, id: "user-marker-id")
                print("DEBUG: Successfully added user marker image without avatar")
            } catch {
                print("DEBUG: Error adding user marker image: \(error.localizedDescription)")
            }
        }
    }
    
    func createFriendMarkerImage(friendId: String? = nil, name: String? = nil, isOnline: Bool = false, profileImageUrl: String? = nil, isExpanded: Bool = false) {
        let size: CGFloat = isExpanded ? 50 : 55
        
        if let avatarUrlString = profileImageUrl {
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
                    try self?.mapView.mapboxMap.addImage(image, id: markerId)
                    print("DEBUG: Successfully added friend marker for \(name ?? "Unknown") with avatar")
                } catch {
                    print("DEBUG: Error adding friend marker image: \(error.localizedDescription)")
                }
            }
        } else {
            let markerImage = generateFriendMarkerImage(
                size: size,
                name: name,
                isOnline: isOnline,
                avatarImage: nil,
                isExpanded: isExpanded
            )
            
            let markerId = friendId != nil ? "friend-marker-\(friendId!)\(isExpanded ? "-expanded" : "")" : "friend-marker-default"
            
            do {
                try mapView.mapboxMap.addImage(markerImage, id: markerId)
                print("DEBUG: Successfully added friend marker for \(name ?? "Unknown") without avatar")
            } catch {
                print("DEBUG: Error adding friend marker image: \(error.localizedDescription)")
            }
        }
    }
    
    func createSameLocationMarkerImage(groupId: String, representativeUser: User, totalCount: Int, hasOnlineUsers: Bool) {
        let size: CGFloat = 60
        
        if let avatarUrlString = representativeUser.currentAvatarUrl {
            loadImageAsync(from: avatarUrlString) { [weak self] avatarImage in
                let markerImage = self?.generateSameLocationMarkerImage(
                    size: size,
                    representativeUser: representativeUser,
                    avatarImage: avatarImage,
                    totalCount: totalCount,
                    hasOnlineUsers: hasOnlineUsers
                )
                
                guard let image = markerImage else { return }
                
                do {
                    try self?.mapView.mapboxMap.addImage(image, id: "same-location-\(groupId)")
                    print("DEBUG: Successfully added same-location marker for group \(groupId)")
                } catch {
                    print("DEBUG: Error adding same-location marker image: \(error.localizedDescription)")
                }
            }
        } else {
            let markerImage = generateSameLocationMarkerImage(
                size: size,
                representativeUser: representativeUser,
                avatarImage: nil,
                totalCount: totalCount,
                hasOnlineUsers: hasOnlineUsers
            )
            
            do {
                try mapView.mapboxMap.addImage(markerImage, id: "same-location-\(groupId)")
                print("DEBUG: Successfully added same-location marker for group \(groupId) without avatar")
            } catch {
                print("DEBUG: Error adding same-location marker image: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Annotation Creation Methods
    
    private func createFriendAnnotation(for friend: User, at coordinate: CLLocationCoordinate2D, isExpanded: Bool) -> PointAnnotation {
        let isOnline = friend.isOnline
        
        createFriendMarkerImage(
            friendId: friend.id,
            name: friend.fullName,
            isOnline: isOnline,
            profileImageUrl: friend.currentAvatarUrl,
            isExpanded: isExpanded
        )
        
        var annotation = PointAnnotation(coordinate: coordinate)
        annotation.iconAnchor = .center
        
        let markerIconId = "friend-marker-\(friend.id)\(isExpanded ? "-expanded" : "")"
        annotation.iconImage = markerIconId
        annotation.iconSize = isExpanded ? 0.8 : 1.0
        
        friendIdByAnnotationId[annotation.id] = friend.id
        
        return annotation
    }
    
    private func createClusterAnnotation(for group: LocationGroup, friends: [User]) -> PointAnnotation {
        let anyOnline = friends.contains { $0.isOnline }
        let clusterId = group.friendIds.sorted().joined(separator: "_")
        let friendInitials = friends.prefix(3).map { $0.initials }
        
        let clusterImage = ClusterMarkerGenerator.generateClusterMarker(
            count: group.friendIds.count,
            friendInitials: friendInitials,
            isOnline: anyOnline
        )
        
        do {
            try mapView.mapboxMap.addImage(clusterImage, id: clusterId)
        } catch {
            print("DEBUG: Error adding cluster marker image: \(error.localizedDescription)")
        }
        
        var annotation = PointAnnotation(coordinate: group.centerCoordinate)
        annotation.iconAnchor = .center
        annotation.iconImage = clusterId
        annotation.iconSize = 1.0
        
        return annotation
    }
    
    private func createSameLocationAnnotation(for group: LocationGroup, friends: [User]) -> PointAnnotation {
        let representativeUser: User
        
        if let repUserId = group.representativeUserId,
           let repUser = friends.first(where: { $0.id == repUserId }) {
            representativeUser = repUser
        } else if let onlineUser = friends.first(where: { $0.isOnline }) {
            representativeUser = onlineUser
        } else {
            representativeUser = friends.first ?? User.MOCK_USER
        }
        
        let groupId = group.friendIds.sorted().joined(separator: "_")
        
        createSameLocationMarkerImage(
            groupId: groupId,
            representativeUser: representativeUser,
            totalCount: group.friendIds.count,
            hasOnlineUsers: friends.contains { $0.isOnline }
        )
        
        var annotation = PointAnnotation(coordinate: group.centerCoordinate)
        annotation.iconAnchor = .center
        annotation.iconImage = "same-location-\(groupId)"
        annotation.iconSize = 1.0
        
        return annotation
    }
    
    // MARK: - Cluster Animation Methods
    
    private func handleExpandedCluster(group: LocationGroup, groupId: String, expandedAnnotationManager: PointAnnotationManager) {
        if expandedClusterAnnotations[groupId] == nil {
            startClusterExpansionAnimation(
                clusterId: groupId,
                group: group,
                expandedAnnotationManager: expandedAnnotationManager
            )
        } else {
            // Already expanded, just update positions
            let clusterFriends = viewModel.friends.filter { group.friendIds.contains($0.id) }
            var expandedAnnotations: [PointAnnotation] = []
            
            for friend in clusterFriends {
                if let position = group.relativePositions[friend.id] {
                    let annotation = createFriendAnnotation(
                        for: friend,
                        at: position,
                        isExpanded: true
                    )
                    expandedAnnotations.append(annotation)
                    friendIdByAnnotationId[annotation.id] = friend.id
                }
            }
            expandedClusterAnnotations[groupId] = expandedAnnotations
        }
    }
    
    private func startClusterExpansionAnimation(clusterId: String, group: LocationGroup, expandedAnnotationManager: PointAnnotationManager) {
        print("DEBUG: Starting expansion animation for cluster \(clusterId)")
        
        expansionTimers[clusterId]?.invalidate()
        
        let friends = viewModel.friends.filter { group.friendIds.contains($0.id) }
        let animationDuration: TimeInterval = 0.4
        let frameInterval: TimeInterval = 0.016
        
        var animatingAnnotations: [PointAnnotation] = []
        
        for friend in friends {
            let annotation = createFriendAnnotation(
                for: friend,
                at: group.centerCoordinate,
                isExpanded: true
            )
            animatingAnnotations.append(annotation)
            friendIdByAnnotationId[annotation.id] = friend.id
        }
        
        expandedClusterAnnotations[clusterId] = animatingAnnotations
        expandedAnnotationManager.annotations = Array(expandedClusterAnnotations.values.flatMap { $0 })
        
        animationProgress[clusterId] = 0.0
        
        let timer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                let currentProgress = self.animationProgress[clusterId] ?? 0.0
                let newProgress = min(1.0, currentProgress + frameInterval / animationDuration)
                
                let keyframes = group.getExpansionKeyframes(progress: newProgress)
                self.updateExpandedAnnotationPositions(
                    clusterId: clusterId,
                    keyframes: keyframes,
                    expandedAnnotationManager: expandedAnnotationManager
                )
                
                self.animationProgress[clusterId] = newProgress
                
                if newProgress >= 1.0 {
                    timer.invalidate()
                    self.expansionTimers.removeValue(forKey: clusterId)
                    self.animationProgress.removeValue(forKey: clusterId)
                    print("DEBUG: Completed expansion animation for cluster \(clusterId)")
                }
            }
        }
        
        expansionTimers[clusterId] = timer
    }
    
    private func startClusterContractionAnimation(clusterId: String, targetCenter: CLLocationCoordinate2D, expandedAnnotationManager: PointAnnotationManager) {
        print("DEBUG: Starting contraction animation for cluster \(clusterId)")
        
        expansionTimers[clusterId]?.invalidate()
        
        guard let group = lastLocationGroups.first(where: {
            $0.type == .cluster &&
            $0.friendIds.sorted().joined(separator: "_") == clusterId
        }) else {
            expandedClusterAnnotations.removeValue(forKey: clusterId)
            expandedAnnotationManager.annotations = Array(expandedClusterAnnotations.values.flatMap { $0 })
            return
        }
        
        let animationDuration: TimeInterval = 0.3
        let frameInterval: TimeInterval = 0.016
        
        animationProgress[clusterId] = 0.0
        
        let timer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                let currentProgress = self.animationProgress[clusterId] ?? 0.0
                let newProgress = min(1.0, currentProgress + frameInterval / animationDuration)
                
                let keyframes = group.getContractionKeyframes(progress: newProgress)
                self.updateExpandedAnnotationPositions(
                    clusterId: clusterId,
                    keyframes: keyframes,
                    expandedAnnotationManager: expandedAnnotationManager
                )
                
                self.animationProgress[clusterId] = newProgress
                
                if newProgress >= 1.0 {
                    timer.invalidate()
                    self.expansionTimers.removeValue(forKey: clusterId)
                    self.animationProgress.removeValue(forKey: clusterId)
                    
                    self.expandedClusterAnnotations.removeValue(forKey: clusterId)
                    expandedAnnotationManager.annotations = Array(self.expandedClusterAnnotations.values.flatMap { $0 })
                    
                    print("DEBUG: Completed contraction animation for cluster \(clusterId)")
                }
            }
        }
        
        expansionTimers[clusterId] = timer
    }
    
    private func updateExpandedAnnotationPositions(clusterId: String, keyframes: [String: CLLocationCoordinate2D], expandedAnnotationManager: PointAnnotationManager) {
        guard var annotations = expandedClusterAnnotations[clusterId] else { return }
        
        for i in 0..<annotations.count {
            let friendId = friendIdByAnnotationId[annotations[i].id]
            if let friendId = friendId, let newPosition = keyframes[friendId] {
                annotations[i].point = Point(newPosition)
            }
        }
        
        expandedClusterAnnotations[clusterId] = annotations
        expandedAnnotationManager.annotations = Array(expandedClusterAnnotations.values.flatMap { $0 })
    }
    
    // MARK: - Image Generation Methods
    
    private func generateUserMarkerImage(size: CGFloat, avatarImage: UIImage?) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        
        return renderer.image { ctx in
            let rectangle = CGRect(x: 0, y: 0, width: size, height: size)
            let cornerRadius: CGFloat = size/2
            
            let bezierPath = UIBezierPath(
                roundedRect: rectangle,
                cornerRadius: cornerRadius
            )
            ctx.cgContext.addPath(bezierPath.cgPath)
            ctx.cgContext.clip()
            
            if let image = avatarImage {
                image.draw(in: rectangle)
            } else {
                let colors = [
                    UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 0.9).cgColor,
                    UIColor(red: 0.0, green: 0.4, blue: 0.9, alpha: 0.9).cgColor
                ]
                let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: colors as CFArray,
                    locations: [0.0, 1.0]
                )!
                
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size, y: size),
                    options: []
                )
                
                let initials = viewModel.currentUser.initials
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: size * 0.3, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraphStyle
                ]
                
                let attributedString = NSAttributedString(string: initials, attributes: attributes)
                let textRect = CGRect(x: 0, y: (size - size * 0.4) / 2, width: size, height: size * 0.4)
                attributedString.draw(in: textRect)
            }
            
            ctx.cgContext.resetClip()
            
            let borderPath = UIBezierPath(
                roundedRect: rectangle.insetBy(dx: 2, dy: 2),
                cornerRadius: cornerRadius - 2
            )
            ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
            ctx.cgContext.setLineWidth(4.0)
            ctx.cgContext.addPath(borderPath.cgPath)
            ctx.cgContext.strokePath()
            
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
    
    private func generateFriendMarkerImage(size: CGFloat, name: String?, isOnline: Bool, avatarImage: UIImage?, isExpanded: Bool = false) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        
        return renderer.image { ctx in
            let rectangle = CGRect(x: 0, y: 0, width: size, height: size)
            let cornerRadius: CGFloat = size/2
            
            let bezierPath = UIBezierPath(
                roundedRect: rectangle,
                cornerRadius: cornerRadius
            )
            ctx.cgContext.addPath(bezierPath.cgPath)
            ctx.cgContext.clip()
            
            if let image = avatarImage {
                image.draw(in: rectangle)
            } else {
                let colors: [CGColor]
                if isOnline {
                    colors = [
                        UIColor(red: 0.0, green: 0.8, blue: 0.4, alpha: 0.9).cgColor,
                        UIColor(red: 0.0, green: 0.6, blue: 0.3, alpha: 0.9).cgColor
                    ]
                } else {
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
                
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size, y: size),
                    options: []
                )
                
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
                
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: size * 0.3, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraphStyle
                ]
                
                let attributedString = NSAttributedString(string: initials, attributes: attributes)
                let textRect = CGRect(x: 0, y: (size - size * 0.4) / 2, width: size, height: size * 0.4)
                attributedString.draw(in: textRect)
            }
            
            ctx.cgContext.resetClip()
            
            let borderPath = UIBezierPath(
                roundedRect: rectangle.insetBy(dx: 2, dy: 2),
                cornerRadius: cornerRadius - 2
            )
            ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
            ctx.cgContext.setLineWidth(isExpanded ? 2.0 : 3.0)
            ctx.cgContext.addPath(borderPath.cgPath)
            ctx.cgContext.strokePath()
            
            let statusPath = UIBezierPath(
                roundedRect: rectangle.insetBy(dx: 0.5, dy: 0.5),
                cornerRadius: cornerRadius - 0.5
            )
            let statusColor = isOnline ? UIColor.systemGreen : UIColor.systemGray
            ctx.cgContext.setStrokeColor(statusColor.cgColor)
            ctx.cgContext.setLineWidth(isExpanded ? 1.5 : 2.0)
            ctx.cgContext.addPath(statusPath.cgPath)
            ctx.cgContext.strokePath()
            
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
    
    private func generateSameLocationMarkerImage(size: CGFloat, representativeUser: User, avatarImage: UIImage?, totalCount: Int, hasOnlineUsers: Bool) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        
        return renderer.image { ctx in
            let rectangle = CGRect(x: 0, y: 0, width: size, height: size)
            let cornerRadius: CGFloat = size/2
            
            // Draw main avatar circle
            let bezierPath = UIBezierPath(
                roundedRect: rectangle,
                cornerRadius: cornerRadius
            )
            ctx.cgContext.addPath(bezierPath.cgPath)
            ctx.cgContext.clip()
            
            if let image = avatarImage {
                image.draw(in: rectangle)
            } else {
                // Draw gradient background based on online status
                let colors: [CGColor]
                if hasOnlineUsers {
                    colors = [
                        UIColor(red: 0.0, green: 0.8, blue: 0.4, alpha: 0.9).cgColor,
                        UIColor(red: 0.0, green: 0.6, blue: 0.3, alpha: 0.9).cgColor
                    ]
                } else {
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
                
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size, y: size),
                    options: []
                )
                
                // Draw initials
                let initials = representativeUser.initials
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: size * 0.3, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraphStyle
                ]
                
                let attributedString = NSAttributedString(string: initials, attributes: attributes)
                let textRect = CGRect(x: 0, y: (size - size * 0.4) / 2, width: size, height: size * 0.4)
                attributedString.draw(in: textRect)
            }
            
            ctx.cgContext.resetClip()
            
            // Draw border
            let borderPath = UIBezierPath(
                roundedRect: rectangle.insetBy(dx: 2, dy: 2),
                cornerRadius: cornerRadius - 2
            )
            ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
            ctx.cgContext.setLineWidth(3.0)
            ctx.cgContext.addPath(borderPath.cgPath)
            ctx.cgContext.strokePath()
            
            // Draw status border
            let statusColor = hasOnlineUsers ? UIColor.systemGreen : UIColor.systemGray
            ctx.cgContext.setStrokeColor(statusColor.cgColor)
            ctx.cgContext.setLineWidth(2.0)
            ctx.cgContext.strokeEllipse(in: rectangle.insetBy(dx: 0.5, dy: 0.5))
            
            // Draw count badge if more than 1 user
            if totalCount > 1 {
                let badgeSize: CGFloat = size * 0.35
                let badgeRect = CGRect(
                    x: size - badgeSize - 3,
                    y: 3,
                    width: badgeSize,
                    height: badgeSize
                )
                
                // Badge background
                ctx.cgContext.setFillColor(UIColor.red.cgColor)
                ctx.cgContext.fillEllipse(in: badgeRect)
                
                // Badge border
                ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
                ctx.cgContext.setLineWidth(2.0)
                ctx.cgContext.strokeEllipse(in: badgeRect.insetBy(dx: 1, dy: 1))
                
                // Count text
                let countText = totalCount > 99 ? "99+" : "\(totalCount)"
                let fontSize = badgeSize * 0.5
                
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraphStyle
                ]
                
                let attributedString = NSAttributedString(string: countText, attributes: attributes)
                let textRect = CGRect(
                    x: badgeRect.minX,
                    y: badgeRect.midY - fontSize/2,
                    width: badgeRect.width,
                    height: fontSize
                )
                
                attributedString.draw(in: textRect)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func areFriendLocationsSame(_ locations1: [String: UserLocation], _ locations2: [String: UserLocation]) -> Bool {
        guard locations1.count == locations2.count else { return false }
        
        for (friendId, location1) in locations1 {
            guard let location2 = locations2[friendId] else { return false }
            
            let threshold: Double = 0.0001
            if abs(location1.latitude - location2.latitude) > threshold ||
               abs(location1.longitude - location2.longitude) > threshold ||
               abs(location1.timestamp - location2.timestamp) > 30 {
                return false
            }
        }
        
        return true
    }
    
    private func areLocationGroupsSame(_ groups1: [LocationGroup], _ groups2: [LocationGroup]) -> Bool {
        guard groups1.count == groups2.count else { return false }
        
        for (index, group1) in groups1.enumerated() {
            guard index < groups2.count else { return false }
            let group2 = groups2[index]
            
            if group1.type != group2.type ||
               group1.friendIds.sorted() != group2.friendIds.sorted() ||
               abs(group1.centerCoordinate.latitude - group2.centerCoordinate.latitude) > 0.0001 ||
               abs(group1.centerCoordinate.longitude - group2.centerCoordinate.longitude) > 0.0001 {
                return false
            }
        }
        
        return true
    }
    
    private func loadImageAsync(from urlString: String, completion: @escaping (UIImage?) -> Void) {
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
            
            Task { @MainActor in
                self?.imageCache[urlString] = image
                completion(image)
            }
        }.resume()
    }
    
    private func refreshUserMarkerWithNewAvatar() {
        if let avatarUrl = viewModel.currentUser.currentAvatarUrl {
            imageCache.removeValue(forKey: avatarUrl)
        }
        
        createUserMarkerImage()
        
        if let userLocation = viewModel.userLocation {
            updateUserAnnotation(at: userLocation, userName: viewModel.currentUser.fullName)
        }
    }
    
    // MARK: - Tap Detection Methods
    
    private func isAnnotationTappedAt(annotation: Annotation, point: CGPoint) -> Bool {
        guard let pointAnnotation = annotation as? PointAnnotation else { return false }
        
        // Convert annotation coordinate to screen point
        let annotationScreenPoint = mapView.mapboxMap.point(for: pointAnnotation.point.coordinates)
        
        // Calculate distance between tap point and annotation point
        let distance = sqrt(
            pow(point.x - annotationScreenPoint.x, 2) +
            pow(point.y - annotationScreenPoint.y, 2)
        )
        
        // Return true if within tap tolerance
        let tapTolerance: CGFloat = 35
        return distance <= tapTolerance
    }
    
    // MARK: - Event Handlers
    
    @objc private func handleMapTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: mapView)
        
        Task { @MainActor in
            // Check if any annotation was tapped
            var annotationTapped = false
            
            // Check friend annotations
            if let friendManager = friendAnnotationManager {
                for annotation in friendManager.annotations {
                    if isAnnotationTappedAt(annotation: annotation, point: point) {
                        handleStandardAnnotationTap(annotation)
                        annotationTapped = true
                        break
                    }
                }
            }
            
            // Check expanded cluster annotations if no friend annotation was tapped
            if !annotationTapped, let expandedManager = expandedClusterAnnotationManager {
                for annotation in expandedManager.annotations {
                    if isAnnotationTappedAt(annotation: annotation, point: point) {
                        handleExpandedAnnotationTap(annotation)
                        annotationTapped = true
                        break
                    }
                }
            }
            
            // If no annotation was tapped, handle as general map tap
            if !annotationTapped {
                NotificationCenter.default.post(name: NSNotification.Name("MapTapped"), object: nil)
                collapseAllClusters()
            }
        }
    }
    
    private func collapseAllClusters() {
        for timer in expansionTimers.values {
            timer.invalidate()
        }
        expansionTimers.removeAll()
        animationProgress.removeAll()
        
        expandedClusterAnnotationManager?.annotations = []
        expandedClusterAnnotations.removeAll()
        
        viewModel.friendLocationGrouper.collapseAllClusters()
        
        print("DEBUG: Collapsed all clusters")
    }
    
    // MARK: - Tap Handling Methods
    
    private func handleStandardAnnotationTap(_ annotation: Annotation) {
        if let friendId = friendIdByAnnotationId[annotation.id] {
            // Single friend annotation
            print("DEBUG: Single friend tapped: \(friendId)")
            NotificationCenter.default.post(
                name: NSNotification.Name("FriendSelected"),
                object: nil,
                userInfo: ["friendId": friendId]
            )
        } else if let clusterFriendIds = clusterIdByAnnotationId[annotation.id] {
            // Cluster annotation
            handleClusterTap(annotation, friendIds: clusterFriendIds)
        } else if let sameLocationFriendIds = sameLocationGroupIdByAnnotationId[annotation.id] {
            // Same-location group annotation
            handleSameLocationTap(annotation, friendIds: sameLocationFriendIds)
        }
    }
    
    private func handleExpandedAnnotationTap(_ annotation: Annotation) {
        if let friendId = friendIdByAnnotationId[annotation.id] {
            print("DEBUG: Expanded cluster friend tapped: \(friendId)")
            NotificationCenter.default.post(
                name: NSNotification.Name("FriendSelected"),
                object: nil,
                userInfo: ["friendId": friendId]
            )
        }
    }
    
    private func handleClusterTap(_ annotation: Annotation, friendIds: [String]) {
        let clusterId = friendIds.sorted().joined(separator: "_")
        print("DEBUG: Cluster tapped with \(friendIds.count) friends")
        
        let isExpanded = viewModel.toggleClusterExpansion(clusterId: clusterId)
        
        if let pointAnnotation = annotation as? PointAnnotation {
            let clusterCenter = pointAnnotation.point.coordinates
            
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
    
    private func handleSameLocationTap(_ annotation: Annotation, friendIds: [String]) {
        print("DEBUG: Same-location group tapped with \(friendIds.count) friends")
        
        if let pointAnnotation = annotation as? PointAnnotation {
            let location = pointAnnotation.point.coordinates
            
            NotificationCenter.default.post(
                name: NSNotification.Name("SameLocationGroupSelected"),
                object: nil,
                userInfo: [
                    "friendIds": friendIds,
                    "latitude": location.latitude,
                    "longitude": location.longitude
                ]
            )
        }
    }
    
    // MARK: - Memory Management
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        imageCache.removeAll()
        
        for timer in expansionTimers.values {
            timer.invalidate()
        }
        expansionTimers.removeAll()
        animationProgress.removeAll()
    }
}
