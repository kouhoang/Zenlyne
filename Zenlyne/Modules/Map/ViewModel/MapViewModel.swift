//
//  LocationViewModel.swift
//  Zenlyne
//
//  Created by kou on 4/6/25.
//

import Foundation
import SwiftUI
import CoreLocation
import MapboxMaps
import FirebaseAuth
import FirebaseFirestore
import FirebaseDatabase
import Combine

// MARK: - Map Style Options (same as before)
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

// MARK: - Location States (same as before)
enum LocationTrackingState {
    case idle
    case requesting
    case tracking
    case denied
    case error(String)
}

// MARK: - Camera Update Reason
enum CameraUpdateReason {
    case userLocation
    case friendLocation(String)
    case clusterFocus(String)
    case userInitiated
    case initialLoad
    case none
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
    @Published var currentMapCenter: CLLocationCoordinate2D?
    @Published var reverseGeocodingService = ReverseGeocodingService()
    
    // CRITICAL: Enhanced camera control
    @Published var shouldUpdateCamera: Bool = false
    private var lastCameraUpdateReason: CameraUpdateReason = .none
    private var lastCameraUpdate: Date = Date.distantPast
    private var isUserInteractingWithMap: Bool = false
    private var cameraUpdateDebounceTimer: Timer?
    
    // MARK: - Location Change Tracking
    private var lastUserLocationUpdate: Date = Date.distantPast
    private var lastFriendLocationsUpdate: Date = Date.distantPast
    private var lastSignificantUserLocation: CLLocationCoordinate2D?
    
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
    
    // MARK: - Constants
    private let minimumCameraUpdateInterval: TimeInterval = 2.0
    private let significantLocationChangeThreshold: Double = 50.0 // meters
    
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
        setupUserInteractionTracking()
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
        
