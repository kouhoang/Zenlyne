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
    
    // MARK: - Published Properties
    @Published var currentMapStyle: MapStyle = .streets
    @Published var currentUser: User = User.MOCK_USER
    @Published var friends: [User] = []
    @Published var friendLocations: [String: UserLocation] = [:]
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var isTrackingLocation: Bool = false
    @Published var cameraOptions: CameraOptions
    @Published var currentZoomLevel: Double = 14.0
    @Published var shouldUpdateCamera: Bool = false // Control camera updates
    
    // MARK: - Combine Publishers
    @Published private var locationTrackingState: LocationTrackingState = .idle
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Services
    private let locationService: LocationServiceProtocol
    private let firebaseService: FirebaseServiceProtocol
    let friendLocationGrouper = FriendLocationGrouper()
    
    // MARK: - Internal State
    private var locationObserversActive = false
    private var onlineStatusObserversActive = false
    private var friendsListListener: ListenerRegistration?
    
    // Timer for periodic cleanup
    private var cleanupTimer: Timer?
    
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
        setupPeriodicCleanup()
    }
    
    // MARK: - Private Setup
    private func setupCombineBindings() {
        // Observe location tracking state changes
        $locationTrackingState
            .receive(on: DispatchQueue.main)
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
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.handleUserLocationUpdate(location)
            }
            .store(in: &cancellables)
        
        // Observe friend locations and update clustering
        $friendLocations
            .combineLatest($friends, $currentZoomLevel)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] locations, friends, zoomLevel in
                self?.handleFriendLocationsUpdate(locations: locations, friends: friends, zoomLevel: zoomLevel)
            }
            .store(in: &cancellables)
        
        // Observe zoom level changes for clustering
        $currentZoomLevel
            .removeDuplicates { abs($0 - $1) < 0.5 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] zoomLevel in
                self?.friendLocationGrouper.updateZoomLevel(zoomLevel)
                self?.handleZoomLevelChanged(zoomLevel)
            }
            .store(in: &cancellables)
    }
    
    private func handleUserLocationUpdate(_ location: CLLocationCoordinate2D) {
        print("DEBUG: User location updated via Combine: \(location.latitude), \(location.longitude)")
    }
    
    private func handleFriendLocationsUpdate(locations: [String: UserLocation], friends: [User], zoomLevel: Double) {
        // Filter out expired locations (older than 72 hours)
        let currentTime = Date().timeIntervalSince1970
        let expirationTime: TimeInterval = 72 * 60 * 60 // 72 hours
        
        let validLocations = locations.filter { _, location in
            (currentTime - location.timestamp) < expirationTime
        }
        
        print("DEBUG: Friend locations updated via Combine: \(validLocations.count) valid locations for \(friends.count) friends")
        
        // Update the published property if different
        if validLocations != friendLocations {
            friendLocations = validLocations
        }
    }
    
    private func handleZoomLevelChanged(_ zoomLevel: Double) {
        print("DEBUG: Zoom level changed to: \(zoomLevel)")
        
        // Auto-expand clusters at high zoom levels
        if zoomLevel >= 16.0 {
            friendLocationGrouper.expandAllClusters()
        } else if zoomLevel < 12.0 {
            friendLocationGrouper.collapseAllClusters()
        }
    }
    
    private func setupPeriodicCleanup() {
        // Clean up expired locations every 30 minutes
        Task { @MainActor in
            cleanupTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.cleanupExpiredLocations()
                }
            }
        }
    }
    
    private func cleanupExpiredLocations() {
        let currentTime = Date().timeIntervalSince1970
        let expirationTime: TimeInterval = 72 * 60 * 60 // 72 hours
        
        var updatedLocations = friendLocations
        var hasChanges = false
        
        for (friendId, location) in friendLocations {
            if (currentTime - location.timestamp) >= expirationTime {
                updatedLocations.removeValue(forKey: friendId)
                hasChanges = true
                print("DEBUG: Removed expired location for friend: \(friendId)")
            }
        }
        
        if hasChanges {
            friendLocations = updatedLocations
        }
    }
    
    // MARK: - Location Tracking
    
    func startTrackingLocation() {
        print("DEBUG: Starting location tracking")
        locationTrackingState = .requesting
        
        locationService.requestAlwaysAuthorization()
        locationService.startUpdatingLocation()
        
        // Set user as online
        if let userId = Auth.auth().currentUser?.uid {
            firebaseService.setUserOnlineStatus(userId: userId, isOnline: true)
        }
        
        // Start monitoring friends
        startMonitoringFriends()
    }
    
    func stopTrackingLocation() {
        print("DEBUG: Stopping location tracking")
        locationService.stopUpdatingLocation()
        locationTrackingState = .idle
        
        // Set user as offline
        if let userId = Auth.auth().currentUser?.uid {
            firebaseService.setUserOnlineStatus(userId: userId, isOnline: false)
        }
        
        stopMonitoringFriends()
    }
    
    // MARK: - Friends Monitoring with Combine
    
    private func startMonitoringFriends() {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            print("DEBUG: No current user ID available")
            return
        }
        
        print("DEBUG: Starting to monitor friends for user: \(currentUserId)")
        
        // Use Combine to observe friends list
        firebaseService.friendsPublisher(forUserId: currentUserId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] friends in
                guard let self = self else { return }
                
                print("DEBUG: Received \(friends.count) friends via Combine")
                self.friends = friends
                
                if !friends.isEmpty {
                    let friendIds = friends.map { $0.id }
                    self.startObservingFriendLocations(friendIds: friendIds)
                    self.startObservingFriendOnlineStatus(friendIds: friendIds)
                } else {
                    print("DEBUG: No friends to monitor")
                }
            }
            .store(in: &cancellables)
        
        // Also observe friend locations using Combine
        if !friends.isEmpty {
            let friendIds = friends.map { $0.id }
            firebaseService.friendLocationsPublisher(userIds: friendIds)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] locations in
                    guard let self = self else { return }
                    
                    // Filter expired locations
                    let currentTime = Date().timeIntervalSince1970
                    let expirationTime: TimeInterval = 72 * 60 * 60
                    
                    let validLocations = locations.filter { _, location in
                        (currentTime - location.timestamp) < expirationTime
                    }
                    
                    print("DEBUG: Received \(validLocations.count) valid friend locations via Combine")
                    self.friendLocations = validLocations
                }
                .store(in: &cancellables)
        }
    }
    
    private nonisolated func stopMonitoringFriends() {
        Task { @MainActor in
            // Cancel all Combine subscriptions
            cancellables.removeAll()
            
            // Stop Firebase observers
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
            
            // Re-setup basic Combine bindings
            setupCombineBindings()
        }
    }
    
    // MARK: - Map Camera Control
    
    func focusOnUserLocation() {
        guard let userLocation = userLocation else {
            print("DEBUG: No user location available to focus")
            return
        }
        
        // Only update camera when explicitly requested
        cameraOptions = CameraOptions(
            center: userLocation,
            zoom: 16.0, // Fixed zoom level
            bearing: 0,
            pitch: 0
        )
        
        // Trigger one-time camera update
        triggerCameraUpdate()
        
        print("DEBUG: Focused camera on user location: \(userLocation.latitude), \(userLocation.longitude)")
    }
    
    func toggleMapStyle() {
        currentMapStyle = currentMapStyle.nextStyle()
    }
    
    func updateZoomLevel(_ zoomLevel: Double) {
        if abs(currentZoomLevel - zoomLevel) > 0.1 {
            currentZoomLevel = zoomLevel
        }
    }
    
    // Trigger camera update for specific actions only
    private func triggerCameraUpdate() {
        // Set flag to trigger camera update in MapViewRepresentable
        shouldUpdateCamera = true
    }
    
    // MARK: - Friend Location Observers (Legacy support)
    
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
            
            // Filter expired locations
            let currentTime = Date().timeIntervalSince1970
            let expirationTime: TimeInterval = 72 * 60 * 60 // 72 hours
            
            let validLocations = locations.filter { _, location in
                (currentTime - location.timestamp) < expirationTime
            }
            
            print("DEBUG: Received \(validLocations.count) valid friend locations")
            
            for (friendId, location) in validLocations {
                let friend = self.friends.first(where: { $0.id == friendId })?.fullName ?? "Unknown"
                print("DEBUG: Friend \(friend) (\(friendId)) location: \(location.latitude), \(location.longitude)")
            }
            
            // Update friend location in main thread
            Task { @MainActor in
                self.friendLocations = validLocations
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
    
    // MARK: - Clustering Management
    
    func getLocationGroups() -> [LocationGroup] {
        return friendLocationGrouper.groupFriendLocations(friendLocations)
    }
    
    func toggleClusterExpansion(clusterId: String) -> Bool {
        return friendLocationGrouper.toggleClusterExpansion(clusterId: clusterId)
    }
    
    func isClusterExpanded(clusterId: String) -> Bool {
        return friendLocationGrouper.isClusterExpanded(clusterId: clusterId)
    }
    
    func focusOnCluster(clusterId: String, expanded: Bool = true) {
        let locationGroups = friendLocationGrouper.groupFriendLocations(friendLocations)
        
        if let group = locationGroups.first(where: {
            $0.type == .cluster &&
            $0.friendIds.sorted().joined(separator: "_") == clusterId
        }) {
            if expanded {
                _ = friendLocationGrouper.toggleClusterExpansion(clusterId: clusterId)
            }
            
            cameraOptions = CameraOptions(
                center: group.centerCoordinate,
                zoom: 15.5,
                bearing: 0,
                pitch: 0
            )
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
    
    func focusOnFriendLocation(friendId: String) {
        print("DEBUG: Focusing on friend location for friend ID: \(friendId)")
        
        guard let friendLocation = friendLocations[friendId] else {
            print("DEBUG: No location found for friend with ID: \(friendId)")
            print("DEBUG: Available friend locations: \(friendLocations.keys.joined(separator: ", "))")
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
    
    func debugFriendLocations() {
        print("DEBUG: Current friend locations:")
        for (friendId, location) in friendLocations {
            let ageInHours = (Date().timeIntervalSince1970 - location.timestamp) / 3600
            let friend = friends.first(where: { $0.id == friendId})?.fullName ?? "Unknown"
            print("DEBUG: Friend: \(friend) (\(friendId)) - Location: \(location.latitude), \(location.longitude) - Age: \(String(format: "%.1f", ageInHours)) hours")
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        Task { @MainActor in
            cleanupTimer?.invalidate()
        }
        // Note: stopMonitoringFriends() will be called automatically when cancellables are deallocated
    }
}

// MARK: - LocationServiceDelegate
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
    
    /// Publisher for zoom level changes
    var zoomLevelPublisher: AnyPublisher<Double, Never> {
        $currentZoomLevel
            .removeDuplicates { abs($0 - $1) < 0.1 }
            .eraseToAnyPublisher()
    }
    
    /// Publisher for location groups (clusters)
    var locationGroupsPublisher: AnyPublisher<[LocationGroup], Never> {
        friendLocationsPublisher
            .combineLatest(zoomLevelPublisher)
            .receive(on: DispatchQueue.main)
            .map { [weak self] locations, zoomLevel in
                guard let self = self else { return [] }
                self.friendLocationGrouper.updateZoomLevel(zoomLevel)
                return self.friendLocationGrouper.groupFriendLocations(locations)
            }
            .removeDuplicates { lhs, rhs in
                return lhs.count == rhs.count &&
                       lhs.map { "\($0.friendIds.sorted().joined())_\($0.type)" } ==
                       rhs.map { "\($0.friendIds.sorted().joined())_\($0.type)" }
            }
            .eraseToAnyPublisher()
    }
}
