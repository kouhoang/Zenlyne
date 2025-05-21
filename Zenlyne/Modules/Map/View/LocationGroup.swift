//
//  LocationGroup.swift
//  Zenlyne
//
//  Created by admin on 20/5/25.
//

import Foundation
import CoreLocation
import MapboxMaps

// Enhanced structure to store grouped locations with relative positions
struct LocationGroup {
    enum GroupType {
        case single
        case cluster     // Multiple friends, show as cluster
    }
    
    let centerCoordinate: CLLocationCoordinate2D
    let friendIds: [String]
    let type: GroupType
    
    // New property: Store relative positions for friends in this cluster
    // Key: friendId, Value: Relative position within cluster
    var relativePositions: [String: CLLocationCoordinate2D] = [:]
    
    var count: Int {
        return friendIds.count
    }
    
    // Generate well-distributed relative positions for friends in this cluster
    mutating func generateRelativePositions(radius: Double = 20.0) {
        // Clear existing positions
        relativePositions = [:]
        
        // If only one friend, position at center
        if friendIds.count == 1, let friendId = friendIds.first {
            relativePositions[friendId] = centerCoordinate
            return
        }
        
        // For multiple friends, create a nice arrangement
        let positions = calculateOffsetPositions(center: centerCoordinate, count: friendIds.count, radius: radius)
        
        // Assign positions to friends
        for (index, friendId) in friendIds.enumerated() {
            if index < positions.count {
                relativePositions[friendId] = positions[index]
            } else {
                // Fallback to center if we somehow have more friends than positions
                relativePositions[friendId] = centerCoordinate
            }
        }
    }
    
    // Calculate evenly distributed positions around center
    private func calculateOffsetPositions(center: CLLocationCoordinate2D, count: Int, radius: Double) -> [CLLocationCoordinate2D] {
        guard count > 0 else { return [] }
        
        var positions: [CLLocationCoordinate2D] = []
        
        // If only one friend, return the center
        if count == 1 {
            positions.append(center)
            return positions
        }
        
        // For 2-3 friends, create a more pleasing pattern
        if count == 2 {
            // For 2 friends, place them horizontally next to each other
            let latOffset = 0.0
            let lonFactor = cos(center.latitude * Double.pi / 180.0)
            
            // Friend 1 (left)
            let lonOffset1 = -radius / (111111.0 * lonFactor)
            positions.append(CLLocationCoordinate2D(
                latitude: center.latitude,
                longitude: center.longitude + lonOffset1
            ))
            
            // Friend 2 (right)
            let lonOffset2 = radius / (111111.0 * lonFactor)
            positions.append(CLLocationCoordinate2D(
                latitude: center.latitude,
                longitude: center.longitude + lonOffset2
            ))
        } else if count == 3 {
            // For 3 friends, place them in a triangle formation
            let lonFactor = cos(center.latitude * Double.pi / 180.0)
            
            // Friend 1 (top)
            let latOffset1 = radius / 111111.0
            positions.append(CLLocationCoordinate2D(
                latitude: center.latitude + latOffset1,
                longitude: center.longitude
            ))
            
            // Friend 2 (bottom left)
            let latOffset2 = -radius / (2 * 111111.0)
            let lonOffset2 = -radius / (111111.0 * lonFactor)
            positions.append(CLLocationCoordinate2D(
                latitude: center.latitude + latOffset2,
                longitude: center.longitude + lonOffset2
            ))
            
            // Friend 3 (bottom right)
            let latOffset3 = -radius / (2 * 111111.0)
            let lonOffset3 = radius / (111111.0 * lonFactor)
            positions.append(CLLocationCoordinate2D(
                latitude: center.latitude + latOffset3,
                longitude: center.longitude + lonOffset3
            ))
        } else {
            // For more than 3 friends, calculate positions in a circle
            let angleStep = (2.0 * Double.pi) / Double(count)
            
            for i in 0..<count {
                let angle = Double(i) * angleStep
                
                // Convert meters to coordinate space
                // ~111,111 meters per degree of latitude
                let latOffset = (radius * sin(angle)) / 111111.0
                
                // Longitude degrees vary based on latitude
                let lonFactor = cos(center.latitude * Double.pi / 180.0)
                let lonOffset = (radius * cos(angle)) / (111111.0 * lonFactor)
                
                let position = CLLocationCoordinate2D(
                    latitude: center.latitude + latOffset,
                    longitude: center.longitude + lonOffset
                )
                
                positions.append(position)
            }
        }
        
        return positions
    }
}

// Enhanced class for grouping friend locations with expanded clusters support
class FriendLocationGrouper {
    // Distance threshold in meters (5 meters = very close proximity)
    private let proximityThreshold: Double = 5.0
    
