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
    // Published properties for view
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var cameraOptions: CameraOptions
    @Published var isTrackingLocation: Bool = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var friendLocations: [String: UserLocation] = [:]
    @Published var friends: [User] = []
    
    // Services
    private let locationService: LocationServiceProtocol
    private let firebaseService: FirebaseServiceProtocol
    var currentUser: User
    
    // Timer để tự động refresh vị trí của bạn bè
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
        
        // Default location settings
        let defaultLocation = CLLocationCoordinate2D(latitude: 21.019900, longitude: -100.000000)
        self.cameraOptions = CameraOptions(center: defaultLocation, zoom: 15)
        
        // Set up location service
        if let locationService = locationService as? LocationService {
            locationService.delegate = self
        }
        
        // Load the last known location from Firebase
        loadLastKnownLocation()
        
        // Bắt đầu timer để refresh vị trí của bạn bè mỗi 30 giây
        startRefreshTimer()
    }
    
    deinit {
        stopRefreshTimer()
        firebaseService.stopObservingFriendLocations()
    }
    
    // Start tracking location
    func startTrackingLocation() {
        locationService.requestLocationPermission()
        locationService.startUpdatingLocation()
        isTrackingLocation = true
        
        // Nếu đã có vị trí, focus ngay lập tức
        if let location = userLocation {
            cameraOptions = CameraOptions(center: location, zoom: 15)
        }
        
        // Lấy danh sách bạn bè và bắt đầu lắng nghe vị trí của họ
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
    
    // Bắt đầu timer để refresh vị trí của bạn bè
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.loadFriends()
        }
    }
    
    // Dừng timer
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // Lấy danh sách bạn bè từ Firebase
    private func loadFriends() {
        firebaseService.fetchFriends(forUserId: currentUser.id) { [weak self] friends in
            DispatchQueue.main.async {
                self?.friends = friends
                
                // Bắt đầu lắng nghe vị trí của bạn bè
                let friendIds = friends.map { $0.id }
                self?.startObservingFriendLocations(friendIds: friendIds)
            }
        }
    }
    
    // Bắt đầu lắng nghe vị trí của bạn bè theo thời gian thực
    private func startObservingFriendLocations(friendIds: [String]) {
        firebaseService.observeFriendLocations(userIds: friendIds) { [weak self] locations in
            DispatchQueue.main.async {
                self?.friendLocations = locations
            }
        }
    }
    
    // Lấy thông tin user từ ID
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
            
            // Tự động update camera khi có location mới nếu đang tracking
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
