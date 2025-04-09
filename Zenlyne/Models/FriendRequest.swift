//
//  FriendRequest.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import Foundation

struct FriendRequest: Identifiable {
    let id: String
    let senderId: String
    let senderEmail: String
    let recipientId: String
    let status: String
}
	
