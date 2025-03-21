//
//  MapViewModel.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import Foundation
import MapboxMaps
import CoreLocation
import SwiftUI
import Combine

class LocationViewModel: ObservableObject {
    // Published properties for view
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var cameraOptions: CameraOptions
    @Published var isTrackingLocation: Bool = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    // Services
    private let locationService: LocationServiceProtocol
    private let firebaseService: FirebaseServiceProtocol
    private let currentUser: User
    
    // Default initialization
    init(
        locationService: LocationServiceProtocol = LocationService(),
        firebaseService: FirebaseServiceProtocol = FirebaseService(),
        user: User = User.MOCK_USER
    ) {
        self.locationService = locationService
        self.firebaseService = firebaseService
        self.currentUser = user
        
        // Default location settings
        let defaultLocation = CLLocationCoordinate2D(latitude: 21.019900, longitude: -100.000000)
        self.cameraOptions = CameraOptions(center: defaultLocation, zoom: 15)
        
        // Set up location service
        if let locationService = locationService as? LocationService {
            locationService.delegate = self
        }
        
        // Load the last known location from Firebase
        loadLastKnownLocation()
    }
    
    // Start tracking location
    func startTrackingLocation() {
        locationService.requestLocationPermission()
        locationService.startUpdatingLocation()
        isTrackingLocation = true
    }
    
    // Stop tracking location
    func stopTrackingLocation() {
        locationService.stopUpdatingLocation()
        isTrackingLocation = false
    }
    
    // Focus camera on user's location
    func focusOnUserLocation() {
        if let location = userLocation {
            cameraOptions = CameraOptions(center: location, zoom: 15)
        }
    }
    
    // Load last known location from Firebase
    private func loadLastKnownLocation() {
        firebaseService.fetchUserLastLocation(userId: currentUser.id) { [weak self] location in
            DispatchQueue.main.async {
                if let location = location {
                    self?.userLocation = location.toCoordinate()
                    self?.cameraOptions = CameraOptions(center: location.toCoordinate(), zoom: 15)
                }
            }
        }
    }
    
    // Save current location to Firebase
    private func saveLocationToFirebase(coordinate: CLLocationCoordinate2D) {
        let userLocation = UserLocation(coordinate: coordinate)
        firebaseService.saveUserLocation(userId: currentUser.id, location: userLocation)
    }
}

// MARK: - LocationServiceDelegate
extension LocationViewModel: LocationServiceDelegate {
    func locationService(_ service: LocationServiceProtocol, didUpdateLocation location: CLLocation) {
        DispatchQueue.main.async { [weak self] in
            self?.userLocation = location.coordinate
            
            // Save to Firebase
            self?.saveLocationToFirebase(coordinate: location.coordinate)
            
            // Update camera if tracking is enabled
            if self?.isTrackingLocation == true {
                self?.cameraOptions = CameraOptions(center: location.coordinate, zoom: 15)
            }
        }
    }
    
    func locationService(_ service: LocationServiceProtocol, didFailWithError error: Error) {
        print("Location update failed: \(error.localizedDescription)")
    }
    
    func locationService(_ service: LocationServiceProtocol, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.authorizationStatus = status
            
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self?.startTrackingLocation()
            }
        }
    }
}
