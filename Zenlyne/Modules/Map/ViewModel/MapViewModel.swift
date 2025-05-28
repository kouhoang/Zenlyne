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

// MARK: - Map Style Options
enum MapStyle {
    case streets
    case satellite
    case satelliteStreets
    
    var mapboxStyle: StyleURI {
        switch self {
        case .streets:
            return .streets
        case .satellite:
            return .satellite
        case .satelliteStreets:
            return .satelliteStreets
        }
    }
    
    var displayName: String {
        switch self {
        case .streets:
            return "Standard"
        case .satellite:
            return "Satellite"
        case .satelliteStreets:
            return "Hybrid"
        }
    }
    
    var iconName: String {
        switch self {
        case .streets:
            return "map"
        case .satellite:
            return "globe"
        case .satelliteStreets:
            return "building.2"
        }
    }
    
    // Get the next style in the cycle
    func nextStyle() -> MapStyle {
        switch self {
        case .streets:
            return .satellite
        case .satellite:
            return .satelliteStreets
        case .satelliteStreets:
            return .streets
        }
    }
}

class LocationViewModel: NSObject, ObservableObject {
    @Published var currentMapStyle: MapStyle = .streets
    
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
    
    private var clusterState = ClusterState()
    
    // Initialize with default camera position at NWS
    init(locationService: LocationServiceProtocol = LocationService(),
         firebaseService: FirebaseServiceProtocol = FirebaseService()) {
        // Default camera position (NWS)
        self.cameraOptions = CameraOptions(
            center: CLLocationCoordinate2D(latitude: 21.01991, longitude: 105.7838),
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
        guard let userLocation = userLocation else {
            print("DEBUG: No user location available to focus")
            return
        }
        
        DispatchQueue.main.async {
            self.cameraOptions = CameraOptions(
                center: userLocation,
                zoom: 15.0,
                bearing: 0,
                pitch: 0
            )
            self.isTrackingLocation = true
            print("DEBUG: Focused camera on user location: \(userLocation.latitude), \(userLocation.longitude)")
        }
    }
    
    func toggleMapStyle() {
        currentMapStyle = currentMapStyle.nextStyle()
    }
    
    // MARK: - Friend Location Observers
    
    func startObservingFriendLocations(friendIds: [String]) {
        guard !friendIds.isEmpty else {
            print("DEBUG: No friends to observe locations for")
            return
        }
        
        print("DEBUG: Starting to observe locations for \(friendIds.count) friends: \(friendIds)")
        
        // Stop current observers if any
        if locationObserversActive {
            firebaseService.stopObservingFriendLocations()
        }
        
        // Start observing friends location
        firebaseService.observeFriendLocations(userIds: friendIds) { [weak self] locations in
            guard let self = self else { return }
            
            print("DEBUG: Received \(locations.count) friend locations")
            
            for (friendId, location) in locations {
                let friend = self.friends.first(where: { $0.id == friendId })?.fullName ?? "Unknown"
                print("DEBUG: Friend \(friend) (\(friendId)) location: \(location.latitude), \(location.longitude)")
            }
            
            // Update friend location in main thread
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
    
    func debugFriendLocations() {
        print("DEBUG: Current friend locations:")
        for (friendId, location) in friendLocations {
            let ageInHours = (Date().timeIntervalSince1970 - location.timestamp) / 3600
            let friend = friends.first(where: { $0.id == friendId})?.fullName ?? "Unknown"
            print("DEBUG: Friend: \(friend) (\(friendId)) - Location: \(location.latitude), \(location.longitude) - Age: \(String(format: "%.1f", ageInHours)) hours")
        }
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
    
    func monitorFriendsAndLocations() {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            print("DEBUG: No current user ID available")
            return
        }
        
        print("DEBUG: Monitoring friends and locations for user: \(currentUserId)")
        
        // Load friends list
        firebaseService.fetchFriends(forUserId: currentUserId) { [weak self] friends in
            guard let self = self else { return }
            
            print("DEBUG: Loaded \(friends.count) friends")
            
            DispatchQueue.main.async {
                self.friends = friends
                
                // Start observing your friends' location and status
                if !friends.isEmpty {
                    let friendIds = friends.map { $0.id }
                    self.startObservingFriendLocations(friendIds: friendIds)
                    self.startObservingFriendOnlineStatus(friendIds: friendIds)
                } else {
                    print("DEBUG: No friends to monitor")
                }
            }
        }
    }
    
    func focusOnFriendLocation(friendId: String) {
        print("DEBUG: Focusing on friend location for friend ID: \(friendId)")
        
        guard let friendLocation = friendLocations[friendId] else {
            print("DEBUG: No location found for friend with ID: \(friendId)")
            
            // Display debug information about existing locations
            print("DEBUG: Available friend locations: \(friendLocations.keys.joined(separator: ", "))")
            
            // Check database directly
            debugFriendLocationsInDatabase()
            return
        }
        
        let coordinate = friendLocation.toCoordinate()
        print("DEBUG: Friend location found: \(coordinate.latitude), \(coordinate.longitude)")
        
        // Animate camera to friend location
        cameraOptions = CameraOptions(
            center: coordinate,
            zoom: 15.0,
            bearing: 0,
            pitch: 0
        )
        
        isTrackingLocation = false
    }
    
    func debugFriendLocationsInDatabase() {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            print("DEBUG: No current user ID available")
            return
        }
        
        let db = Firestore.firestore()
        
        // Get friends list
        db.collection("users").document(currentUserId).getDocument { snapshot, error in
            guard let document = snapshot, document.exists,
                  let data = document.data(),
                  let friendIds = data["friendIds"] as? [String] else {
                print("DEBUG: No friends found")
                return
            }
            
            // Check the location of each friend
            for friendId in friendIds {
                db.collection("users").document(friendId).getDocument { snapshot, error in
                    if let error = error {
                        print("DEBUG: Error fetching friend \(friendId): \(error.localizedDescription)")
                        return
                    }
                    
                    guard let document = snapshot, document.exists,
                          let data = document.data() else {
                        print("DEBUG: Friend document not found: \(friendId)")
                        return
                    }
                    
                    let name = data["fullName"] as? String ?? "Unknown"
                    
                    if let locationData = data["lastLocation"] as? [String: Any] {
                        if let lat = locationData["latitude"] as? Double,
                           let lon = locationData["longitude"] as? Double,
                           let timestamp = locationData["timestamp"] as? TimeInterval {
                            
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateStyle = .medium
                            dateFormatter.timeStyle = .medium
                            let date = Date(timeIntervalSince1970: timestamp)
                            
                            print("DEBUG: Friend \(name) (\(friendId)) location: \(lat), \(lon), Updated: \(dateFormatter.string(from: date))")
                            
                            if let expiresAt = locationData["expiresAt"] as? TimeInterval {
                                let expiryDate = Date(timeIntervalSince1970: expiresAt)
                                print("DEBUG:   Expires: \(dateFormatter.string(from: expiryDate))")
                            }
                        } else {
                            print("DEBUG: Friend \(name) (\(friendId)) has invalid location data format")
                        }
                    } else {
                        print("DEBUG: Friend \(name) (\(friendId)) has no location data")
                    }
                    
                    let isOnline = data["isOnline"] as? Bool ?? false
                    print("DEBUG: Friend \(name) (\(friendId)) is \(isOnline ? "online" : "offline")")
                }
            }
        }
    }
}

// MARK: - LocationServiceDelegate

extension LocationViewModel: LocationServiceDelegate {
    func locationService(_ service: LocationServiceProtocol, didUpdateLocation location: CLLocation) {
        // Only upadte userLocation, do not change cameraOptions
        DispatchQueue.main.async {
            self.userLocation = location.coordinate
            print("DEBUG: Updated user location to \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }
        
        // Sava location into Firebase
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

extension LocationViewModel {
    // Track expanded cluster IDs
    private struct ClusterState {
        var expandedClusterIds: Set<String> = []
        var currentZoomLevel: Double = 14.0
        var autoExpandThreshold: Double = 16.0
    }
    
    // Update current zoom level
    func updateMapZoomLevel(_ zoomLevel: Double) {
        clusterState.currentZoomLevel = zoomLevel
        
        // Auto-expand clusters at high zoom levels
        if zoomLevel >= clusterState.autoExpandThreshold {
            expandAllClustersInView()
        } else if zoomLevel < clusterState.autoExpandThreshold - 1.0 {
            // Collapse clusters when zoomed out
            collapseAllClusters()
        }
    }
    
    // Toggle a specific cluster's expansion state
    func toggleClusterExpansion(clusterId: String) -> Bool {
        if clusterState.expandedClusterIds.contains(clusterId) {
            clusterState.expandedClusterIds.remove(clusterId)
            return false // Now collapsed
        } else {
            clusterState.expandedClusterIds.insert(clusterId)
            return true // Now expanded
        }
    }
    
    // Check if a cluster is expanded
    func isClusterExpanded(clusterId: String) -> Bool {
        return clusterState.expandedClusterIds.contains(clusterId)
    }
    
    // Expand all clusters currently in view
    private func expandAllClustersInView() {
        // For now, we'll simply flag all clusters as expanded
        // In a real implementation, you would only expand clusters visible in the current camera view
        
        // Process current friend locations to identify clusters
        let friendLocationGetter = FriendLocationGrouper()
        friendLocationGetter.updateZoomLevel(clusterState.currentZoomLevel)
        
        let locationGroups = friendLocationGetter.groupFriendLocations(friendLocations)
        
        // Mark all multi-friend clusters as expanded
        for group in locationGroups {
            if group.type == .cluster && group.count >= 2 {
                let clusterId = group.friendIds.sorted().joined(separator: "_")
                clusterState.expandedClusterIds.insert(clusterId)
            }
        }
        
        // Notify that clusters have changed to trigger update
        self.objectWillChange.send()
    }
    
    // Collapse all currently expanded clusters
    private func collapseAllClusters() {
        if !clusterState.expandedClusterIds.isEmpty {
            clusterState.expandedClusterIds.removeAll()
            
            // Notify that clusters have changed to trigger update
            self.objectWillChange.send()
        }
    }
    
    // Focus on a specific cluster
    func focusOnCluster(clusterId: String, expanded: Bool = true) {
        // Find the relevant group for this cluster ID
        let friendLocationGetter = FriendLocationGrouper()
        let locationGroups = friendLocationGetter.groupFriendLocations(friendLocations)
        
        // Find the cluster's center point
        if let group = locationGroups.first(where: {
            $0.type == .cluster &&
            $0.friendIds.sorted().joined(separator: "_") == clusterId
        }) {
            // Set expanded state if requested
            if expanded {
                clusterState.expandedClusterIds.insert(clusterId)
            }
            
            // Focus camera on the cluster
            cameraOptions = CameraOptions(
                center: group.centerCoordinate,
                zoom: 15.5, // Higher zoom to better see the expanded cluster
                bearing: 0,
                pitch: 0
            )
            
            // Notify changes
            self.objectWillChange.send()
        }
    }
    
    // Get all currently expanded cluster IDs
    func getExpandedClusterIds() -> Set<String> {
        return clusterState.expandedClusterIds
    }
}
