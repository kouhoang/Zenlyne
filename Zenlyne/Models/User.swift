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
    
    var currentAvatarUrl: String? {
        return avatarUrl ?? profileImageUrl
    }
    
    /// Returns user initials for display
    var initials: String {
        let formatter = PersonNameComponentsFormatter()
        if let components = formatter.personNameComponents(from: fullName) {
            formatter.style = .abbreviated
            return formatter.string(from: components)
        } else {
            // Fallback logic
            let words = fullName.split(separator: " ")
            if words.count > 1 {
                return String(words[0].prefix(1)).uppercased() + String(words.last!.prefix(1)).uppercased()
            } else if !words.isEmpty {
                return String(words[0].prefix(1)).uppercased()
            } else {
                return "U"
            }
        }
    }
    
    /// Check if user has a valid location that's not expired
    var hasValidLocation: Bool {
        guard let location = lastLocation else { return false }
        let currentTime = Date().timeIntervalSince1970
        let expirationTime: TimeInterval = 72 * 60 * 60 // 72 hours
        return (currentTime - location.timestamp) < expirationTime
    }
    
    /// Get time since last location update
    var locationAge: TimeInterval? {
        guard let location = lastLocation else { return nil }
        return Date().timeIntervalSince1970 - location.timestamp
    }
    
    /// Get formatted last seen time
    var formattedLastSeen: String {
        if isOnline {
            return "Online"
        } else if let lastSeen = lastSeen {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Last seen \(formatter.localizedString(for: lastSeen, relativeTo: Date()))"
        } else {
            return "Offline"
        }
    }
    
    /// Static mock user for preview/testing
    static let MOCK_USER = User(
        id: "mock_user_id",
        fullName: "John Doe",
        email: "john.doe@example.com"
    )
    
    /// Create mock friends for testing
    static func createMockFriends(count: Int = 5) -> [User] {
        let names = [
            "Alice Johnson", "Bob Smith", "Carol Williams", "David Brown", "Emma Davis",
            "Frank Miller", "Grace Wilson", "Henry Moore", "Ivy Taylor", "Jack Anderson"
        ]
        
        return (0..<min(count, names.count)).map { index in
            var user = User(
                id: "mock_friend_\(index)",
                fullName: names[index],
                email: "\(names[index].lowercased().replacingOccurrences(of: " ", with: "."))@example.com"
            )
            user.isOnline = Bool.random()
            user.lastSeen = Date().addingTimeInterval(-Double.random(in: 300...7200)) // Random last seen within 2 hours
            
            // Add mock location
            let latOffset = Double.random(in: -0.05...0.05)
            let lonOffset = Double.random(in: -0.05...0.05)
            user.lastLocation = UserLocation(
                latitude: 21.01991 + latOffset,
                longitude: 105.7838 + lonOffset,
                timestamp: Date().timeIntervalSince1970 - Double.random(in: 0...3600)
            )
            
            return user
        }
    }
}

//extension User {
//    static var MOCK_USER = User(id: NSUUID().uuidString, fullName: "Kou", email: "test@gmail.com")
//}
//

