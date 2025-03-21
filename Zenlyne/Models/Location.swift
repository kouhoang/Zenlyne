//
//  Location.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import Foundation
import CoreLocation

struct UserLocation: Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: TimeInterval
    
    init(coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.timestamp = Date().timeIntervalSince1970
    }
    
    func toCoordinate() -> CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "latitude": latitude,
            "longitude": longitude,
            "timestamp": timestamp
        ]
    }
}
