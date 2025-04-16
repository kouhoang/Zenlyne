//
//  MapViewRepresentable.swift
//  Zenlyne
//
//  Created by admin on 21/3/25.
//

import SwiftUI
import MapboxMaps
import CoreLocation

public struct MapViewRepresentable: UIViewRepresentable {
    @ObservedObject public var viewModel: LocationViewModel
        
    public init(viewModel: LocationViewModel) {
        self.viewModel = viewModel
    }
        
    public func makeUIView(context: Context) -> MapView {
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
        
    public func updateUIView(_ mapView: MapView, context: Context) {
        // Update camera position when viewModel changes
        mapView.camera.fly(to: viewModel.cameraOptions, duration: 0.25)
        
        // Update user annotation when location changes
        if let location = viewModel.userLocation {
            context.coordinator.updateUserAnnotation(
                for: mapView,
                at: location,
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
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    public class Coordinator: NSObject {
        private var viewModel: LocationViewModel
        private var userAnnotationManager: PointAnnotationManager?
        private var friendAnnotationManager: PointAnnotationManager?
        private var friendIdByAnnotationId: [String: String] = [:]
        
        public init(viewModel: LocationViewModel) {
            self.viewModel = viewModel
            super.init()
        }
        
        func setupAnnotations(for mapView: MapView) {
            // Create the annotation managers
            userAnnotationManager = mapView.annotations.makePointAnnotationManager()
            friendAnnotationManager = mapView.annotations.makePointAnnotationManager()
            
            // Create the custom image for user location
            createUserMarkerImage(for: mapView)
            
            // Create the custom image for friend locations
            createFriendMarkerImage(for: mapView)
            
            // Thiết lập annotation tap handling qua annotationInteractionDelegate
            if let friendManager = friendAnnotationManager {
                friendManager.delegate = self
            }
            
            // Thêm tap gesture recognizer để xử lý sự kiện tap trên bản đồ
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(_:)))
            mapView.addGestureRecognizer(tapGesture)
        }
        
        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            // Khi người dùng nhấn vào bản đồ (không phải vào marker),
            // gửi thông báo để đóng panel thông tin bạn bè nếu nó đang hiển thị
            NotificationCenter.default.post(name: NSNotification.Name("MapTapped"), object: nil)
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
                
                // Add subtle inner shadow
                ctx.cgContext.setShadow(
                    offset: CGSize(width: 0, height: 1),
                    blur: 3,
                    color: UIColor.black.withAlphaComponent(0.2).cgColor
                )
                
                // Draw text with improved styling
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                
                let fullName = viewModel.currentUser.fullName
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont(name: "Avenir-Medium", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .medium),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraphStyle,
                    .shadow: NSShadow() // Add text shadow
                ]
                
                let attributedString = NSAttributedString(string: fullName, attributes: attributes)
                let textRect = CGRect(x: 5, y: (size - 20) / 2, width: size - 10, height: 20)
                
                // Clear shadow for text drawing
                ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
                attributedString.draw(in: textRect)
            }
            
            // Add the image to the style
            try? mapView.mapboxMap.style.addImage(annotationImage, id: "user-marker-id")
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
        }
        
        func updateFriendAnnotations(for mapView: MapView, friendLocations: [String: UserLocation], friends: [User]) {
            guard let annotationManager = friendAnnotationManager else { return }
            
            // Remove existing annotations
            annotationManager.annotations = []
            friendIdByAnnotationId.removeAll()
            
            // Create a new annotation for each friend
            var annotations: [PointAnnotation] = []
            
            for (friendId, location) in friendLocations {
                // Get friend info
                guard let friend = friends.first(where: { $0.id == friendId }) else { continue }
                
                // Check if friend is online - create different marker based on status
                let isOnline = friend.isOnline
                
                // Create unique marker image for this friend if it doesn't exist
                createFriendMarkerImage(for: mapView, friendId: friendId, name: friend.fullName, isOnline: isOnline)
                
                // Create annotation
                var annotation = PointAnnotation(coordinate: location.toCoordinate())
                annotation.iconAnchor = .bottom
                
                let statusText = isOnline ? "online" : "offline"
                let markerIconId = "friend-marker-\(friendId)-\(statusText)"
                annotation.iconImage = markerIconId
                annotation.iconSize = 1.0
                
                // Lưu mapping giữa annotation ID và friend ID để xử lý tap
                friendIdByAnnotationId[annotation.id] = friendId
                
                annotations.append(annotation)
            }
            
            // Thêm tất cả các annotation vào manager
            annotationManager.annotations = annotations
        }

        // Cập nhật method tạo hình ảnh cho friend marker với trạng thái online/offline
        func createFriendMarkerImage(for mapView: MapView, friendId: String? = nil, name: String? = nil, isOnline: Bool = false) {
            let size: CGFloat = 50 // Square dimensions
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            
            let annotationImage = renderer.image { ctx in
                let rectangle = CGRect(x: 0, y: 0, width: size, height: size)
                
                // Định nghĩa bo góc
                let cornerRadius: CGFloat = 12
                
                // Create gradient background - sử dụng màu khác nhau cho online/offline
                let colors: [CGColor]
                if isOnline {
                    // Màu cam cho bạn bè online
                    colors = [
                        UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 0.9).cgColor,
                        UIColor(red: 0.8, green: 0.3, blue: 0.0, alpha: 0.9).cgColor
                    ]
                } else {
                    // Màu xám cho bạn bè offline
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
                
                // Get initials from name
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
                
                // Draw text with improved styling
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraphStyle
                ]
                
                let attributedString = NSAttributedString(string: initials, attributes: attributes)
                
                // Tính toán vị trí để đặt text ở giữa
                let textRect = CGRect(x: 5, y: (size - 20) / 2, width: size - 10, height: 20)
                
                // Clear shadow for text drawing
                ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
                attributedString.draw(in: textRect)
                
                // Vẽ chấm trạng thái online/offline
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
                
                // Thêm viền trắng cho chấm status
                ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
                ctx.cgContext.setLineWidth(1.0)
                ctx.cgContext.strokeEllipse(in: CGRect(
                    x: statusDotX - statusDotSize/2,
                    y: statusDotY - statusDotSize/2,
                    width: statusDotSize,
                    height: statusDotSize
                ))
            }
            
            // Tạo ID duy nhất cho marker dựa trên ID và trạng thái online
            let statusText = isOnline ? "online" : "offline"
            let markerId = friendId != nil ? "friend-marker-\(friendId!)-\(statusText)" : "friend-marker-default-\(statusText)"
            
            // Add the image to the style
            try? mapView.mapboxMap.style.addImage(annotationImage, id: markerId)
        }
    }
}

// MARK: - AnnotationInteractionDelegate
extension MapViewRepresentable.Coordinator: AnnotationInteractionDelegate {
    public func annotationManager(_ manager: AnnotationManager, didDetectTappedAnnotations annotations: [Annotation]) {
        guard let annotation = annotations.first,
              let friendId = friendIdByAnnotationId[annotation.id] else {
            return
        }
        
        // Gửi thông báo về việc chọn bạn bè để hiển thị thông tin
        NotificationCenter.default.post(
            name: NSNotification.Name("FriendSelected"),
            object: nil,
            userInfo: ["friendId": friendId]
        )
    }
}
