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
        
    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero)
        
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
        
        return mapView
    }
        
    func updateUIView(_ mapView: MapView, context: Context) {
        print("DEBUG: Updating MapView with \(viewModel.friendLocations.count) friend locations")
        
        // Update camera position when viewModel changes
        mapView.camera.fly(to: viewModel.cameraOptions, duration: 0.25)
        
        // Update user annotation when location changes
        if let userLocation = viewModel.userLocation {
            context.coordinator.updateUserAnnotation(
                for: mapView,
                at: userLocation,
                userName: viewModel.currentUser.fullName
            )
        }
        
        // Update friend annotations when their locations change
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
        private var userAnnotationManager: PointAnnotationManager?
        private var friendAnnotationManager: PointAnnotationManager?
        private var pulseAnnotationManager: CircleAnnotationManager?
        private var friendIdByAnnotationId: [String: String] = [:]
        private var pulseTimers: [String: Timer] = [:]
        
        init(viewModel: LocationViewModel) {
            self.viewModel = viewModel
            super.init()
        }
        
        
        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            // When the user taps on the map (not on a marker),
            // send a notification to close the friend info panel if it's displayed
            NotificationCenter.default.post(name: NSNotification.Name("MapTapped"), object: nil)
        }
        
        // Simplified pulsing effect using regular annotations instead of layers
        private func addPulseEffectLayer(for mapView: MapView, at coordinate: CLLocationCoordinate2D, color: UIColor, isUser: Bool) {
            // Use the stored pulse annotation manager or create a new one
            let pulseAnnotationManager = self.pulseAnnotationManager ?? mapView.annotations.makeCircleAnnotationManager()
            self.pulseAnnotationManager = pulseAnnotationManager
            
            // Create a pulsing animation using scaling circle annotations
            let pulseLayerId = isUser ? "user-pulse" : "friend-pulse-\(UUID().uuidString)"
            
            // Create initial small circle
            var circle = CircleAnnotation(centerCoordinate: coordinate)
            circle.circleColor = StyleColor(color.withAlphaComponent(0.3))
            // Fix: Use the correct expression type for Mapbox
            circle.circleRadius = Double(20)
            circle.circleOpacity = Double(0.8)
            
            pulseAnnotationManager.annotations = [circle]
            
            // Create a timer to animate the pulsing effect
            let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let annotations = pulseAnnotationManager.annotations as? [CircleAnnotation],
                      var firstCircle = annotations.first else { return }
                
                // Extract current radius and opacity values
                let currentRadius = (firstCircle.circleRadius ?? 20) as Double
                let currentOpacity = (firstCircle.circleOpacity ?? 0.8) as Double
                
                // Calculate new values
                let newRadius: Double
                let newOpacity: Double
                
                if currentRadius < 50 {
                    newRadius = currentRadius + 0.5
                    newOpacity = max(0.1, currentOpacity - 0.01)
                } else {
                    newRadius = 20
                    newOpacity = 0.8
                }
                
                // Create a new circle with updated properties
                var updatedCircle = CircleAnnotation(centerCoordinate: firstCircle.point.coordinates)
                updatedCircle.circleColor = firstCircle.circleColor
                updatedCircle.circleRadius = newRadius
                updatedCircle.circleOpacity = newOpacity
                
                pulseAnnotationManager.annotations = [updatedCircle]
            }
            
            // Store the timer to prevent it from being deallocated
            pulseTimers[pulseLayerId] = timer
        }
        
        func createUserMarkerImage(for mapView: MapView) {
            let size: CGFloat = 50 // Square dimensions
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            
            let annotationImage = renderer.image { ctx in
                let rectangle = CGRect(x: 0, y: 0, width: size, height: size)
                
                // Create gradient background
                let colors = [
                    UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 0.9).cgColor,
                    UIColor(red: 0.0, green: 0.4, blue: 0.9, alpha: 0.9).cgColor
                ]
                let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: colors as CFArray,
                    locations: [0.0, 1.0]
                )!
                
                // Apply rounded corners
                let cornerRadius: CGFloat = 14
                let bezierPath = UIBezierPath(
                    roundedRect: rectangle,
                    cornerRadius: cornerRadius
                )
                ctx.cgContext.addPath(bezierPath.cgPath)
                ctx.cgContext.clip()
                
                // Draw gradient
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size, y: size),
                    options: []
                )
                
                // Draw glowing border
                let borderPath = UIBezierPath(
                    roundedRect: rectangle.insetBy(dx: 2, dy: 2),
                    cornerRadius: cornerRadius - 2
                )
                ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
                ctx.cgContext.setLineWidth(2.5)
                ctx.cgContext.addPath(borderPath.cgPath)
                ctx.cgContext.strokePath()
                
                // Create circle within marker for avatar/initials
                let avatarRect = CGRect(x: 8, y: 8, width: size - 16, height: size - 16)
                let avatarPath = UIBezierPath(ovalIn: avatarRect)
                
                // Draw blue background for avatar
                ctx.cgContext.setFillColor(UIColor(red: 0.0, green: 0.3, blue: 0.8, alpha: 0.5).cgColor)
                ctx.cgContext.addPath(avatarPath.cgPath)
                ctx.cgContext.fillPath()
                
                // Get initials for avatar fallback
                let fullName = viewModel.currentUser.fullName
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
                
                // Draw initials in center of avatar circle
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraphStyle
                ]
                
                let attributedString = NSAttributedString(string: initials, attributes: attributes)
                
                // Calculate position to place text in center of avatar
                let textRect = CGRect(x: 8, y: (size - 20) / 2, width: size - 16, height: 20)
                attributedString.draw(in: textRect)
            }
            
            // Add the image to the style
            do {
                try mapView.mapboxMap.style.addImage(annotationImage, id: "user-marker-id")
                print("DEBUG: Created user marker image")
            } catch {
                print("DEBUG: Error adding user marker image: \(error.localizedDescription)")
            }
        }
        
        func updateUserAnnotation(for mapView: MapView, at coordinate: CLLocationCoordinate2D, userName: String) {
            guard let annotationManager = userAnnotationManager else { return }
            
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
            
            // Update the pulsing effect layer position
            updatePulseEffect(for: mapView, at: coordinate, isUser: true)
        }
        
        // Helper function to update pulse effect position
        private func updatePulseEffect(for mapView: MapView, at coordinate: CLLocationCoordinate2D, isUser: Bool) {
            // Use the stored pulse annotation manager instead of searching for it
            if let pulseManager = self.pulseAnnotationManager {
                // Update the position of existing circle annotations
                if let circles = pulseManager.annotations as? [CircleAnnotation], !circles.isEmpty {
                    var updatedCircles: [CircleAnnotation] = []
                    
                    for circle in circles {
                        // Extract current radius and opacity values
                        let currentRadius = (circle.circleRadius ?? 20) as Double
                        let currentOpacity = (circle.circleOpacity ?? 0.8) as Double
                        
                        // Create a new circle with the updated coordinate but same properties
                        var updatedCircle = CircleAnnotation(centerCoordinate: coordinate)
                        updatedCircle.circleColor = circle.circleColor
                        updatedCircle.circleRadius = currentRadius
                        updatedCircle.circleOpacity = currentOpacity
                        
                        updatedCircles.append(updatedCircle)
                    }
                    
                    pulseManager.annotations = updatedCircles
                } else {
                    // Or create new pulse effect
                    addPulseEffectLayer(for: mapView, at: coordinate, color: isUser ? .blue : .orange, isUser: isUser)
                }
            } else {
                // Create new pulse effect if no manager exists
                addPulseEffectLayer(for: mapView, at: coordinate, color: isUser ? .blue : .orange, isUser: isUser)
            }
        }
        
        func setupAnnotations(for mapView: MapView) {
            print("DEBUG: Setting up annotations")
            
            // Create the annotation managers
            userAnnotationManager = mapView.annotations.makePointAnnotationManager()
            friendAnnotationManager = mapView.annotations.makePointAnnotationManager()
            pulseAnnotationManager = mapView.annotations.makeCircleAnnotationManager()
            
            // Create the custom image for user location
            createUserMarkerImage(for: mapView)
            
            // Create the custom image for friend locations
            createFriendMarkerImage(for: mapView)
            
            // Add pulsing effect to user location using circle layers
            if let userLocation = viewModel.userLocation {
                addPulseEffectLayer(for: mapView, at: userLocation, color: UIColor.blue, isUser: true)
            }
            
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
            
            // Add tap gesture recognizer to handle map taps
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(_:)))
            mapView.addGestureRecognizer(tapGesture)
            
            print("DEBUG: Annotations setup complete")
        }
        
        func updateFriendAnnotations(for mapView: MapView, friendLocations: [String: UserLocation], friends: [User]) {
            guard let annotationManager = friendAnnotationManager else { return }
            
            print("DEBUG: Updating friend annotations with \(friendLocations.count) locations and \(friends.count) friends")
            
            // Delete all current annotations
            annotationManager.annotations = []
            friendIdByAnnotationId.removeAll()
            
            // Create new annotation for each friend
            var annotations: [PointAnnotation] = []
            
            for (friendId, location) in friendLocations {
                // Get friend information
                guard let friend = friends.first(where: { $0.id == friendId }) else {
                    print("DEBUG: Friend not found for ID \(friendId)")
                    continue
                }
                
                print("DEBUG: Creating annotation for friend: \(friend.fullName) at \(location.latitude), \(location.longitude)")
                
                // Check online status
                let isOnline = friend.isOnline
                
                // Create marker image for this friend
                createFriendMarkerImage(for: mapView, friendId: friendId, name: friend.fullName, isOnline: isOnline, profileImageUrl: friend.profileImageUrl)
                
                // Create annotation
                var annotation = PointAnnotation(coordinate: location.toCoordinate())
                annotation.iconAnchor = .bottom
                
                let statusText = isOnline ? "online" : "offline"
                let markerIconId = "friend-marker-\(friendId)-\(statusText)"
                annotation.iconImage = markerIconId
                annotation.iconSize = 1.0
                
                // Save mapping between annotation ID and friend ID
                friendIdByAnnotationId[annotation.id] = friendId
                
                annotations.append(annotation)
                
                // Add pulse effect for online friends
                if isOnline {
                    updatePulseEffect(for: mapView, at: location.toCoordinate(), isUser: false)
                }
            }
            
            // Add all annotations to manager
            annotationManager.annotations = annotations
            print("DEBUG: Added \(annotations.count) friend annotations to map")
        }

        // Update method to create friend marker image with online/offline status
        func createFriendMarkerImage(for mapView: MapView, friendId: String? = nil, name: String? = nil, isOnline: Bool = false, profileImageUrl: String? = nil) {
            let size: CGFloat = 50 // Square dimensions
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            
            let annotationImage = renderer.image { ctx in
                let rectangle = CGRect(x: 0, y: 0, width: size, height: size)
                
                // Define corner radius
                let cornerRadius: CGFloat = 12
                
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
                
                // Apply rounded corners
                let bezierPath = UIBezierPath(
                    roundedRect: rectangle,
                    cornerRadius: cornerRadius
                )
                ctx.cgContext.addPath(bezierPath.cgPath)
                ctx.cgContext.clip()
                
                // Draw gradient
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size, y: size),
                    options: []
                )
                
                // Draw glowing border
                let borderPath = UIBezierPath(
                    roundedRect: rectangle.insetBy(dx: 2, dy: 2),
                    cornerRadius: cornerRadius - 2
                )
                ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
                ctx.cgContext.setLineWidth(2.5)
                ctx.cgContext.addPath(borderPath.cgPath)
                ctx.cgContext.strokePath()
                
                // Add subtle inner shadow
                ctx.cgContext.setShadow(
                    offset: CGSize(width: 0, height: 1),
                    blur: 3,
                    color: UIColor.black.withAlphaComponent(0.2).cgColor
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
                
                // Create circle within marker for avatar/initials
                let avatarRect = CGRect(x: 8, y: 8, width: size - 16, height: size - 16)
                let avatarPath = UIBezierPath(ovalIn: avatarRect)
                
                // Clear shadow for avatar
                ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
                
                // Draw blue background for avatar
                ctx.cgContext.setFillColor(UIColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 0.5).cgColor)
                ctx.cgContext.addPath(avatarPath.cgPath)
                ctx.cgContext.fillPath()
                
                // Draw initials in center of avatar circle
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraphStyle
                ]
                
                let attributedString = NSAttributedString(string: initials, attributes: attributes)
                
                // Calculate position to place text in center of avatar
                let textRect = CGRect(x: 8, y: (size - 20) / 2, width: size - 16, height: 20)
                attributedString.draw(in: textRect)
                
                // Draw online/offline status dot
                let statusDotSize: CGFloat = 10
                let statusDotX = size - statusDotSize - 5
                let statusDotY = 5 + statusDotSize/2
                
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
                ctx.cgContext.setLineWidth(1.0)
                ctx.cgContext.strokeEllipse(in: CGRect(
                    x: statusDotX - statusDotSize/2,
                    y: statusDotY - statusDotSize/2,
                    width: statusDotSize,
                    height: statusDotSize
                ))
            }
            
            // Create unique ID for marker based on ID and online status
            let statusText = isOnline ? "online" : "offline"
            let markerId = friendId != nil ? "friend-marker-\(friendId!)-\(statusText)" : "friend-marker-default-\(statusText)"
            
            // Add the image to the style
            do {
                try mapView.mapboxMap.style.addImage(annotationImage, id: markerId)
                print("DEBUG: Created marker image for friend \(friendId ?? "unknown") - \(statusText)")
            } catch {
                print("DEBUG: Error adding friend marker image: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - AnnotationInteractionDelegate
extension MapViewRepresentable.Coordinator: AnnotationInteractionDelegate {
    func annotationManager(_ manager: AnnotationManager, didDetectTappedAnnotations annotations: [Annotation]) {
        guard let annotation = annotations.first,
              let friendId = friendIdByAnnotationId[annotation.id] else {
            return
        }
        
        // Send notification about selecting a friend to display info
        NotificationCenter.default.post(
            name: NSNotification.Name("FriendSelected"),
            object: nil,
            userInfo: ["friendId": friendId]
        )
    }
}
