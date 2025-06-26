//
//  FriendLocationGrouper.swift
//  Zenlyne
//
//  Created by kou on 4/6/25.
//

import Foundation
import CoreLocation
import Combine

// MARK: - Location Group Types
enum LocationGroupType {
    case single
    case cluster
    case sameLocation
}

// MARK: - Location Group Model
struct LocationGroup {
    let type: LocationGroupType
    let friendIds: [String]
    let centerCoordinate: CLLocationCoordinate2D
    let count: Int
    var relativePositions: [String: CLLocationCoordinate2D] = [:]
    var originalPositions: [String: CLLocationCoordinate2D] = [:]
    
    // For same location groups
    var representativeUserId: String?
    var sameLocationRadius: Double = 5.0 // meters
    
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
        
        switch type {
        case .sameLocation:
            // For same location groups, all users are at the same point
            // Set representative user (first online user or first user)
            if representativeUserId == nil {
                representativeUserId = friendIds.first
            }
            
            // All positions are the same
            for friendId in friendIds {
                relativePositions[friendId] = centerCoordinate
            }
            
            print("DEBUG: Same location group - all users at \(centerCoordinate)")
            
        case .cluster:
            // Check if original positions are far enough apart for expansion
            let minDistance = radius * 1.5
            var positionsAreSeparated = checkPositionsSeparation(minDistance: minDistance)
            
            if positionsAreSeparated && count <= 4 {
                // Use original positions as they are well separated
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
                
                print("DEBUG: Generated circular arrangement for cluster")
            }
            
        case .single:
            // Single user, position at center
            if let friendId = friendIds.first {
                relativePositions[friendId] = centerCoordinate
            }
        }
    }
    
    private func checkPositionsSeparation(minDistance: Double) -> Bool {
        guard friendIds.count >= 2 else { return true }
        
        for i in 0..<friendIds.count {
            for j in (i+1)..<friendIds.count {
                let pos1 = originalPositions[friendIds[i]] ?? centerCoordinate
                let pos2 = originalPositions[friendIds[j]] ?? centerCoordinate
                let distance = pos1.distance(to: pos2)
                
                if distance < minDistance {
                    return false
                }
            }
        }
        
        return true
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
            
            positions.append(CLLocationCoordinate2D(
                latitude: center.latitude + latOffset * 0.7,
                longitude: center.longitude
            ))
            positions.append(CLLocationCoordinate2D(
                latitude: center.latitude - latOffset * 0.4,
                longitude: center.longitude - lonOffset * 0.7
            ))
            positions.append(CLLocationCoordinate2D(
                latitude: center.latitude - latOffset * 0.4,
                longitude: center.longitude + lonOffset * 0.7
            ))
        } else {
            // Circle formation for 4+ friends
            let angleStep = (2.0 * Double.pi) / Double(count)
            let startAngle = -Double.pi / 2
            
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
    
    // New properties for same-location handling
    var sameLocationThresholdMeters: Double = 10.0 // Consider same location if within 10m
    var maxSeparatedMarkers: Int = 4 // Max individual markers before clustering
    var minDistanceForSeparation: Double = 30.0 // Min distance to show as separate markers
    
    static let `default` = GroupingConfiguration()
    
    static let aggressive = GroupingConfiguration(
        clusterRadiusMeters: 500.0,
        minFriendsForCluster: 2,
        maxFriendsPerCluster: 15,
        expansionRadius: 50.0,
        sameLocationThresholdMeters: 15.0,
        maxSeparatedMarkers: 6
    )
    
    static let precise = GroupingConfiguration(
        clusterRadiusMeters: 100.0,
        minFriendsForCluster: 3,
        maxFriendsPerCluster: 8,
        expansionRadius: 25.0,
        sameLocationThresholdMeters: 5.0,
        maxSeparatedMarkers: 3
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
        configuration = getConfigurationForZoomLevel(zoomLevel)
        
        print("DEBUG: FriendLocationGrouper zoom level updated to: \(zoomLevel)")
    }
    
    func groupFriendLocations(_ friendLocations: [String: UserLocation]) -> [LocationGroup] {
        print("DEBUG: Smart grouping \(friendLocations.count) friend locations at zoom level \(currentZoomLevel)")
        
        currentFriendLocations = friendLocations
        let groups = performSmartGrouping(friendLocations)
        
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
        
        for clusterId in clusterIds {
            regenerateClusterPositions(clusterId: clusterId)
        }
    }
    
    func collapseAllClusters() {
        expandedClusterIds.removeAll()
        print("DEBUG: Collapsed all clusters")
    }
    
    private func regenerateClusterPositions(clusterId: String) {
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
        }
    }
    
    // MARK: - Smart Grouping Logic
    
    private func performSmartGrouping(_ friendLocations: [String: UserLocation]) -> [LocationGroup] {
        var groups: [LocationGroup] = []
        var processedFriends: Set<String> = []
        
        print("DEBUG: Starting smart grouping with \(friendLocations.count) friends")
        
        // Step 1: Find same-location groups first
        let sameLocationGroups = findSameLocationGroups(friendLocations, processedFriends: &processedFriends)
        groups.append(contentsOf: sameLocationGroups)
        
        // Step 2: Process remaining friends for clustering or individual markers
        let remainingFriends = friendLocations.filter { !processedFriends.contains($0.key) }
        let clusteredGroups = processRemainingFriends(remainingFriends, processedFriends: &processedFriends)
        groups.append(contentsOf: clusteredGroups)
        
        print("DEBUG: Created \(groups.count) total groups")
        return groups
    }
    
    private func findSameLocationGroups(_ friendLocations: [String: UserLocation], processedFriends: inout Set<String>) -> [LocationGroup] {
        var sameLocationGroups: [LocationGroup] = []
        let threshold = configuration.sameLocationThresholdMeters
        
        for (friendId, location) in friendLocations {
            if processedFriends.contains(friendId) { continue }
            
            let coordinate = location.toCoordinate()
            var sameLocationFriends: [String] = [friendId]
            var totalLat = coordinate.latitude
            var totalLon = coordinate.longitude
            
            processedFriends.insert(friendId)
            
            // Find friends at the same location
            for (otherId, otherLocation) in friendLocations {
                if processedFriends.contains(otherId) { continue }
                
                let otherCoordinate = otherLocation.toCoordinate()
                let distance = coordinate.distance(to: otherCoordinate)
                
                if distance <= threshold {
                    sameLocationFriends.append(otherId)
                    processedFriends.insert(otherId)
                    totalLat += otherCoordinate.latitude
                    totalLon += otherCoordinate.longitude
                    
                    print("DEBUG: Found friend \(otherId) at same location as \(friendId) (distance: \(distance)m)")
                }
            }
            
            let centerCoordinate = CLLocationCoordinate2D(
                latitude: totalLat / Double(sameLocationFriends.count),
                longitude: totalLon / Double(sameLocationFriends.count)
            )
            
            if sameLocationFriends.count > 1 {
                // Create same-location group
                var group = LocationGroup(
                    type: .sameLocation,
                    friendIds: sameLocationFriends,
                    centerCoordinate: centerCoordinate,
                    count: sameLocationFriends.count
                )
                
                group.generateRelativePositions(radius: 0, friendLocations: friendLocations)
                sameLocationGroups.append(group)
                
                print("DEBUG: Created same-location group with \(sameLocationFriends.count) friends")
            } else {
                // Single friend, will be processed in step 2
                processedFriends.remove(friendId)
            }
        }
        
        return sameLocationGroups
    }
    
    private func processRemainingFriends(_ remainingFriends: [String: UserLocation], processedFriends: inout Set<String>) -> [LocationGroup] {
        var groups: [LocationGroup] = []
        let clusterRadius = configuration.clusterRadiusMeters
        let maxSeparated = configuration.maxSeparatedMarkers
        let minSeparationDistance = configuration.minDistanceForSeparation
        
        for (friendId, location) in remainingFriends {
            if processedFriends.contains(friendId) { continue }
            
            let coordinate = location.toCoordinate()
            var nearbyFriends: [String] = [friendId]
            var totalLat = coordinate.latitude
            var totalLon = coordinate.longitude
            
            processedFriends.insert(friendId)
            
            // Find nearby friends within cluster radius
            for (otherId, otherLocation) in remainingFriends {
                if processedFriends.contains(otherId) { continue }
                
                let otherCoordinate = otherLocation.toCoordinate()
                let distance = coordinate.distance(to: otherCoordinate)
                
                if distance <= clusterRadius && nearbyFriends.count < configuration.maxFriendsPerCluster {
                    nearbyFriends.append(otherId)
                    processedFriends.insert(otherId)
                    totalLat += otherCoordinate.latitude
                    totalLon += otherCoordinate.longitude
                }
            }
            
            let centerCoordinate = CLLocationCoordinate2D(
                latitude: totalLat / Double(nearbyFriends.count),
                longitude: totalLon / Double(nearbyFriends.count)
            )
            
            // Decide whether to cluster or separate
            let shouldCluster = nearbyFriends.count >= configuration.minFriendsForCluster
            let shouldSeparate = nearbyFriends.count <= maxSeparated && arePositionsWellSeparated(nearbyFriends, remainingFriends, minSeparationDistance)
            
            if shouldSeparate && !shouldCluster {
                // Create individual markers for each friend
                for friendId in nearbyFriends {
                    if let friendLocation = remainingFriends[friendId] {
                        let group = LocationGroup(
                            type: .single,
                            friendIds: [friendId],
                            centerCoordinate: friendLocation.toCoordinate(),
                            count: 1
                        )
                        groups.append(group)
                        print("DEBUG: Created individual marker for \(friendId)")
                    }
                }
            } else if shouldCluster {
                // Create cluster
                var group = LocationGroup(
                    type: .cluster,
                    friendIds: nearbyFriends,
                    centerCoordinate: centerCoordinate,
                    count: nearbyFriends.count
                )
                
                group.generateRelativePositions(
                    radius: configuration.expansionRadius,
                    friendLocations: Dictionary(uniqueKeysWithValues: remainingFriends.map { ($0.key, $0.value) })
                )
                groups.append(group)
                
                print("DEBUG: Created cluster with \(nearbyFriends.count) friends")
            } else {
                // Single friend
                let group = LocationGroup(
                    type: .single,
                    friendIds: [friendId],
                    centerCoordinate: coordinate,
                    count: 1
                )
                groups.append(group)
            }
        }
        
        return groups
    }
    
    private func arePositionsWellSeparated(_ friendIds: [String], _ friendLocations: [String: UserLocation], _ minDistance: Double) -> Bool {
        guard friendIds.count > 1 else { return true }
        
        for i in 0..<friendIds.count {
            for j in (i+1)..<friendIds.count {
                guard let location1 = friendLocations[friendIds[i]],
                      let location2 = friendLocations[friendIds[j]] else { continue }
                
                let coord1 = location1.toCoordinate()
                let coord2 = location2.toCoordinate()
                let distance = coord1.distance(to: coord2)
                
                if distance < minDistance {
                    return false
                }
            }
        }
        
        return true
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
                expansionRadius: 60.0,
                sameLocationThresholdMeters: 50.0,
                maxSeparatedMarkers: 8
            )
        case 8...10:
            return GroupingConfiguration(
                clusterRadiusMeters: 2000.0,
                minFriendsForCluster: 2,
                maxFriendsPerCluster: 15,
                expansionRadius: 50.0,
                sameLocationThresholdMeters: 30.0,
                maxSeparatedMarkers: 6
            )
        case 10...12:
            return GroupingConfiguration(
                clusterRadiusMeters: 1000.0,
                minFriendsForCluster: 2,
                maxFriendsPerCluster: 12,
                expansionRadius: 45.0,
                sameLocationThresholdMeters: 20.0,
                maxSeparatedMarkers: 5
            )
        case 12...14:
            return configuration
        case 14...16:
            return GroupingConfiguration(
                clusterRadiusMeters: 200.0,
                minFriendsForCluster: 2,
                maxFriendsPerCluster: 8,
                expansionRadius: 30.0,
                sameLocationThresholdMeters: 10.0,
                maxSeparatedMarkers: 4
            )
        case 16...18:
            return GroupingConfiguration(
                clusterRadiusMeters: 100.0,
                minFriendsForCluster: 3,
                maxFriendsPerCluster: 6,
                expansionRadius: 25.0,
                sameLocationThresholdMeters: 5.0,
                maxSeparatedMarkers: 3
            )
        default:
            return GroupingConfiguration(
                clusterRadiusMeters: 50.0,
                minFriendsForCluster: 3,
                maxFriendsPerCluster: 5,
                expansionRadius: 20.0,
                sameLocationThresholdMeters: 3.0,
                maxSeparatedMarkers: 2
            )
        }
    }
    
    // MARK: - Utility Methods
    
    func getClusterById(_ clusterId: String) -> LocationGroup? {
        return currentGroups.first { group in
            guard group.type == .cluster else { return false }
            let groupClusterId = group.friendIds.sorted().joined(separator: "_")
            return groupClusterId == clusterId
        }
    }
    
    func getSameLocationGroupById(_ groupId: String) -> LocationGroup? {
        return currentGroups.first { group in
            guard group.type == .sameLocation else { return false }
            let groupGroupId = group.friendIds.sorted().joined(separator: "_")
            return groupGroupId == groupId
        }
    }
    
    func getFriendsInCluster(_ clusterId: String) -> [String] {
        return getClusterById(clusterId)?.friendIds ?? []
    }
    
    func getFriendsInSameLocation(_ groupId: String) -> [String] {
        return getSameLocationGroupById(groupId)?.friendIds ?? []
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
