//
//  FriendRequest.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import Foundation

struct FriendRequest: Identifiable, Codable {
    let id: String
    let senderId: String
    let senderEmail: String
    let recipientId: String
    let status: String
    var timestamp: Date = Date()
    
    enum Status: String, CaseIterable {
        case pending = "pending"
        case accepted = "accepted"
        case declined = "declined"
    }
}
