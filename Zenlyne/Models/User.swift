//
//  User.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import Foundation
import FirebaseAuth

struct User: Identifiable, Codable {
    let id: String
    let fullName: String
    let email: String
    var profileImageUrl: String?
    var friendIds: [String] = []
    var friendRequests: [String] = []
    var isOnline: Bool = false
    var lastLocation: UserLocation?
    var lastSeen: Date?
    
    // Hàm này trả về thời gian user ở online trong bao lâu (đơn vị: phút)
    var timeAgoDisplay: String? {
        guard let lastSeen = lastSeen else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastSeen, relativeTo: Date())
    }
    
    var initials: String {
        let formatter = PersonNameComponentsFormatter()
        if let components = formatter.personNameComponents(from: fullName) {
            formatter.style = .abbreviated
            return formatter.string(from: components)
        }
        
        return ""
    }
}

extension User {
    static var MOCK_USER = User(id: NSUUID().uuidString, fullName: "Kou", email: "test@gmail.com")
}
