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
    private var pointAnnotationManager: PointAnnotationManager?
    
    // Add public initializer
    public init(viewModel: LocationViewModel) {
        self.viewModel = viewModel
    }
    
    public func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero)
        
        // Configure the map style
        mapView.mapboxMap.loadStyle(.streets)
        
        // Configure map with initial options
        mapView.mapboxMap.onNext(event: .mapLoaded) { _ in
            // Set camera to initial position
            mapView.camera.fly(to: viewModel.cameraOptions, duration: 0.25)
            
            // Setup point annotation manager for custom user marker
            context.coordinator.setupUserAnnotation(for: mapView)
        }
        
        return mapView
    }
    
    public func updateUIView(_ mapView: MapView, context: Context) {
        // Update camera position when viewModel changes
        mapView.camera.fly(to: viewModel.cameraOptions, duration: 0.25)
        
        // Update user annotation when location changes
        if let location = viewModel.userLocation {
            context.coordinator.updateUserAnnotation(for: mapView, at: location, userName: viewModel.currentUser.fullName)
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    public class Coordinator: NSObject {
        private var viewModel: LocationViewModel
        private var pointAnnotationManager: PointAnnotationManager?
        
        public init(viewModel: LocationViewModel) {
            self.viewModel = viewModel
        }
        
        func setupUserAnnotation(for mapView: MapView) {
            // Create the annotation manager
            pointAnnotationManager = mapView.annotations.makePointAnnotationManager()
            
            // Create the custom image for user location - now as a square
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
            guard let annotationManager = pointAnnotationManager else { return }
            
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
    }
}
