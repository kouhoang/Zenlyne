//
//  Location.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import Foundation
import CoreLocation

// MARK: - UserLocation struct definition (if not defined elsewhere)
struct UserLocation: Codable {
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
}
