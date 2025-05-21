//
//  LocationGroup.swift
//  Zenlyne
//
//  Created by admin on 20/5/25.
//


//
//  LocationGroup.swift
//  Zenlyne
//
//  Created by admin on 20/5/25.
//


import Foundation
import CoreLocation
import MapboxMaps

// Simplified structure to store grouped locations - only single or cluster
struct LocationGroup {
    enum GroupType {
        case single
        case cluster     // Multiple friends, show as cluster
    }
    
    let centerCoordinate: CLLocationCoordinate2D
    let friendIds: [String]
    let type: GroupType
    
    var count: Int {
        return friendIds.count
    }
}

// Simplified proximity grouping manager - only using clustering
class FriendLocationGrouper {
    // Distance threshold in meters (5 meters = very close proximity)
    private let proximityThreshold: Double = 5.0
    
    // Minimum friends required to form a cluster (at least 2)
    private let minFriendsForCluster: Int = 2
    
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
                if distanceInMeters <= proximityThreshold {
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
            
            let group = LocationGroup(
                centerCoordinate: centerCoordinate,
                friendIds: nearbyFriendIds,
                type: groupType
            )
            
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
