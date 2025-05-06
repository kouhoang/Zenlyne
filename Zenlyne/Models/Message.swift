//
//  Message.swift
//  Zenlyne
//
//  Created by admin on 6/5/25.
//

import Foundation
import FirebaseAuth

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
    
    // Create a dictionary representation for Firebase Realtime Database
    func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "senderId": senderId,
            "receiverId": receiverId,
            "content": content,
            "timestamp": timestamp.timeIntervalSince1970,
            "isRead": isRead
        ]
    }
    
    // Create a Message from Firebase Realtime Database data
    static func fromDictionary(_ data: [String: Any]) -> Message? {
        guard let id = data["id"] as? String,
              let senderId = data["senderId"] as? String,
              let receiverId = data["receiverId"] as? String,
              let content = data["content"] as? String,
              let timestamp = data["timestamp"] as? TimeInterval else {
            return nil
        }
        
        let isRead = data["isRead"] as? Bool ?? false
        
        return Message(
            id: id,
            senderId: senderId,
            receiverId: receiverId,
            content: content,
            timestamp: Date(timeIntervalSince1970: timestamp),
            isRead: isRead
        )
    }
    
    static let sampleData = [
        Message(id: "1", senderId: "user1", receiverId: "user2", content: "Xin chào, bạn khỏe không?", timestamp: Date().addingTimeInterval(-3600), isRead: true),
        Message(id: "2", senderId: "user2", receiverId: "user1", content: "Mình khỏe, cảm ơn bạn!", timestamp: Date().addingTimeInterval(-3000), isRead: true),
        Message(id: "3", senderId: "user1", receiverId: "user2", content: "Bạn đang làm gì vậy?", timestamp: Date().addingTimeInterval(-2400), isRead: true),
        Message(id: "4", senderId: "user2", receiverId: "user1", content: "Mình đang code một app chat", timestamp: Date().addingTimeInterval(-1800), isRead: false)
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
    
    // Create a dictionary representation for Firebase Realtime Database
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "participants": participants,
            "unreadCount": unreadCount
        ]
        
        if let lastMessage = lastMessage {
            dict["lastMessageId"] = lastMessage.id
            dict["lastMessageContent"] = lastMessage.content
            dict["lastMessageTimestamp"] = lastMessage.timestamp.timeIntervalSince1970
            dict["lastMessageSenderId"] = lastMessage.senderId
        }
        
        return dict
    }
    
    static let sampleData = [
        Chat(participants: ["user1", "user2"],
             lastMessage: Message(id: "1", senderId: "user2", receiverId: "user1", content: "Mình đang code một app chat", timestamp: Date().addingTimeInterval(-60), isRead: false),
             unreadCount: 1),
        Chat(participants: ["user1", "user3"],
             lastMessage: Message(id: "2", senderId: "user1", receiverId: "user3", content: "Chúc bạn một ngày tốt lành", timestamp: Date().addingTimeInterval(-3600), isRead: true),
             unreadCount: 0)
    ]
}
