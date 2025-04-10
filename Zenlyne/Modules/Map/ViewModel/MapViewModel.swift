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

public class LocationViewModel: ObservableObject {
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var cameraOptions: CameraOptions
    @Published var isTrackingLocation: Bool = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var friendLocations: [String: UserLocation] = [:]
    @Published var friends: [User] = []
    
    private let locationService: LocationServiceProtocol
    private let firebaseService: FirebaseServiceProtocol
    var currentUser: User
    
    // Timer to automatically refresh your friends' locations
    private var refreshTimer: Timer?
    
    // Default initialization
    init(
        locationService: LocationServiceProtocol = LocationService(),
        firebaseService: FirebaseServiceProtocol = FirebaseService(),
        user: User = User.MOCK_USER
    ) {
        self.locationService = locationService
        self.firebaseService = firebaseService
        self.currentUser = user
        
        let defaultLocation = CLLocationCoordinate2D(latitude: 21.019900, longitude: -100.000000)
        self.cameraOptions = CameraOptions(center: defaultLocation, zoom: 15)
        
        if let locationService = locationService as? LocationService {
            locationService.delegate = self
        }
        
        // Load the last known location from Firebase
        loadLastKnownLocation()
        
        // Start timer to refresh friend's location every 30 seconds
        startRefreshTimer()
    }
    
    deinit {
        stopRefreshTimer()
        firebaseService.stopObservingFriendLocations()
    }
    
    func startTrackingLocation() {
        locationService.requestLocationPermission()
        locationService.startUpdatingLocation()
        isTrackingLocation = true
        
        // If position is available, focus immediately
        if let location = userLocation {
            cameraOptions = CameraOptions(center: location, zoom: 15)
        }
        
        // Get the friends list and start listening for their location
        loadFriends()
    }
    
    // Stop tracking location
    func stopTrackingLocation() {
        locationService.stopUpdatingLocation()
        isTrackingLocation = false
        firebaseService.stopObservingFriendLocations()
        stopRefreshTimer()
    }
    
    // Focus camera on user's location
    func focusOnUserLocation() {
        if let location = userLocation {
            cameraOptions = CameraOptions(center: location, zoom: 15)
        }
    }
    
    // Focus camera on friend's location
    func focusOnFriendLocation(friendId: String) {
        if let location = friendLocations[friendId] {
            cameraOptions = CameraOptions(center: location.toCoordinate(), zoom: 15)
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
    
    // Start timer to refresh friend's location
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.loadFriends()
        }
    }
    
    // Stop timer
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // Get friend list from Firebase
    private func loadFriends() {
        firebaseService.fetchFriends(forUserId: currentUser.id) { [weak self] friends in
            DispatchQueue.main.async {
                self?.friends = friends
                
                // Start listening for your friends location
                let friendIds = friends.map { $0.id }
                self?.startObservingFriendLocations(friendIds: friendIds)
            }
        }
    }
    
    // Start listening to your friends' locations in real time
    func startObservingFriendLocations(friendIds: [String]) {
        firebaseService.observeFriendLocations(userIds: friendIds) { [weak self] locations in
            DispatchQueue.main.async {
                self?.friendLocations = locations
            }
        }
    }
    
    // Get user information from ID
    func getFriend(byId id: String) -> User? {
        return friends.first { $0.id == id }
    }
}

// MARK: - LocationServiceDelegate
extension LocationViewModel: LocationServiceDelegate {
    func locationService(_ service: LocationServiceProtocol, didUpdateLocation location: CLLocation) {
        DispatchQueue.main.async { [weak self] in
            self?.userLocation = location.coordinate
            
            // Save to Firebase
            self?.saveLocationToFirebase(coordinate: location.coordinate)
            
            // Automatically update camera when there is a new location if tracking
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
