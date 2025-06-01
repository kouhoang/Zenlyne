//
//  LocationGroupType.swift
//  Zenlyne
//
//  Created by kou on 2/6/25.
//


//
//  FriendLocationGrouper.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import Foundation
import CoreLocation
import Combine

// MARK: - Location Group Types
enum LocationGroupType {
    case single
    case cluster
}

// MARK: - Location Group Model
struct LocationGroup {
    let type: LocationGroupType
    let friendIds: [String]
    let centerCoordinate: CLLocationCoordinate2D
    let count: Int
    var relativePositions: [String: CLLocationCoordinate2D] = [:]
    
    mutating func generateRelativePositions(radius: Double) {
        guard count > 1 else {
            // Single friend, just use center
            if let friendId = friendIds.first {
                relativePositions[friendId] = centerCoordinate
            }
            return
        }
        
        let positions = calculateOffsetPositions(
            center: centerCoordinate,
            count: count,
            radius: radius
        )
        
        for (index, friendId) in friendIds.enumerated() {
            if index < positions.count {
                relativePositions[friendId] = positions[index]
            }
        }
    }
    
    private func calculateOffsetPositions(center: CLLocationCoordinate2D, count: Int, radius: Double) -> [CLLocationCoordinate2D] {
        guard count > 0 else { return [] }
        
        var positions: [CLLocationCoordinate2D] = []
        
        if count == 1 {
            positions.append(center)
            return positions
        }
        
        if count == 2 {
            let lonFactor = cos(center.latitude * Double.pi / 180.0)
            let lonOffset1 = -radius / (111111.0 * lonFactor)
            let lonOffset2 = radius / (111111.0 * lonFactor)
            
            positions.append(CLLocationCoordinate2D(
                latitude: center.latitude,
                longitude: center.longitude + lonOffset1
            ))
            positions.append(CLLocationCoordinate2D(
                latitude: center.latitude,
                longitude: center.longitude + lonOffset2
            ))
        } else if count == 3 {
            // Triangle formation for 3 friends
            let lonFactor = cos(center.latitude * Double.pi / 180.0)
            
            // Top
            positions.append(CLLocationCoordinate2D(
                latitude: center.latitude + radius / 111111.0,
                longitude: center.longitude
            ))
            
            // Bottom left
            positions.append(CLLocationCoordinate2D(
                latitude: center.latitude - radius / (2 * 111111.0),
                longitude: center.longitude - radius / (111111.0 * lonFactor)
            ))
            
            // Bottom right
            positions.append(CLLocationCoordinate2D(
                latitude: center.latitude - radius / (2 * 111111.0),
                longitude: center.longitude + radius / (111111.0 * lonFactor)
            ))
        } else {
            // Circle formation for 4+ friends
            let angleStep = (2.0 * Double.pi) / Double(count)
            
            for i in 0..<count {
                let angle = Double(i) * angleStep
                let latOffset = (radius * sin(angle)) / 111111.0
                let lonFactor = cos(center.latitude * Double.pi / 180.0)
                let lonOffset = (radius * cos(angle)) / (111111.0 * lonFactor)
                
                positions.append(CLLocationCoordinate2D(
                    latitude: center.latitude + latOffset,
                    longitude: center.longitude + lonOffset
                ))
            }
        }
        
        return positions
    }
}

// MARK: - Grouping Configuration
struct GroupingConfiguration {
    var clusterRadiusMeters: Double = 200.0
    var minFriendsForCluster: Int = 2
    var maxFriendsPerCluster: Int = 10
    var expansionRadius: Double = 30.0
    
    static let `default` = GroupingConfiguration()
    
    static let aggressive = GroupingConfiguration(
        clusterRadiusMeters: 500.0,
        minFriendsForCluster: 2,
        maxFriendsPerCluster: 15,
        expansionRadius: 40.0
    )
    
    static let precise = GroupingConfiguration(
        clusterRadiusMeters: 100.0,
        minFriendsForCluster: 3,
        maxFriendsPerCluster: 8,
        expansionRadius: 20.0
    )
}

