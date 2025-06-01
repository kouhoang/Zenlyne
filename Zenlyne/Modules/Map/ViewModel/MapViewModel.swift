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
import Combine

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

// MARK: - Location States
enum LocationTrackingState {
    case idle
    case requesting
    case tracking
    case denied
    case error(String)
}

@MainActor
class LocationViewModel: NSObject, ObservableObject {
    
    // MARK: - Published Properties (Giữ nguyên để tương thích)
    @Published var currentMapStyle: MapStyle = .streets
    @Published var currentUser: User = User.MOCK_USER
    @Published var friends: [User] = []
    @Published var friendLocations: [String: UserLocation] = [:]
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var isTrackingLocation: Bool = false
    @Published var cameraOptions: CameraOptions
    
    // MARK: - Combine Publishers
    @Published private var locationTrackingState: LocationTrackingState = .idle
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Services
    private let locationService: LocationServiceProtocol
    private let firebaseService: FirebaseServiceProtocol
    
    // MARK: - Internal State
    private var locationObserversActive = false
    private var onlineStatusObserversActive = false
    private var clusterState = ClusterState()
    
    // MARK: - Initialization
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
        
        setupCombineBindings()
    }
    
    // MARK: - Private Setup
    private func setupCombineBindings() {
        // Observe location tracking state changes
        $locationTrackingState
            .sink { [weak self] state in
                switch state {
                case .tracking:
                    self?.isTrackingLocation = true
                case .denied, .error, .idle:
                    self?.isTrackingLocation = false
                case .requesting:
                    break
                }
            }
            .store(in: &cancellables)
        
        // Observe user location changes and update camera if needed
        $userLocation
            .compactMap { $0 }
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] location in
                self?.handleUserLocationUpdate(location)
            }
            .store(in: &cancellables)
        
        // Observe friend locations and update clustering
        $friendLocations
            .combineLatest($friends)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] locations, friends in
                self?.handleFriendLocationsUpdate(locations: locations, friends: friends)
            }
            .store(in: &cancellables)
    }
    
    private func handleUserLocationUpdate(_ location: CLLocationCoordinate2D) {
        print("DEBUG: User location updated via Combine: \(location.latitude), \(location.longitude)")
    }
    
    private func handleFriendLocationsUpdate(locations: [String: UserLocation], friends: [User]) {
        print("DEBUG: Friend locations updated via Combine: \(locations.count) locations for \(friends.count) friends")
    }
    
    // MARK: - Location Tracking (Giữ nguyên interface)
    
    func startTrackingLocation() {
        print("DEBUG: Starting location tracking")
        locationTrackingState = .requesting
        
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
        locationTrackingState = .idle
        
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
    
    // MARK: - Map Camera Control (Giữ nguyên interface)
    
    func focusOnUserLocation() {
        guard let userLocation = userLocation else {
            print("DEBUG: No user location available to focus")
            return
        }
        
        cameraOptions = CameraOptions(
            center: userLocation,
            zoom: 15.0,
            bearing: 0,
            pitch: 0
        )
        isTrackingLocation = true
        print("DEBUG: Focused camera on user location: \(userLocation.latitude), \(userLocation.longitude)")
    }
    
    func toggleMapStyle() {
        currentMapStyle = currentMapStyle.nextStyle()
    }
    
    // MARK: - Friend Location Observers (Giữ nguyên interface)
    
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
            Task { @MainActor in
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
                Task { @MainActor in
                    if let index = self.friends.firstIndex(where: { $0.id == friendId }) {
                        self.friends[index].isOnline = isOnline
                        
                        if !isOnline {
                            // Update last seen time
                            let database = Database.database().reference()
                            database.child("users").child(friendId).child("lastSeen").observeSingleEvent(of: .value) { snapshot in
                                if let timestamp = snapshot.value as? Double {
                                    let date = Date(timeIntervalSince1970: timestamp / 1000)
                                    Task { @MainActor in
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
    
    // MARK: - Helper Methods (Giữ nguyên interface)
    
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
            
            Task { @MainActor in
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
            print("DEBUG: Available friend locations: \(friendLocations.keys.joined(separator: ", "))")
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

// MARK: - LocationServiceDelegate (Giữ nguyên)
extension LocationViewModel: LocationServiceDelegate {
    func locationService(_ service: LocationServiceProtocol, didUpdateLocation location: CLLocation) {
        // Update userLocation and tracking state
        userLocation = location.coordinate
        locationTrackingState = .tracking
        
        print("DEBUG: Updated user location to \(location.coordinate.latitude), \(location.coordinate.longitude)")
        
        // Save location to Firebase
        if let userId = Auth.auth().currentUser?.uid {
            let userLocation = UserLocation(coordinate: location.coordinate)
            firebaseService.saveUserLocation(userId: userId, location: userLocation)
        }
    }
    
    func locationService(_ service: LocationServiceProtocol, didFailWithError error: Error) {
        print("DEBUG: Location error: \(error.localizedDescription)")
        locationTrackingState = .error(error.localizedDescription)
    }
    
    func locationService(_ service: LocationServiceProtocol, didChangeAuthorization status: CLAuthorizationStatus) {
        print("DEBUG: Location authorization status changed: \(status.rawValue)")
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationService.startUpdatingLocation()
            locationTrackingState = .tracking
        case .denied, .restricted:
            locationTrackingState = .denied
        case .notDetermined:
            locationTrackingState = .requesting
        @unknown default:
            locationTrackingState = .idle
        }
    }
}

// MARK: - Cluster Management (Giữ nguyên interface)
extension LocationViewModel {
    
    private struct ClusterState {
        var expandedClusterIds: Set<String> = []
        var currentZoomLevel: Double = 14.0
        var autoExpandThreshold: Double = 16.0
    }
    
    func updateMapZoomLevel(_ zoomLevel: Double) {
        clusterState.currentZoomLevel = zoomLevel
        
        // Auto-expand clusters at high zoom levels
        if zoomLevel >= clusterState.autoExpandThreshold {
            expandAllClustersInView()
        } else if zoomLevel < clusterState.autoExpandThreshold - 1.0 {
            collapseAllClusters()
        }
    }
    
    func toggleClusterExpansion(clusterId: String) -> Bool {
        if clusterState.expandedClusterIds.contains(clusterId) {
            clusterState.expandedClusterIds.remove(clusterId)
            return false
        } else {
            clusterState.expandedClusterIds.insert(clusterId)
            return true
        }
    }
    
    func isClusterExpanded(clusterId: String) -> Bool {
        return clusterState.expandedClusterIds.contains(clusterId)
    }
    
    private func expandAllClustersInView() {
        let friendLocationGetter = FriendLocationGrouper()
        friendLocationGetter.updateZoomLevel(clusterState.currentZoomLevel)
        
        let locationGroups = friendLocationGetter.groupFriendLocations(friendLocations)
        
        for group in locationGroups {
            if group.type == .cluster && group.count >= 2 {
                let clusterId = group.friendIds.sorted().joined(separator: "_")
                clusterState.expandedClusterIds.insert(clusterId)
            }
        }
        
        objectWillChange.send()
    }
    
    private func collapseAllClusters() {
        if !clusterState.expandedClusterIds.isEmpty {
            clusterState.expandedClusterIds.removeAll()
            objectWillChange.send()
        }
    }
    
    func focusOnCluster(clusterId: String, expanded: Bool = true) {
        let friendLocationGetter = FriendLocationGrouper()
        let locationGroups = friendLocationGetter.groupFriendLocations(friendLocations)
        
        if let group = locationGroups.first(where: {
            $0.type == .cluster &&
            $0.friendIds.sorted().joined(separator: "_") == clusterId
        }) {
            if expanded {
                clusterState.expandedClusterIds.insert(clusterId)
            }
            
            cameraOptions = CameraOptions(
                center: group.centerCoordinate,
                zoom: 15.5,
                bearing: 0,
                pitch: 0
            )
            
            objectWillChange.send()
        }
    }
    
    func getExpandedClusterIds() -> Set<String> {
        return clusterState.expandedClusterIds
    }
}

// MARK: - Combine Publishers
extension LocationViewModel {
    
    /// Publisher that emits location tracking state changes
    var locationTrackingStatePublisher: Published<LocationTrackingState>.Publisher {
        $locationTrackingState
    }
    
    /// Publisher for user location changes
    var userLocationPublisher: AnyPublisher<CLLocationCoordinate2D?, Never> {
        $userLocation
            .removeDuplicates { lhs, rhs in
                guard let lhs = lhs, let rhs = rhs else {
                    return lhs == nil && rhs == nil
                }
                return abs(lhs.latitude - rhs.latitude) < 0.0001 &&
                       abs(lhs.longitude - rhs.longitude) < 0.0001
            }
            .eraseToAnyPublisher()
    }
    
    /// Publisher for friend locations changes
    var friendLocationsPublisher: AnyPublisher<[String: UserLocation], Never> {
        $friendLocations
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    /// Publisher for friends list changes
    var friendsPublisher: AnyPublisher<[User], Never> {
        $friends
            .removeDuplicates { $0.map(\.id) == $1.map(\.id) }
            .eraseToAnyPublisher()
    }
    
    /// Publisher for map style changes
    var mapStylePublisher: AnyPublisher<MapStyle, Never> {
        $currentMapStyle
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    /// Publisher for camera option changes
    var cameraOptionsPublisher: AnyPublisher<CameraOptions, Never> {
        $cameraOptions
            .removeDuplicates { lhs, rhs in
                return lhs.center?.latitude == rhs.center?.latitude &&
                       lhs.center?.longitude == rhs.center?.longitude &&
                       lhs.zoom == rhs.zoom
            }
            .eraseToAnyPublisher()
    }
}
