//
//  MapCoordinator.swift
//  Zenlyne
//
//  Created by admin on 30/6/25.
//

import SwiftUI
import MapboxMaps
import CoreLocation
import FirebaseAuth
import Combine

@MainActor
class MapCoordinator: NSObject {
    private var viewModel: LocationViewModel
    private var mapView: MapboxMaps.MapView?
    
    // Managers
    private var annotationManager: MapAnnotationManager?
    private var gestureHandler: MapGestureHandler?
    private var cameraManager: MapCameraManager?
    private var styleManager: MapStyleManager?
    
    // State tracking
    var isUserInteracting: Bool = false
    var currentMapStyle: MapStyle = .streets
    
    init(viewModel: LocationViewModel) {
        self.viewModel = viewModel
        super.init()
    }
    
    func setMapView(_ mapView: MapboxMaps.MapView) {
        self.mapView = mapView
        setupManagers()
    }
    
    private func setupManagers() {
        guard let mapView = mapView else { return }
        
        // Initialize managers
        annotationManager = MapAnnotationManager(mapView: mapView, viewModel: viewModel)
        gestureHandler = MapGestureHandler(coordinator: self)
        cameraManager = MapCameraManager(mapView: mapView, viewModel: viewModel)
        styleManager = MapStyleManager(mapView: mapView)
        
        // Setup gesture handling
        gestureHandler?.setupGestureTracking(on: mapView)
    }
    
    func setupMap(_ mapView: MapboxMaps.MapView) {
        annotationManager?.setupAnnotations()
    }
    
    func updateMapView(with viewModel: LocationViewModel) {
        print("DEBUG: Updating MapView - selective updates only")
        
        // Update map style if changed
        if currentMapStyle != viewModel.currentMapStyle {
            styleManager?.updateStyle(to: viewModel.currentMapStyle)
            currentMapStyle = viewModel.currentMapStyle
        }
        
        // Update camera if needed
        if viewModel.shouldUpdateCamera && !isUserInteracting {
            cameraManager?.updateCamera(with: viewModel.cameraOptions)
            
            DispatchQueue.main.async {
                viewModel.shouldUpdateCamera = false
            }
        } else if viewModel.shouldUpdateCamera {
            DispatchQueue.main.async {
                viewModel.shouldUpdateCamera = false
            }
        }
        
        // Update annotations
        annotationManager?.updateAnnotations(with: viewModel)
    }
    
    // MARK: - Camera Change Handling
    
    func handleCameraChanged(newZoomLevel: Double, newCenter: CLLocationCoordinate2D, userInitiated: Bool) {
        cameraManager?.handleCameraChanged(
            newZoomLevel: newZoomLevel,
            newCenter: newCenter,
            userInitiated: userInitiated,
            viewModel: viewModel
        )
    }
    
    func isUserInitiatedCameraChange() -> Bool {
        return cameraManager?.isUserInitiatedCameraChange() ?? false
    }
    
    func markProgrammaticCameraChange() {
        cameraManager?.markProgrammaticCameraChange()
    }
    
    // MARK: - User Interaction
    
    func setUserInteracting(_ interacting: Bool) {
        isUserInteracting = interacting
        if interacting {
            NotificationCenter.default.post(name: NSNotification.Name("UserMapInteractionStarted"), object: nil)
        } else {
            NotificationCenter.default.post(name: NSNotification.Name("UserMapInteractionEnded"), object: nil)
        }
    }
}

extension MapCoordinator {
    private static var cancellationTokensKey: UInt8 = 0
    
    private var cancellationTokens: [AnyCancelable] {
        get {
            return objc_getAssociatedObject(self, &Self.cancellationTokensKey) as? [AnyCancelable] ?? []
        }
        set {
            objc_setAssociatedObject(self, &Self.cancellationTokensKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    func storeCancellationTokens(_ tokens: [AnyCancelable]) {
        cancellationTokens.append(contentsOf: tokens)
    }
    
    func cleanup() {
        cancellationTokens.forEach { $0.cancel() }
        cancellationTokens.removeAll()
        print("DEBUG: MapCoordinator cleaned up \(cancellationTokens.count) tokens")
    }
}

