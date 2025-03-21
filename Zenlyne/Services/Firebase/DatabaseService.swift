//
//  DatabaseService.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

// Handle querying and updating data on Firebase
import Foundation
import FirebaseDatabase

protocol FirebaseServiceProtocol {
    func saveUserLocation(userId: String, location: UserLocation)
    func fetchUserLastLocation(userId: String, completion: @escaping (UserLocation?) -> Void)
}

class FirebaseService: FirebaseServiceProtocol {
    private let database = Database.database().reference()
    
    func saveUserLocation(userId: String, location: UserLocation) {
        let locationRef = database.child("users").child(userId).child("location")
        locationRef.setValue(location.toDictionary())
    }
    
    func fetchUserLastLocation(userId: String, completion: @escaping (UserLocation?) -> Void) {
        let locationRef = database.child("users").child(userId).child("location")
        
        locationRef.observeSingleEvent(of: .value) { snapshot in
            guard let value = snapshot.value as? [String: Any],
                  let latitude = value["latitude"] as? Double,
                  let longitude = value["longitude"] as? Double,
                  let timestamp = value["timestamp"] as? TimeInterval else {
                completion(nil)
                return
            }
            
            let userLocation = UserLocation(
                latitude: latitude,
                longitude: longitude,
                timestamp: timestamp
            )
            
            completion(userLocation)
        }
    }
}

// Helper extension
extension UserLocation {
    init?(latitude: Double, longitude: Double, timestamp: TimeInterval) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }
}
