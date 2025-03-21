//
//  MapViewRepresentable.swift
//  Zenlyne
//
//  Created by admin on 21/3/25.
//

import SwiftUI
import MapboxMaps
import CoreLocation

struct MapViewRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: LocationViewModel
    
    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero)
        
        // Configure the map style
        mapView.mapboxMap.loadStyleURI(.streets)
        
        // Configure map with initial options
        mapView.mapboxMap.onNext(event: .mapLoaded) { _ in
            // Set camera to initial position
            mapView.camera.fly(to: viewModel.cameraOptions, duration: 0.25)
            
            // Setup location tracking
            setupLocationPuck(for: mapView)
        }
        
        return mapView
    }
    
    func updateUIView(_ mapView: MapView, context: Context) {
        // Update camera position when viewModel changes
        mapView.camera.fly(to: viewModel.cameraOptions, duration: 0.25)
    }
    
    private func setupLocationPuck(for mapView: MapView) {
        // Configure the puck style
        var puckConfig = Puck2DConfiguration()
        puckConfig.showsAccuracyRing = true
        puckConfig.accuracyRingColor = UIColor.blue.withAlphaComponent(0.1)
        
        // Note: Newer versions of MapboxMaps may not have PuckPulsing
        // If your MapboxMaps version doesn't support pulsing, use this configuration instead
        
        mapView.location.options = LocationOptions(
            puckType: .puck2D(puckConfig)
        )
    }
}
