//
//  MapGestureHandler.swift
//  Zenlyne
//
//  Created by admin on 30/6/25.
//


import UIKit
import MapboxMaps

class MapGestureHandler: NSObject {
    private weak var coordinator: MapCoordinator?
    
    init(coordinator: MapCoordinator) {
        self.coordinator = coordinator
        super.init()
    }
    
    func setupGestureTracking(on mapView: MapboxMaps.MapView) {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.delegate = self
        mapView.addGestureRecognizer(panGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        pinchGesture.delegate = self
        mapView.addGestureRecognizer(pinchGesture)
        
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotationGesture(_:)))
        rotationGesture.delegate = self
        mapView.addGestureRecognizer(rotationGesture)
    }
    
    @MainActor @objc func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        handleGestureStateChange(gesture.state, gestureType: "panning")
    }
    
    @MainActor @objc func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
        handleGestureStateChange(gesture.state, gestureType: "pinching")
    }
    
    @MainActor @objc func handleRotationGesture(_ gesture: UIRotationGestureRecognizer) {
        handleGestureStateChange(gesture.state, gestureType: "rotating")
    }
    
    @MainActor private func handleGestureStateChange(_ state: UIGestureRecognizer.State, gestureType: String) {
        switch state {
        case .began:
            coordinator?.setUserInteracting(true)
            print("DEBUG: User started \(gestureType)")
        case .ended, .cancelled:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.coordinator?.setUserInteracting(false)
                print("DEBUG: User finished \(gestureType)")
            }
        default:
            break
        }
    }
}

// MARK: - UIGestureRecognizerDelegate
extension MapGestureHandler: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
