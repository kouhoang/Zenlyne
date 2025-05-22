//
//  FriendLocationGrouper.swift
//  Zenlyne
//

import Foundation
import CoreLocation

enum LocationGroupType {
    case single
    case cluster
}

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

class FriendLocationGrouper {
    private var currentZoomLevel: Double = 14.0
    var expandedClusterIds: Set<String> = []
    
    // MARK: - Public Methods
    
    func updateZoomLevel(_ zoomLevel: Double) {
        currentZoomLevel = zoomLevel
        print("DEBUG: FriendLocationGrouper zoom level updated to: \(zoomLevel)")
    }
    
    func groupFriendLocations(_ friendLocations: [String: UserLocation]) -> [LocationGroup] {
        print("DEBUG: Grouping \(friendLocations.count) friend locations at zoom level \(currentZoomLevel)")
        
        var groups: [LocationGroup] = []
        var processedFriends: Set<String> = []
        
        let clusterRadius = getClusterRadius()
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
                
                if distance <= clusterRadius {
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
            
            let groupType: LocationGroupType = nearbyFriends.count > 1 ? .cluster : .single
            var group = LocationGroup(
                type: groupType,
                friendIds: nearbyFriends,
                centerCoordinate: centerCoordinate,
                count: nearbyFriends.count
            )
            
            // Generate relative positions for cluster members
            if groupType == .cluster {
                group.generateRelativePositions(radius: min(clusterRadius / 2, 30.0))
                print("DEBUG: Created cluster with \(nearbyFriends.count) friends at \(centerCoordinate.latitude), \(centerCoordinate.longitude)")
            } else {
                print("DEBUG: Created single friend group for \(friendId)")
            }
            
            groups.append(group)
        }
        
        print("DEBUG: Created \(groups.count) location groups")
        return groups
    }
    
    func toggleClusterExpansion(clusterId: String) -> Bool {
        if expandedClusterIds.contains(clusterId) {
            expandedClusterIds.remove(clusterId)
            print("DEBUG: Collapsed cluster: \(clusterId)")
            return false // Now collapsed
        } else {
            expandedClusterIds.insert(clusterId)
            print("DEBUG: Expanded cluster: \(clusterId)")
            return true // Now expanded
        }
    }
    
    func isClusterExpanded(clusterId: String) -> Bool {
        return expandedClusterIds.contains(clusterId)
    }
    
    func expandAllClusters() {
        // This could be called when zooming in
        print("DEBUG: Expanding all clusters")
    }
    
    func collapseAllClusters() {
        expandedClusterIds.removeAll()
        print("DEBUG: Collapsed all clusters")
    }
    
    // MARK: - Private Methods
    
    private func getClusterRadius() -> Double {
        // Adjust cluster radius based on zoom level
        // Higher zoom = smaller radius (more precise clustering)
        // Lower zoom = larger radius (more aggressive clustering)
        
        switch currentZoomLevel {
        case 0...8:
            return 5000.0 // 5km - very aggressive clustering for world/country view
        case 8...10:
            return 2000.0 // 2km - city level clustering
        case 10...12:
            return 1000.0 // 1km - district level clustering
        case 12...14:
            return 500.0  // 500m - neighborhood level clustering
        case 14...16:
            return 200.0  // 200m - street level clustering
        case 16...18:
            return 100.0  // 100m - block level clustering
        default:
            return 50.0   // 50m - very precise clustering for high zoom
        }
    }
    
    private func shouldAutoExpand() -> Bool {
        // Auto-expand clusters at high zoom levels
        return currentZoomLevel >= 16.0
    }
    
    private func shouldAutoCollapse() -> Bool {
        // Auto-collapse clusters at low zoom levels
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
}

// MARK: - Extensions

// Extension to calculate distance between coordinates
extension CLLocationCoordinate2D {
    func distance(to coordinate: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: self.latitude, longitude: self.longitude)
        let location2 = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location1.distance(from: location2)
    }
}
