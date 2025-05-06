//
//  Message.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Firebase

struct Message: Identifiable, Codable, Hashable {
    let id: String
    let senderId: String
    let receiverId: String
    let content: String
    let timestamp: Date
    let isRead: Bool
    
    var isFromCurrentUser: Bool {
        return senderId == Auth.auth().currentUser?.uid
    }
    
    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    static let sampleData = [
        Message(id: "1", senderId: "user1", receiverId: "user2", content: "Bombardino Crocodillo", timestamp: Date().addingTimeInterval(-3600), isRead: true),
        Message(id: "2", senderId: "user2", receiverId: "user3", content: "Trulimero Trulocina", timestamp: Date().addingTimeInterval(-3600), isRead: true),
        Message(id: "3", senderId: "user3", receiverId: "user4", content: "Tung Tung Tung Sadur", timestamp: Date().addingTimeInterval(-3600), isRead: true),
        Message(id: "4", senderId: "user4", receiverId: "user1", content: "Tralalelo Tralala", timestamp: Date().addingTimeInterval(-3600), isRead: true)
    ]
}

struct Chat: Identifiable {
    let id: String
    let participants: [String]
    var lastMessage: Message?
    var unreadCount: Int
    
    init(id: String? = nil, participants: [String], lastMessage: Message? = nil, unreadCount: Int = 0) {
        if let id = id {
            self.id = id
        } else {
            let sortedParticipants = participants.sorted()
            self.id = sortedParticipants.joined(separator: "_")
        }
        self.participants = participants
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
    }
    
    func getOtherParticipantId(currentUserId: String) -> String? {
        return participants.first { $0 != currentUserId }
    }
    
    static let sampleData = [
        Chat(participants: ["user1", "user2"],
             lastMessage: Message(id: "1", senderId: "user2", receiverId: "user1", content: "Tung Tung Tung Sadur", timestamp: Date().addingTimeInterval(-60), isRead: false),
             unreadCount: 1),
        Chat(participants: ["user1", "user2"],
             lastMessage: Message(id: "2", senderId: "user1", receiverId: "user3", content: "Tralalelo Tralala", timestamp: Date().addingTimeInterval(-60), isRead: true),
             unreadCount: 0)
    ]
}

