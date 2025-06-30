//
//  MapCameraManager.swift
//  Zenlyne
//
//  Created by admin on 30/6/25.
//

import Foundation
import MapboxMaps
import CoreLocation

@MainActor
class MapCameraManager {
    private let mapView: MapboxMaps.MapView
    private let viewModel: LocationViewModel
    
    // Camera tracking
    private var programmaticCameraChangeTime: Date = Date.distantPast
    private var cameraChangeDebounceTimer: Timer?
    private let cameraChangeDebounceInterval: TimeInterval = 0.3
    
    init(mapView: MapboxMaps.MapView, viewModel: LocationViewModel) {
        self.mapView = mapView
        self.viewModel = viewModel
    }
    
    func updateCamera(with cameraOptions: CameraOptions) {
        print("DEBUG: Updating camera position")
        mapView.camera.fly(to: cameraOptions, duration: 0.5)
        markProgrammaticCameraChange()
    }
    
    func markProgrammaticCameraChange() {
        programmaticCameraChangeTime = Date()
    }
    
    func isUserInitiatedCameraChange() -> Bool {
        let timeSinceProgrammatic = Date().timeIntervalSince(programmaticCameraChangeTime)
        return timeSinceProgrammatic > 1.0
    }
    
    func handleCameraChanged(newZoomLevel: Double, newCenter: CLLocationCoordinate2D, userInitiated: Bool, viewModel: LocationViewModel) {
        cameraChangeDebounceTimer?.invalidate()
        
        // Capture current values before entering Timer closure
        let currentZoom = viewModel.currentZoomLevel
        
        cameraChangeDebounceTimer = Timer.scheduledTimer(withTimeInterval: cameraChangeDebounceInterval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            // Use captured value instead of accessing property in closure
            if abs(newZoomLevel - currentZoom) > 0.5 {
                print("DEBUG: Zoom level changed from \(currentZoom) to \(newZoomLevel) (user initiated: \(userInitiated))")
                
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    
                    self.viewModel.updateZoomLevel(newZoomLevel)
                    
                    if userInitiated {
                        self.viewModel.updateLocationInfo(for: newCenter)
                    }
                    
                    if userInitiated && newZoomLevel < 12.0 {
                        self.collapseAllClusters()
                    }
                }
            }
        }
    }
    
    private func collapseAllClusters() {
        NotificationCenter.default.post(name: NSNotification.Name("CollapseAllClusters"), object: nil)
    }
    
    deinit {
        cameraChangeDebounceTimer?.invalidate()
    }
}
