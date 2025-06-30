//
//  MapViewRepresentable.swift
//  Zenlyne
//
//  Created by admin on 30/6/25.
//

import SwiftUI
@preconcurrency import MapboxMaps
import CoreLocation
import Combine

struct MapViewRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: LocationViewModel
    
    // User interaction tracking
    @State private var isUserInteracting: Bool = false
    @State private var lastUserInteraction: Date = Date()
    
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
        
        // Initial setup 
        let mapLoadedToken = mapView.mapboxMap.onMapLoaded.observeNext { _ in
            mapView.camera.fly(to: viewModel.cameraOptions, duration: 0.25)
            context.coordinator.setupMap(mapView)
        }
        
        // Setup camera change listener - Store cancellation token
        let cameraChangedToken = mapView.mapboxMap.onCameraChanged.observe { event in
            let newZoom = mapView.mapboxMap.cameraState.zoom
            let newCenter = mapView.mapboxMap.cameraState.center
            let isUserInitiated = context.coordinator.isUserInitiatedCameraChange()
            
            Task { @MainActor in
                context.coordinator.handleCameraChanged(
                    newZoomLevel: newZoom,
                    newCenter: newCenter,
                    userInitiated: isUserInitiated
                )
            }
        }
        
        // Store tokens in coordinator
        context.coordinator.storeCancellationTokens([mapLoadedToken, cameraChangedToken])
        
        // Add mapView to container
        containerView.addSubview(mapView)
        mapView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mapView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            mapView.topAnchor.constraint(equalTo: containerView.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        context.coordinator.setMapView(mapView)
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.updateMapView(with: viewModel)
    }

    func makeCoordinator() -> MapCoordinator {
        MapCoordinator(viewModel: viewModel)
    }
    
    // Cleanup when view is deallocated
    static func dismantleUIView(_ uiView: UIView, coordinator: MapCoordinator) {
        coordinator.cleanup()
    }
}