    // Minimum friends required to form a cluster (at least 2)
    private let minFriendsForCluster: Int = 2
    
    // Track expanded clusters by ID
    var expandedClusterIds: Set<String> = []
    
    // Current zoom level for dynamic adjustments
    private var currentZoomLevel: Double = 14.0
    
    // Method to set current zoom level
    func updateZoomLevel(_ zoomLevel: Double) {
        currentZoomLevel = zoomLevel
    }
    
    // Toggle expansion state for a specific cluster
    func toggleClusterExpansion(clusterId: String) -> Bool {
        if expandedClusterIds.contains(clusterId) {
            expandedClusterIds.remove(clusterId)
            return false // Now collapsed
        } else {
            expandedClusterIds.insert(clusterId)
            return true // Now expanded
        }
    }
    
    // Check if a cluster is expanded
    func isClusterExpanded(clusterId: String) -> Bool {
        return expandedClusterIds.contains(clusterId)
    }
    
    // Group friend locations based on proximity
    func groupFriendLocations(_ friendLocations: [String: UserLocation]) -> [LocationGroup] {
        // Early exit if no locations
        if friendLocations.isEmpty {
            return []
        }
        
        // Convert to array for easier processing
        var locations: [(friendId: String, location: CLLocationCoordinate2D)] = []
        for (friendId, userLocation) in friendLocations {
            locations.append((friendId, userLocation.toCoordinate()))
        }
        
        // Temporary storage for processed locations
        var processedLocations = Set<String>()
        var groups: [LocationGroup] = []
        
        // Process each location
        for (currentFriendId, currentLocation) in locations {
            // Skip if already processed
            if processedLocations.contains(currentFriendId) {
                continue
            }
            
            // Mark as processed
            processedLocations.insert(currentFriendId)
            
            // Find nearby friends
            var nearbyFriendIds: [String] = [currentFriendId]
            
            for (otherFriendId, otherLocation) in locations {
                // Skip if the same friend or already processed
                if otherFriendId == currentFriendId || processedLocations.contains(otherFriendId) {
                    continue
                }
                
                // Calculate distance between locations
                let currentCLLocation = CLLocation(latitude: currentLocation.latitude, longitude: currentLocation.longitude)
                let otherCLLocation = CLLocation(latitude: otherLocation.latitude, longitude: otherLocation.longitude)
                
                let distanceInMeters = currentCLLocation.distance(from: otherCLLocation)
                
                // If within threshold, add to nearby friends
                if distanceInMeters <= adjustProximityThreshold(for: currentZoomLevel) {
                    nearbyFriendIds.append(otherFriendId)
                    processedLocations.insert(otherFriendId)
                }
            }
            
            // Determine group type based on number of friends
            let groupType: LocationGroup.GroupType
            if nearbyFriendIds.count < minFriendsForCluster {
                groupType = .single
            } else {
                groupType = .cluster
            }
            
            // Create group with the center as the average of all locations
            let centerCoordinate = calculateCenterCoordinate(for: nearbyFriendIds, in: friendLocations)
            
            var group = LocationGroup(
                centerCoordinate: centerCoordinate,
                friendIds: nearbyFriendIds,
                type: groupType
            )
            
            // Generate relative positions for friends in this cluster
            group.generateRelativePositions(radius: 20.0)
            
            groups.append(group)
        }
        
        return groups
    }
    
    // Calculate center coordinate for a group of friends
    private func calculateCenterCoordinate(for friendIds: [String], in friendLocations: [String: UserLocation]) -> CLLocationCoordinate2D {
        var totalLat: Double = 0
        var totalLon: Double = 0
        var count: Double = 0
        
        for friendId in friendIds {
            if let location = friendLocations[friendId] {
                totalLat += location.latitude
                totalLon += location.longitude
                count += 1
            }
        }
        
        if count > 0 {
            return CLLocationCoordinate2D(
                latitude: totalLat / count,
                longitude: totalLon / count
            )
        } else {
            // Fallback if no valid locations (shouldn't happen)
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
    }
    
    // Adjust proximity threshold based on zoom level
    func adjustProximityThreshold(for zoomLevel: Double) -> Double {
        // At higher zoom levels (closer), we want a smaller threshold
        // At zoom 20 (very close), use 2 meters
        // At zoom 15 (city level), use the normal threshold
        // At zoom 10 (region level), use a larger threshold
        
        if zoomLevel >= 18 {
            // Very close zoom
            return max(2.0, proximityThreshold * 0.4)
        } else if zoomLevel >= 15 {
            // City level zoom
            return proximityThreshold
        } else {
            // Further zoomed out
            // Increase threshold as zoom decreases
            let factor = max(1.0, (15 - zoomLevel) * 0.5)
            return proximityThreshold * factor
        }
    }
}
