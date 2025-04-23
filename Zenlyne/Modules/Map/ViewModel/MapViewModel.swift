//
//  LocationViewModel.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import Foundation
import SwiftUI
import CoreLocation
import MapboxMaps
import FirebaseAuth
import FirebaseFirestore
import FirebaseDatabase

class LocationViewModel: NSObject, ObservableObject {
    // User & Friends
    @Published var currentUser: User = User.MOCK_USER
    @Published var friends: [User] = []
    @Published var friendLocations: [String: UserLocation] = [:]
    
    // Location tracking
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var isTrackingLocation: Bool = false
    
    // Camera settings for MapView
    @Published var cameraOptions: CameraOptions
    
    // Services
    private let locationService: LocationServiceProtocol
    private let firebaseService: FirebaseServiceProtocol
    
    // Tracks active observers
    private var locationObserversActive = false
    private var onlineStatusObserversActive = false
    
    // Initialize with default camera position at Ho Chi Minh City
    init(locationService: LocationServiceProtocol = LocationService(),
         firebaseService: FirebaseServiceProtocol = FirebaseService()) {
        // Default camera position (Ho Chi Minh City)
        self.cameraOptions = CameraOptions(
            center: CLLocationCoordinate2D(latitude: 10.762622, longitude: 106.660172),
            zoom: 14.0,
            bearing: 0,
            pitch: 0
        )
        
        self.locationService = locationService
        self.firebaseService = firebaseService
        
        super.init()
        
        // Set delegate for location updates
        if let locationService = locationService as? LocationService {
            locationService.delegate = self
        }
    }
    
    // MARK: - Location Tracking
    
    func startTrackingLocation() {
        print("DEBUG: Starting location tracking")
        locationService.requestAlwaysAuthorization()
        locationService.startUpdatingLocation()
        
        // Set user as online
        if let userId = Auth.auth().currentUser?.uid {
            firebaseService.setUserOnlineStatus(userId: userId, isOnline: true)
        }
    }
    
    func stopTrackingLocation() {
        print("DEBUG: Stopping location tracking")
        locationService.stopUpdatingLocation()
        
        // Set user as offline
        if let userId = Auth.auth().currentUser?.uid {
            firebaseService.setUserOnlineStatus(userId: userId, isOnline: false)
        }
        
        // Stop all observers
        if locationObserversActive {
            firebaseService.stopObservingFriendLocations()
            locationObserversActive = false
        }
        
        if onlineStatusObserversActive {
            for friend in friends {
                firebaseService.stopObservingUserOnlineStatus(userId: friend.id)
            }
            onlineStatusObserversActive = false
        }
    }
    
    // MARK: - Map Camera Control
    
    func focusOnUserLocation() {
        guard let userLocation = userLocation else { return }
        
        // Animate camera to user location
        cameraOptions = CameraOptions(
            center: userLocation,
            zoom: 15.0,
            bearing: 0,
            pitch: 0
        )
        
        isTrackingLocation = true
    }
    
    func focusOnFriendLocation(friendId: String) {
        guard let friendLocation = friendLocations[friendId] else { return }
        
        // Animate camera to friend location
        cameraOptions = CameraOptions(
            center: friendLocation.toCoordinate(),
            zoom: 15.0,
            bearing: 0,
            pitch: 0
        )
        
        isTrackingLocation = false
    }
    
    // MARK: - Friend Location Observers
    
    func startObservingFriendLocations(friendIds: [String]) {
        guard !friendIds.isEmpty else { return }
        
        print("DEBUG: Starting to observe locations for \(friendIds.count) friends")
        
        // Start observing friend locations
        firebaseService.observeFriendLocations(userIds: friendIds) { [weak self] locations in
            guard let self = self else { return }
            
            print("DEBUG: Received \(locations.count) friend locations")
            
            // Update friend locations in main thread
            DispatchQueue.main.async {
                self.friendLocations = locations
            }
        }
        
        locationObserversActive = true
    }
    
    func startObservingFriendOnlineStatus(friendIds: [String]) {
        guard !friendIds.isEmpty else { return }
        
        print("DEBUG: Starting to observe online status for \(friendIds.count) friends")
        
        // Observe online status for each friend
        for friendId in friendIds {
            firebaseService.observeUserOnlineStatus(userId: friendId) { [weak self] isOnline in
                guard let self = self else { return }
                
                // Update friend's online status
                DispatchQueue.main.async {
                    if let index = self.friends.firstIndex(where: { $0.id == friendId }) {
                        self.friends[index].isOnline = isOnline
                        
                        if !isOnline {
                            // Update last seen time
                            let database = Database.database().reference()
                            database.child("users").child(friendId).child("lastSeen").observeSingleEvent(of: .value) { snapshot in
                                if let timestamp = snapshot.value as? Double {
                                    let date = Date(timeIntervalSince1970: timestamp / 1000)
                                    DispatchQueue.main.async {
                                        self.friends[index].lastSeen = date
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        onlineStatusObserversActive = true
    }
    
    // MARK: - Helper Methods
    
    func getFriend(byId id: String) -> User? {
        return friends.first { $0.id == id }
    }
    
    func timeSinceLastUpdate(friendId: String) -> String? {
        guard let location = friendLocations[friendId] else { return nil }
        
        let locationDate = Date(timeIntervalSince1970: location.timestamp)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        
        return formatter.localizedString(for: locationDate, relativeTo: Date())
    }
}

// MARK: - LocationServiceDelegate

extension LocationViewModel: LocationServiceDelegate {
    func locationService(_ service: LocationServiceProtocol, didUpdateLocation location: CLLocation) {
        // Update UI with new location
        DispatchQueue.main.async {
            self.userLocation = location.coordinate
            
            // If tracking is enabled, update camera to follow user
            if self.isTrackingLocation {
                self.cameraOptions = CameraOptions(
                    center: location.coordinate,
                    zoom: self.cameraOptions.zoom,
                    bearing: self.cameraOptions.bearing,
                    pitch: self.cameraOptions.pitch
                )
            }
        }
        
        // Save location to Firebase
        if let userId = Auth.auth().currentUser?.uid {
            let userLocation = UserLocation(coordinate: location.coordinate)
            firebaseService.saveUserLocation(userId: userId, location: userLocation)
        }
    }
    
    func locationService(_ service: LocationServiceProtocol, didFailWithError error: Error) {
        print("DEBUG: Location error: \(error.localizedDescription)")
    }
    
    func locationService(_ service: LocationServiceProtocol, didChangeAuthorization status: CLAuthorizationStatus) {
        print("DEBUG: Location authorization status changed: \(status.rawValue)")
        
        // Start tracking when authorized
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationService.startUpdatingLocation()
        }
    }
}
