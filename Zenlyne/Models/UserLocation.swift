//
//  UserLocation.swift
//  Zenlyne
//
//  Created by kou on 2/6/25.
//

import Foundation
import CoreLocation
import Combine

// MARK: - UserLocation Model
struct UserLocation: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let timestamp: TimeInterval
    
    init(latitude: Double, longitude: Double, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }
    
    init(coordinate: CLLocationCoordinate2D, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.timestamp = timestamp
    }
    
    func toCoordinate() -> CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    // Calculate age of location
    var age: TimeInterval {
        return Date().timeIntervalSince1970 - timestamp
    }
    
    // Check if location is fresh (less than 1 hour)
    var isFresh: Bool {
        return age < 3600 // 1 hour
    }
    
    // Check if location is recent (less than 24 hours)
    var isRecent: Bool {
        return age < 86400 // 24 hours
    }
    
    // Get relative time string
    var relativeTimeString: String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

