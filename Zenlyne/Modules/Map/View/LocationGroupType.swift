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
    
    // Original positions of friends
    var originalPositions: [String: CLLocationCoordinate2D] = [:]
    
    mutating func generateRelativePositions(radius: Double, friendLocations: [String: UserLocation] = [:]) {
        guard count > 1 else {
            // Single friend, just use center or original position
            if let friendId = friendIds.first {
                if let location = friendLocations[friendId] {
                    relativePositions[friendId] = location.toCoordinate()
                    originalPositions[friendId] = location.toCoordinate()
                } else {
                    relativePositions[friendId] = centerCoordinate
                    originalPositions[friendId] = centerCoordinate
                }
            }
            return
        }
        
        // Store original positions
        for friendId in friendIds {
            if let location = friendLocations[friendId] {
                originalPositions[friendId] = location.toCoordinate()
            } else {
                originalPositions[friendId] = centerCoordinate
            }
        }
        
        // Check if original positions are far enough apart
        let minDistance = radius * 1.5 // Minimum distance to consider positions separated
        var positionsAreSeparated = true
        
        if friendIds.count >= 2 {
            for i in 0..<friendIds.count {
                for j in (i+1)..<friendIds.count {
                    let pos1 = originalPositions[friendIds[i]] ?? centerCoordinate
                    let pos2 = originalPositions[friendIds[j]] ?? centerCoordinate
                    let distance = pos1.distance(to: pos2)
                    
                    if distance < minDistance {
                        positionsAreSeparated = false
                        break
                    }
                }
                if !positionsAreSeparated { break }
            }
        }
        
        if positionsAreSeparated {
            // Use original positions as they are far enough apart
            relativePositions = originalPositions
            print("DEBUG: Using original positions for cluster - positions are separated")
        } else {
            // Generate circular/fan arrangement around center
            let positions = calculateExpandedPositions(
                center: centerCoordinate,
                count: count,
                radius: radius
            )
            
            for (index, friendId) in friendIds.enumerated() {
                if index < positions.count {
                    relativePositions[friendId] = positions[index]
                }
            }
            
            print("DEBUG: Generated circular arrangement for cluster - positions were too close")
        }
    }
    
    private func calculateExpandedPositions(center: CLLocationCoordinate2D, count: Int, radius: Double) -> [CLLocationCoordinate2D] {
        guard count > 0 else { return [] }
        
        var positions: [CLLocationCoordinate2D] = []
        
        if count == 1 {
            positions.append(center)
            return positions
        }
        
        if count == 2 {
            // Side by side arrangement
            let lonFactor = cos(center.latitude * Double.pi / 180.0)
            let lonOffset = radius / (111111.0 * lonFactor)
            
            positions.append(CLLocationCoordinate2D(
                latitude: center.latitude,
                longitude: center.longitude - lonOffset
            ))
            positions.append(CLLocationCoordinate2D(
                latitude: center.latitude,
                longitude: center.longitude + lonOffset
            ))
        } else if count == 3 {
            // Triangle formation
            let lonFactor = cos(center.latitude * Double.pi / 180.0)
            let latOffset = radius / 111111.0
            let lonOffset = radius / (111111.0 * lonFactor)
            
            // Top
            positions.append(CLLocationCoordinate2D(
                latitude: center.latitude + latOffset * 0.7,
                longitude: center.longitude
            ))
            
            // Bottom left
            positions.append(CLLocationCoordinate2D(
                latitude: center.latitude - latOffset * 0.4,
                longitude: center.longitude - lonOffset * 0.7
            ))
            
            // Bottom right
            positions.append(CLLocationCoordinate2D(
                latitude: center.latitude - latOffset * 0.4,
                longitude: center.longitude + lonOffset * 0.7
            ))
        } else {
            // Circle formation for 4+ friends
            let angleStep = (2.0 * Double.pi) / Double(count)
            let startAngle = -Double.pi / 2 // Start from top
            
            for i in 0..<count {
                let angle = startAngle + Double(i) * angleStep
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
    
    // Get animation keyframes for smooth expansion
    func getExpansionKeyframes(progress: Double) -> [String: CLLocationCoordinate2D] {
        var keyframes: [String: CLLocationCoordinate2D] = [:]
        
        for friendId in friendIds {
            let startPos = centerCoordinate
            let endPos = relativePositions[friendId] ?? centerCoordinate
            
            // Smooth interpolation with easing
            let easedProgress = easeOutCubic(progress)
            
            let lat = startPos.latitude + (endPos.latitude - startPos.latitude) * easedProgress
            let lon = startPos.longitude + (endPos.longitude - startPos.longitude) * easedProgress
            
            keyframes[friendId] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        
        return keyframes
    }
    
    // Get animation keyframes for smooth contraction
    func getContractionKeyframes(progress: Double) -> [String: CLLocationCoordinate2D] {
        var keyframes: [String: CLLocationCoordinate2D] = [:]
        
        for friendId in friendIds {
            let startPos = relativePositions[friendId] ?? centerCoordinate
            let endPos = centerCoordinate
            
            // Smooth interpolation with easing
            let easedProgress = easeInCubic(progress)
            
            let lat = startPos.latitude + (endPos.latitude - startPos.latitude) * easedProgress
            let lon = startPos.longitude + (endPos.longitude - startPos.longitude) * easedProgress
            
            keyframes[friendId] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        
        return keyframes
    }
    
    private func easeOutCubic(_ t: Double) -> Double {
        return 1 - pow(1 - t, 3)
    }
    
    private func easeInCubic(_ t: Double) -> Double {
        return t * t * t
    }
}

// MARK: - Grouping Configuration
struct GroupingConfiguration {
    var clusterRadiusMeters: Double = 200.0
    var minFriendsForCluster: Int = 2
    var maxFriendsPerCluster: Int = 10
    var expansionRadius: Double = 35.0
    
    static let `default` = GroupingConfiguration()
    
    static let aggressive = GroupingConfiguration(
        clusterRadiusMeters: 500.0,
        minFriendsForCluster: 2,
        maxFriendsPerCluster: 15,
        expansionRadius: 50.0
    )
    
    static let precise = GroupingConfiguration(
        clusterRadiusMeters: 100.0,
        minFriendsForCluster: 3,
        maxFriendsPerCluster: 8,
        expansionRadius: 25.0
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
    private var currentFriendLocations: [String: UserLocation] = [:]
    
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
    
    // MARK: - Public Methods
    
    func updateZoomLevel(_ zoomLevel: Double) {
        currentZoomLevel = zoomLevel
        
        // Update configuration based on zoom level
        configuration = getConfigurationForZoomLevel(zoomLevel)
        
        print("DEBUG: FriendLocationGrouper zoom level updated to: \(zoomLevel)")
        print("DEBUG: Using cluster radius: \(configuration.clusterRadiusMeters)m, expansion radius: \(configuration.expansionRadius)m")
    }
    
    func groupFriendLocations(_ friendLocations: [String: UserLocation]) -> [LocationGroup] {
        print("DEBUG: Grouping \(friendLocations.count) friend locations at zoom level \(currentZoomLevel)")
        
        // Store current friend locations for expansion calculations
        currentFriendLocations = friendLocations
        
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
            
            // Regenerate relative positions for this cluster
            regenerateClusterPositions(clusterId: clusterId)
            
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
        
        // Regenerate positions for all clusters
        for clusterId in clusterIds {
            regenerateClusterPositions(clusterId: clusterId)
        }
    }
    
    func collapseAllClusters() {
        expandedClusterIds.removeAll()
        print("DEBUG: Collapsed all clusters")
    }
    
    private func regenerateClusterPositions(clusterId: String) {
        // Find the cluster and regenerate its relative positions
        if let index = currentGroups.firstIndex(where: {
            $0.type == .cluster &&
            $0.friendIds.sorted().joined(separator: "_") == clusterId
        }) {
            var group = currentGroups[index]
            group.generateRelativePositions(
                radius: configuration.expansionRadius,
                friendLocations: currentFriendLocations
            )
            currentGroups[index] = group
            
            print("DEBUG: Regenerated positions for cluster \(clusterId) with \(group.friendIds.count) friends")
        }
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
                expansionRadius: 60.0
            )
        case 8...10:
            return GroupingConfiguration(
                clusterRadiusMeters: 2000.0,
                minFriendsForCluster: 2,
                maxFriendsPerCluster: 15,
                expansionRadius: 50.0
            )
        case 10...12:
            return GroupingConfiguration(
                clusterRadiusMeters: 1000.0,
                minFriendsForCluster: 2,
                maxFriendsPerCluster: 12,
                expansionRadius: 45.0
            )
        case 12...14:
            return configuration // Use default
        case 14...16:
            return GroupingConfiguration(
                clusterRadiusMeters: 200.0,
                minFriendsForCluster: 2,
                maxFriendsPerCluster: 8,
                expansionRadius: 30.0
            )
        case 16...18:
            return GroupingConfiguration(
                clusterRadiusMeters: 100.0,
                minFriendsForCluster: 3,
                maxFriendsPerCluster: 6,
                expansionRadius: 25.0
            )
        default:
            return GroupingConfiguration(
                clusterRadiusMeters: 50.0,
                minFriendsForCluster: 3,
                maxFriendsPerCluster: 5,
                expansionRadius: 20.0
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
                group.generateRelativePositions(
                    radius: configuration.expansionRadius,
                    friendLocations: friendLocations
                )
                print("DEBUG: Created cluster with \(nearbyFriends.count) friends at \(centerCoordinate.latitude), \(centerCoordinate.longitude)")
            } else {
                group.generateRelativePositions(
                    radius: 0,
                    friendLocations: friendLocations
                )
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
}

// MARK: - Extensions

extension CLLocationCoordinate2D {
    func distance(to coordinate: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: self.latitude, longitude: self.longitude)
        let location2 = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location1.distance(from: location2)
    }
}
