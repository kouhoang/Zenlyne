//
//  Chat.swift
//  Zenlyne
//
//  Created by admin on 2/6/25.
//

import Foundation
import Combine

struct Chat: Identifiable, Codable {
    let id: String
    let participants: [String]
    var lastMessage: Message?
    var unreadCount: Int
    var createdAt: Date?
    var updatedAt: Date?
    
    init(id: String, participants: [String], lastMessage: Message? = nil, unreadCount: Int = 0) {
        self.id = id
        self.participants = participants
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    func getOtherParticipantId(currentUserId: String) -> String? {
        return participants.first { $0 != currentUserId }
    }
}
