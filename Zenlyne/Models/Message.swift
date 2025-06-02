//
//  Message.swift
//  Zenlyne
//
//  Created by admin on 6/5/25.
//

import Foundation
import Combine

struct Message: Identifiable, Codable {
    let id: String
    let senderId: String
    let receiverId: String
    let content: String
    let timestamp: Date
    var isRead: Bool
    
    init(id: String, senderId: String, receiverId: String, content: String, timestamp: Date, isRead: Bool = false) {
        self.id = id
        self.senderId = senderId
        self.receiverId = receiverId
        self.content = content
        self.timestamp = timestamp
        self.isRead = isRead
    }
}