// MARK: - Friend Location Grouper
class FriendLocationGrouper: ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var currentGroups: [LocationGroup] = []
    @Published var expandedClusterIds: Set<String> = []
    
    // MARK: - Private Properties
    private var currentZoomLevel: Double = 14.0
    private var configuration: GroupingConfiguration = .default
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Combine Publishers
    private let groupsSubject = CurrentValueSubject<[LocationGroup], Never>([])
    private let expandedClustersSubject = CurrentValueSubject<Set<String>, Never>(Set())
    
    var groupsPublisher: AnyPublisher<[LocationGroup], Never> {
        groupsSubject
            .removeDuplicates { lhs, rhs in
                return lhs.count == rhs.count &&
                       lhs.map { "\($0.friendIds.sorted().joined())_\($0.type)" } ==
                       rhs.map { "\($0.friendIds.sorted().joined())_\($0.type)" }
            }
            .eraseToAnyPublisher()
    }
    
    var expandedClustersPublisher: AnyPublisher<Set<String>, Never> {
        expandedClustersSubject
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    init(configuration: GroupingConfiguration = .default) {
        self.configuration = configuration
        setupCombineBindings()
    }
    
    private func setupCombineBindings() {
        // Sync published properties with subjects
        $currentGroups
            .sink { [weak self] groups in
                self?.groupsSubject.send(groups)
            }
            .store(in: &cancellables)
        
        $expandedClusterIds
            .sink { [weak self] expandedIds in
                self?.expandedClustersSubject.send(expandedIds)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods (Giữ nguyên interface)
    
    func updateZoomLevel(_ zoomLevel: Double) {
        currentZoomLevel = zoomLevel
        
        // Update configuration based on zoom level
        configuration = getConfigurationForZoomLevel(zoomLevel)
        
        print("DEBUG: FriendLocationGrouper zoom level updated to: \(zoomLevel)")
        print("DEBUG: Using cluster radius: \(configuration.clusterRadiusMeters)m")
    }
    
    func groupFriendLocations(_ friendLocations: [String: UserLocation]) -> [LocationGroup] {
        print("DEBUG: Grouping \(friendLocations.count) friend locations at zoom level \(currentZoomLevel)")
        
        let groups = performGrouping(friendLocations)
        
        // Update published property
        DispatchQueue.main.async {
            self.currentGroups = groups
        }
        
        return groups
    }
    
    func toggleClusterExpansion(clusterId: String) -> Bool {
        let wasExpanded = expandedClusterIds.contains(clusterId)
        
        if wasExpanded {
            expandedClusterIds.remove(clusterId)
            print("DEBUG: Collapsed cluster: \(clusterId)")
            return false
        } else {
            expandedClusterIds.insert(clusterId)
            print("DEBUG: Expanded cluster: \(clusterId)")
            return true
        }
    }
    
    func isClusterExpanded(clusterId: String) -> Bool {
        return expandedClusterIds.contains(clusterId)
    }
    
    func expandAllClusters() {
        let clusterIds = currentGroups
            .filter { $0.type == .cluster }
            .map { $0.friendIds.sorted().joined(separator: "_") }
        
        expandedClusterIds.formUnion(clusterIds)
        print("DEBUG: Expanded all clusters: \(clusterIds.count)")
    }
    
    func collapseAllClusters() {
        expandedClusterIds.removeAll()
        print("DEBUG: Collapsed all clusters")
    }
    
    // MARK: - Configuration Management
    
    func updateConfiguration(_ newConfiguration: GroupingConfiguration) {
        configuration = newConfiguration
        print("DEBUG: Updated grouping configuration")
    }
    
    func getConfigurationForZoomLevel(_ zoomLevel: Double) -> GroupingConfiguration {
        switch zoomLevel {
        case 0...8:
            return GroupingConfiguration(
                clusterRadiusMeters: 5000.0,
                minFriendsForCluster: 2,
                maxFriendsPerCluster: 20,
                expansionRadius: 50.0
            )
        case 8...10:
            return GroupingConfiguration(
                clusterRadiusMeters: 2000.0,
                minFriendsForCluster: 2,
                maxFriendsPerCluster: 15,
                expansionRadius: 40.0
            )
        case 10...12:
            return GroupingConfiguration(
                clusterRadiusMeters: 1000.0,
                minFriendsForCluster: 2,
                maxFriendsPerCluster: 12,
                expansionRadius: 35.0
            )
        case 12...14:
            return configuration // Use default
        case 14...16:
            return GroupingConfiguration(
                clusterRadiusMeters: 200.0,
                minFriendsForCluster: 2,
                maxFriendsPerCluster: 8,
                expansionRadius: 25.0
            )
        case 16...18:
            return GroupingConfiguration(
                clusterRadiusMeters: 100.0,
                minFriendsForCluster: 3,
                maxFriendsPerCluster: 6,
                expansionRadius: 20.0
            )
        default:
            return GroupingConfiguration(
                clusterRadiusMeters: 50.0,
                minFriendsForCluster: 3,
                maxFriendsPerCluster: 5,
                expansionRadius: 15.0
            )
        }
    }
    
    // MARK: - Private Grouping Logic
    
    private func performGrouping(_ friendLocations: [String: UserLocation]) -> [LocationGroup] {
        var groups: [LocationGroup] = []
        var processedFriends: Set<String> = []
        
        let clusterRadius = configuration.clusterRadiusMeters
        print("DEBUG: Using cluster radius: \(clusterRadius)m")
        
        for (friendId, location) in friendLocations {
            if processedFriends.contains(friendId) {
                continue
            }
            
            let coordinate = location.toCoordinate()
            var nearbyFriends: [String] = [friendId]
            var totalLat = coordinate.latitude
            var totalLon = coordinate.longitude
            
            processedFriends.insert(friendId)
            
            // Find nearby friends within cluster radius
            for (otherId, otherLocation) in friendLocations {
                if processedFriends.contains(otherId) {
                    continue
                }
                
                let otherCoordinate = otherLocation.toCoordinate()
                let distance = coordinate.distance(to: otherCoordinate)
                
                if distance <= clusterRadius && nearbyFriends.count < configuration.maxFriendsPerCluster {
                    nearbyFriends.append(otherId)
                    processedFriends.insert(otherId)
                    totalLat += otherCoordinate.latitude
                    totalLon += otherCoordinate.longitude
                    
                    print("DEBUG: Friend \(otherId) is \(distance)m from \(friendId), adding to cluster")
                }
            }
            
            // Calculate center coordinate for the group
            let centerCoordinate = CLLocationCoordinate2D(
                latitude: totalLat / Double(nearbyFriends.count),
                longitude: totalLon / Double(nearbyFriends.count)
            )
            
            let shouldCluster = nearbyFriends.count >= configuration.minFriendsForCluster
            let groupType: LocationGroupType = shouldCluster ? .cluster : .single
            
            var group = LocationGroup(
                type: groupType,
                friendIds: nearbyFriends,
                centerCoordinate: centerCoordinate,
                count: nearbyFriends.count
            )
            
            // Generate relative positions for cluster members
            if groupType == .cluster {
                group.generateRelativePositions(radius: configuration.expansionRadius)
                print("DEBUG: Created cluster with \(nearbyFriends.count) friends at \(centerCoordinate.latitude), \(centerCoordinate.longitude)")
            } else {
                group.generateRelativePositions(radius: 0) // Single friend at center
                print("DEBUG: Created single friend group for \(friendId)")
            }
            
            groups.append(group)
        }
        
        print("DEBUG: Created \(groups.count) location groups")
        return groups
    }
    
    // MARK: - Utility Methods
    
    func getClusterById(_ clusterId: String) -> LocationGroup? {
        return currentGroups.first { group in
            guard group.type == .cluster else { return false }
            let groupClusterId = group.friendIds.sorted().joined(separator: "_")
            return groupClusterId == clusterId
        }
    }
    
    func getFriendsInCluster(_ clusterId: String) -> [String] {
        return getClusterById(clusterId)?.friendIds ?? []
    }
    
    func shouldAutoExpand() -> Bool {
        return currentZoomLevel >= 16.0
    }
    
    func shouldAutoCollapse() -> Bool {
        return currentZoomLevel <= 12.0
    }
    
    // MARK: - Debugging Methods
    
    func debugPrintGroups(_ groups: [LocationGroup]) {
        print("DEBUG: === Location Groups Debug ===")
        for (index, group) in groups.enumerated() {
            print("DEBUG: Group \(index + 1):")
            print("  Type: \(group.type)")
            print("  Count: \(group.count)")
            print("  Center: \(group.centerCoordinate.latitude), \(group.centerCoordinate.longitude)")
            print("  Friends: \(group.friendIds.joined(separator: ", "))")
            
            if group.type == .cluster {
                let clusterId = group.friendIds.sorted().joined(separator: "_")
                print("  Cluster ID: \(clusterId)")
                print("  Expanded: \(isClusterExpanded(clusterId: clusterId))")
                
                if !group.relativePositions.isEmpty {
                    print("  Relative Positions:")
                    for (friendId, position) in group.relativePositions {
                        print("    \(friendId): \(position.latitude), \(position.longitude)")
                    }
                }
            }
        }
        print("DEBUG: === End Groups Debug ===")
    }
    
    func printCurrentState() {
        print("DEBUG: === FriendLocationGrouper State ===")
        print("  Zoom Level: \(currentZoomLevel)")
        print("  Cluster Radius: \(configuration.clusterRadiusMeters)m")
        print("  Current Groups: \(currentGroups.count)")
        print("  Expanded Clusters: \(expandedClusterIds.count)")
        print("================================")
    }
}

// MARK: - Extensions

extension CLLocationCoordinate2D {
    func distance(to coordinate: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: self.latitude, longitude: self.longitude)
        let location2 = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location1.distance(from: location2)
    }
}

// MARK: - Convenience Extensions for Combine

extension FriendLocationGrouper {
    
    /// Publisher that emits when clustering should be updated based on zoom level changes
    func clusteringUpdatePublisher(zoomLevelPublisher: AnyPublisher<Double, Never>) -> AnyPublisher<Void, Never> {
        zoomLevelPublisher
            .removeDuplicates { abs($0 - $1) < 0.5 } // Only update on significant zoom changes
            .map { [weak self] zoomLevel in
                self?.updateZoomLevel(zoomLevel)
                return ()
            }
            .eraseToAnyPublisher()
    }
    
    /// Publisher that emits cluster expansion recommendations based on zoom level
    func autoExpansionPublisher(zoomLevelPublisher: AnyPublisher<Double, Never>) -> AnyPublisher<Bool, Never> {
        zoomLevelPublisher
            .map { zoomLevel in
                return zoomLevel >= 16.0 // Auto-expand at high zoom levels
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}