        // Observe user location changes with smart camera updates
        $userLocation
            .compactMap { $0 }
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.handleUserLocationUpdate(location)
            }
            .store(in: &cancellables)
        
        // Observe friend locations with debounced updates
        $friendLocations
            .combineLatest($friends, $currentZoomLevel)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] locations, friends, zoomLevel in
                self?.handleFriendLocationsUpdate(locations: locations, friends: friends, zoomLevel: zoomLevel)
            }
            .store(in: &cancellables)
        
        // Observe zoom level changes for clustering (no camera updates)
        $currentZoomLevel
            .removeDuplicates { abs($0 - $1) < 0.5 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] zoomLevel in
                self?.friendLocationGrouper.updateZoomLevel(zoomLevel)
                self?.handleZoomLevelChanged(zoomLevel)
            }
            .store(in: &cancellables)
    }
    
    private func setupUserInteractionTracking() {
        // Listen for user interaction notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("UserMapInteractionStarted"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isUserInteractingWithMap = true
            print("DEBUG: User interaction with map started")
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("UserMapInteractionEnded"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delay ending interaction to prevent immediate camera updates
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self?.isUserInteractingWithMap = false
                print("DEBUG: User interaction with map ended")
            }
        }
    }
    
    private func handleUserLocationUpdate(_ location: CLLocationCoordinate2D) {
        print("DEBUG: User location updated via Combine: \(location.latitude), \(location.longitude)")
        
        // Check if this is a significant location change
        let isSignificantChange = isSignificantLocationChange(location)
        
        if isSignificantChange {
            print("DEBUG: Significant user location change detected")
            lastSignificantUserLocation = location
            lastUserLocationUpdate = Date()
            
            // Only auto-focus on user location for the first few updates or after long gaps
            let timeSinceLastUpdate = Date().timeIntervalSince(lastUserLocationUpdate)
            if timeSinceLastUpdate > 300 { // 5 minutes
                requestCameraUpdate(reason: .userLocation, delay: 1.0)
            }
        }
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
            lastFriendLocationsUpdate = Date()
        }
    }
    
    private func handleZoomLevelChanged(_ zoomLevel: Double) {
        print("DEBUG: Zoom level changed to: \(zoomLevel)")
        
        // Auto-expand clusters at high zoom levels (without camera changes)
        if zoomLevel >= 16.0 {
            friendLocationGrouper.expandAllClusters()
        } else if zoomLevel < 12.0 {
            friendLocationGrouper.collapseAllClusters()
        }
    }
    
    private func setupPeriodicCleanup() {
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
    
    // MARK: - Enhanced Camera Control
    
    private func isSignificantLocationChange(_ newLocation: CLLocationCoordinate2D) -> Bool {
        guard let lastLocation = lastSignificantUserLocation else {
            return true // First location is always significant
        }
        
        let distance = lastLocation.distance(to: newLocation)
        return distance > significantLocationChangeThreshold
    }
    
    private func requestCameraUpdate(reason: CameraUpdateReason, delay: TimeInterval = 0.0) {
        // Don't update camera if user is interacting
        guard !isUserInteractingWithMap else {
            print("DEBUG: Camera update blocked - user is interacting")
            return
        }
        
        // Don't update too frequently
        let timeSinceLastUpdate = Date().timeIntervalSince(lastCameraUpdate)
        guard timeSinceLastUpdate > minimumCameraUpdateInterval else {
            print("DEBUG: Camera update blocked - too frequent (last: \(timeSinceLastUpdate)s ago)")
            return
        }
        
        print("DEBUG: Requesting camera update for reason: \(reason)")
        
        // Cancel any pending camera updates
        cameraUpdateDebounceTimer?.invalidate()
        
        cameraUpdateDebounceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            // Double-check user is not interacting
            guard !self.isUserInteractingWithMap else {
                print("DEBUG: Camera update cancelled - user started interacting")
                return
            }
            
            self.lastCameraUpdateReason = reason
            self.lastCameraUpdate = Date()
            self.shouldUpdateCamera = true
            
            print("DEBUG: Camera update triggered for reason: \(reason)")
        }
    }
    
    // MARK: - Public Camera Control Methods (Enhanced)
    
    func focusOnUserLocation() {
        guard let userLocation = userLocation else {
            print("DEBUG: No user location available to focus")
            return
        }
        
        print("DEBUG: Focus on user location requested")
        
        // Update camera options
        cameraOptions = CameraOptions(
            center: userLocation,
            zoom: 16.0,
            bearing: 0,
            pitch: 0
        )
        
        // Request camera update
        requestCameraUpdate(reason: .userInitiated)
    }
    
    func focusOnFriendLocation(friendId: String) {
        print("DEBUG: Focusing on friend location for friend ID: \(friendId)")
        
        guard let friendLocation = friendLocations[friendId] else {
            print("DEBUG: No location found for friend with ID: \(friendId)")
            return
        }
        
        let coordinate = friendLocation.toCoordinate()
        print("DEBUG: Friend location found: \(coordinate.latitude), \(coordinate.longitude)")
        
        // Update camera options
        cameraOptions = CameraOptions(
            center: coordinate,
            zoom: 15.0,
            bearing: 0,
            pitch: 0
        )
        
        // Request camera update
        requestCameraUpdate(reason: .friendLocation(friendId), delay: 0.5)
    }
    
    func focusOnCluster(clusterId: String, expanded: Bool = true) {
        let locationGroups = friendLocationGrouper.groupFriendLocations(friendLocations)
        
        guard let group = locationGroups.first(where: {
            $0.type == .cluster &&
            $0.friendIds.sorted().joined(separator: "_") == clusterId
        }) else {
            print("DEBUG: Could not find cluster with ID: \(clusterId)")
            return
        }
        
        print("DEBUG: Focusing on cluster: \(clusterId)")
        
        if expanded {
            _ = friendLocationGrouper.toggleClusterExpansion(clusterId: clusterId)
        }
        
        cameraOptions = CameraOptions(
            center: group.centerCoordinate,
            zoom: 15.5,
            bearing: 0,
            pitch: 0
        )
        
        requestCameraUpdate(reason: .clusterFocus(clusterId), delay: 0.3)
    }
    
    func toggleMapStyle() {
        print("DEBUG: Toggling map style from \(currentMapStyle.displayName)")
        currentMapStyle = currentMapStyle.nextStyle()
        print("DEBUG: Map style changed to \(currentMapStyle.displayName)")
    }
    
    func updateZoomLevel(_ zoomLevel: Double) {
        if abs(currentZoomLevel - zoomLevel) > 0.1 {
            currentZoomLevel = zoomLevel
        }
    }
    
    // MARK: - Smart Update Control
    
    func setUserInteracting(_ interacting: Bool) {
        isUserInteractingWithMap = interacting
        
        if interacting {
            // Cancel any pending camera updates when user starts interacting
            cameraUpdateDebounceTimer?.invalidate()
            shouldUpdateCamera = false
        }
    }
    
    func canUpdateCamera() -> Bool {
        return !isUserInteractingWithMap &&
               Date().timeIntervalSince(lastCameraUpdate) > minimumCameraUpdateInterval
    }
    
    func getLastCameraUpdateReason() -> CameraUpdateReason {
        return lastCameraUpdateReason
    }
    
    // MARK: - Location Tracking (same as before)
    
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
    
    func updateLocationInfo(for coordinate: CLLocationCoordinate2D) {
            reverseGeocodingService.reverseGeocode(coordinate: coordinate)
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
    
    // MARK: - Friends Monitoring with Combine (same as before)
    
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
    
    // MARK: - Include all remaining methods from original LocationViewModel
    // (Copy all the existing methods for friend observations, clustering, etc.)
    
    func startObservingFriendLocations(friendIds: [String]) {
        guard !friendIds.isEmpty else {
            print("DEBUG: No friends to observe locations for")
            return
        }
        
        print("DEBUG: Starting to observe locations for \(friendIds.count) friends: \(friendIds)")
        
        if locationObserversActive {
            firebaseService.stopObservingFriendLocations()
        }
        
        firebaseService.observeFriendLocations(userIds: friendIds) { [weak self] locations in
            guard let self = self else { return }
            
            let currentTime = Date().timeIntervalSince1970
            let expirationTime: TimeInterval = 72 * 60 * 60 // 72 hours
            
            let validLocations = locations.filter { _, location in
                (currentTime - location.timestamp) < expirationTime
            }
            
            print("DEBUG: Received \(validLocations.count) valid friend locations")
            
            Task { @MainActor in
                self.friendLocations = validLocations
            }
        }
        
        locationObserversActive = true
    }
    
    func startObservingFriendOnlineStatus(friendIds: [String]) {
        guard !friendIds.isEmpty else { return }
        
        print("DEBUG: Starting to observe online status for \(friendIds.count) friends")
        
        for friendId in friendIds {
            firebaseService.observeUserOnlineStatus(userId: friendId) { [weak self] isOnline in
                guard let self = self else { return }
                
                Task { @MainActor in
                    if let index = self.friends.firstIndex(where: { $0.id == friendId }) {
                        self.friends[index].isOnline = isOnline
                        
                        if !isOnline {
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
    
    // MARK: - Clustering Management (same as before)
    
    func getLocationGroups() -> [LocationGroup] {
        return friendLocationGrouper.groupFriendLocations(friendLocations)
    }
    
    func toggleClusterExpansion(clusterId: String) -> Bool {
        return friendLocationGrouper.toggleClusterExpansion(clusterId: clusterId)
    }
    
    func isClusterExpanded(clusterId: String) -> Bool {
        return friendLocationGrouper.isClusterExpanded(clusterId: clusterId)
    }
    
    // MARK: - Helper Methods (same as before)
    
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
            cameraUpdateDebounceTimer?.invalidate()
        }
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - LocationServiceDelegate (same as before)
extension LocationViewModel: LocationServiceDelegate {
    func locationService(_ service: LocationServiceProtocol, didUpdateLocation location: CLLocation) {
        userLocation = location.coordinate
        locationTrackingState = .tracking
        
        print("DEBUG: Updated user location to \(location.coordinate.latitude), \(location.coordinate.longitude)")
        
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

// MARK: - Combine Publishers (enhanced)
extension LocationViewModel {
    
    var locationTrackingStatePublisher: Published<LocationTrackingState>.Publisher {
        $locationTrackingState
    }
    
    var userLocationPublisher: AnyPublisher<CLLocationCoordinate2D?, Never> {
        $userLocation
            .removeDuplicates { lhs, rhs in
                guard let lhs = lhs, let rhs = rhs else {
                    return lhs == nil && rhs == nil
                }
                return abs(lhs.latitude - rhs.latitude) < 0.00001 &&
                       abs(lhs.longitude - rhs.longitude) < 0.00001
            }
            .eraseToAnyPublisher()
    }
    
    var friendLocationsPublisher: AnyPublisher<[String: UserLocation], Never> {
        $friendLocations
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    var friendsPublisher: AnyPublisher<[User], Never> {
        $friends
            .removeDuplicates { $0.map(\.id) == $1.map(\.id) }
            .eraseToAnyPublisher()
    }
    
    var mapStylePublisher: AnyPublisher<MapStyle, Never> {
        $currentMapStyle
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    var cameraOptionsPublisher: AnyPublisher<CameraOptions, Never> {
        $cameraOptions
            .removeDuplicates { lhs, rhs in
                return lhs.center?.latitude == rhs.center?.latitude &&
                       lhs.center?.longitude == rhs.center?.longitude &&
                       lhs.zoom == rhs.zoom
            }
            .eraseToAnyPublisher()
    }
    
    var zoomLevelPublisher: AnyPublisher<Double, Never> {
        $currentZoomLevel
            .removeDuplicates { abs($0 - $1) < 0.1 }
            .eraseToAnyPublisher()
    }
    
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
    
    // New publisher for camera update permissions
    var cameraUpdateAllowedPublisher: AnyPublisher<Bool, Never> {
        return Publishers.CombineLatest(
            $shouldUpdateCamera,
            Just(!isUserInteractingWithMap)
        )
        .map { shouldUpdate, userNotInteracting in
            return shouldUpdate && userNotInteracting
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }
}
