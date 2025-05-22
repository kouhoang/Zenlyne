//
//  User.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import Foundation
import FirebaseAuth
import CoreLocation

struct User: Identifiable, Codable {
    let id: String
    let fullName: String
    let email: String
    var profileImageUrl: String?
    var avatarUrl: String? // New field for Cloudinary URLs
    var friendIds: [String] = []
    var friendRequests: [String] = []
    var isOnline: Bool = false
    var lastLocation: UserLocation?
    var lastSeen: Date?
    var fcmToken: String?
    
    // Computed property to get the current avatar URL
    var currentAvatarUrl: String? {
        return avatarUrl ?? profileImageUrl
    }
    
    // Calculate how long a user has been online (in minutes)
    var timeAgoDisplay: String? {
        guard let lastSeen = self.lastSeen else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastSeen, relativeTo: Date())
    }
    
    // Get user initials for avatar
    var initials: String {
        let formatter = PersonNameComponentsFormatter()
        if let components = formatter.personNameComponents(from: self.fullName) {
            formatter.style = .abbreviated
            return formatter.string(from: components)
        }
        
        // Fallback if formatter fails
        let words = self.fullName.split(separator: " ")
        if words.count > 1 {
            return String(words[0].prefix(1)) + String(words.last!.prefix(1))
        } else if !words.isEmpty {
            return String(words[0].prefix(1))
        } else {
            return "?"
        }
    }
    
    // Get the distance to another user in kilometers (if locations are available)
    func distanceTo(otherUser: User) -> Double? {
        guard let myLocation = self.lastLocation, let otherLocation = otherUser.lastLocation else {
            return nil
        }
        
        let location1 = CLLocation(latitude: myLocation.latitude, longitude: myLocation.longitude)
        let location2 = CLLocation(latitude: otherLocation.latitude, longitude: otherLocation.longitude)
        
        // Calculate distance in meters and convert to kilometers
        return location1.distance(from: location2) / 1000.0
    }
    
    // Check if the location is fresh (less than 24 hours old)
    func hasRecentLocation() -> Bool {
        guard let location = self.lastLocation else {
            return false
        }
        
        // Check if location is less than 24 hours old
        let twentyFourHoursAgo = Date().timeIntervalSince1970 - (24 * 60 * 60)
        return location.timestamp > twentyFourHoursAgo
    }
    
    // Calculate how old the location is
    func locationAge() -> String? {
        guard let location = self.lastLocation else {
            return nil
        }
        
        let locationDate = Date(timeIntervalSince1970: location.timestamp)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        
        return formatter.localizedString(for: locationDate, relativeTo: Date())
    }
    
    // Calculate whether user is nearby (within 1km)
    func isNearby(to otherUser: User) -> Bool {
        guard let distance = distanceTo(otherUser: otherUser) else {
            return false
        }
        return distance <= 1.0 // Within 1 kilometer
    }
}

extension User {
    static var MOCK_USER = User(id: NSUUID().uuidString, fullName: "Kou", email: "test@gmail.com")
}
