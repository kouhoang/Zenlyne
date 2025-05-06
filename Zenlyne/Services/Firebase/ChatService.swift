//
//  MessagingService.swift
//  Zenlyne
//
//  Created by admin on 26/4/25.
//

import Foundation
import FirebaseDatabase
import FirebaseFirestore
import FirebaseAuth
import Combine

class MessagingService {
    private let database = Database.database().reference()
    private let firestore = Firestore.firestore()
    
    // MARK: - Chat Handling
    
    /// Generates a unique chat ID for two users
    private func generateChatId(userId1: String, userId2: String) -> String {
        let sortedIds = [userId1, userId2].sorted()
        return sortedIds.joined(separator: "_")
    }
    
    /// Sends a message to another user
    func sendMessage(to receiverId: String, content: String, completion: @escaping (Result<Message, Error>) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "MessagingService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])))
            return
        }
        
        let senderId = currentUser.uid
        let chatId = generateChatId(userId1: senderId, userId2: receiverId)
        let messageId = database.child("messages").child(chatId).childByAutoId().key ?? UUID().uuidString
        let timestamp = Date().timeIntervalSince1970
        
        let messageData: [String: Any] = [
            "id": messageId,
            "senderId": senderId,
            "receiverId": receiverId,
            "content": content,
            "timestamp": timestamp,
            "isRead": false
        ]
        
        // Save the message to the chat
        database.child("messages").child(chatId).child(messageId).setValue(messageData) { error, _ in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            // Update the chat metadata for both users
            let chatMetadata: [String: Any] = [
                "lastMessageId": messageId,
                "lastMessageContent": content,
                "lastMessageTimestamp": timestamp,
                "lastMessageSenderId": senderId,
                "updatedAt": timestamp
            ]
            
            // Update sender's chat list
            self.database.child("user-chats").child(senderId).child(chatId).updateChildValues(chatMetadata)
            
            // Update receiver's chat list and increment unread count
            self.database.child("user-chats").child(receiverId).child(chatId).updateChildValues(chatMetadata)
            self.database.child("user-chats").child(receiverId).child(chatId).child("unreadCount").runTransactionBlock { (currentData) -> TransactionResult in
                var count = currentData.value as? Int ?? 0
                count += 1
                currentData.value = count
                return TransactionResult.success(withValue: currentData)
            }
            
            // Also make sure participants field exists in both user's chats
            self.database.child("user-chats").child(senderId).child(chatId).child("participants").setValue([senderId, receiverId])
            self.database.child("user-chats").child(receiverId).child(chatId).child("participants").setValue([senderId, receiverId])
            
            // Return the created message
            let message = Message(
                id: messageId,
                senderId: senderId,
                receiverId: receiverId,
                content: content,
                timestamp: Date(timeIntervalSince1970: timestamp),
                isRead: false
            )
            
            completion(.success(message))
        }
    }
    
    /// Retrieves messages for a specific chat
    func getMessages(with userId: String, completion: @escaping (Result<[Message], Error>) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "MessagingService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])))
            return
        }
        
        let chatId = generateChatId(userId1: currentUser.uid, userId2: userId)
        
        database.child("messages").child(chatId).queryOrdered(byChild: "timestamp").observe(.value) { snapshot in
            guard snapshot.exists() else {
                completion(.success([]))
                return
            }
            
            var messages: [Message] = []
            
            for child in snapshot.children {
                guard let snapshot = child as? DataSnapshot,
                      let data = snapshot.value as? [String: Any],
                      let id = data["id"] as? String,
                      let senderId = data["senderId"] as? String,
                      let receiverId = data["receiverId"] as? String,
                      let content = data["content"] as? String,
                      let timestamp = data["timestamp"] as? TimeInterval else {
                    continue
                }
                
                let isRead = data["isRead"] as? Bool ?? false
                
                let message = Message(
                    id: id,
                    senderId: senderId,
                    receiverId: receiverId,
                    content: content,
                    timestamp: Date(timeIntervalSince1970: timestamp),
                    isRead: isRead
                )
                
                messages.append(message)
            }
            
            // Mark all messages as read if the current user is the receiver
            for message in messages where message.receiverId == currentUser.uid && !message.isRead {
                self.markMessageAsRead(chatId: chatId, messageId: message.id)
            }
            
            // Reset unread count for this chat
            self.database.child("user-chats").child(currentUser.uid).child(chatId).child("unreadCount").setValue(0)
            
            // Sort messages by timestamp
            messages.sort { $0.timestamp < $1.timestamp }
            
            completion(.success(messages))
        }
    }
    
    /// Marks a message as read
    private func markMessageAsRead(chatId: String, messageId: String) {
        database.child("messages").child(chatId).child(messageId).child("isRead").setValue(true)
    }
    
    /// Gets a list of all user chats
    func getUserChats(completion: @escaping (Result<[Chat], Error>) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "MessagingService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])))
            return
        }
        
        database.child("user-chats").child(currentUser.uid).observe(.value) { snapshot in
            guard snapshot.exists() else {
                completion(.success([]))
                return
            }
            
            var chats: [Chat] = []
            
            for child in snapshot.children {
                guard let snapshot = child as? DataSnapshot,
                      let data = snapshot.value as? [String: Any],
                      let participants = data["participants"] as? [String] else {
                    continue
                }
                
                let chatId = snapshot.key
                let unreadCount = data["unreadCount"] as? Int ?? 0
                
                var lastMessage: Message?
                
                // Create the last message if data exists
                if let lastMessageId = data["lastMessageId"] as? String,
                   let lastMessageContent = data["lastMessageContent"] as? String,
                   let lastMessageSenderId = data["lastMessageSenderId"] as? String,
                   let lastMessageTimestamp = data["lastMessageTimestamp"] as? TimeInterval {
                    
                    // Determine receiver ID from last message
                    let lastMessageReceiverId = lastMessageSenderId == currentUser.uid ?
                        participants.first(where: { $0 != currentUser.uid }) ?? "" :
                        currentUser.uid
                    
                    lastMessage = Message(
                        id: lastMessageId,
                        senderId: lastMessageSenderId,
                        receiverId: lastMessageReceiverId,
                        content: lastMessageContent,
                        timestamp: Date(timeIntervalSince1970: lastMessageTimestamp),
                        isRead: unreadCount == 0
                    )
                }
                
                let chat = Chat(
                    id: chatId,
                    participants: participants,
                    lastMessage: lastMessage,
                    unreadCount: unreadCount
                )
                
                chats.append(chat)
            }
            
            // Sort chats by last message timestamp (most recent first)
            chats.sort { (chat1, chat2) -> Bool in
                let timestamp1 = chat1.lastMessage?.timestamp ?? Date(timeIntervalSince1970: 0)
                let timestamp2 = chat2.lastMessage?.timestamp ?? Date(timeIntervalSince1970: 0)
                return timestamp1 > timestamp2
            }
            
            completion(.success(chats))
        }
    }
    
    /// Creates a new chat between two users if it doesn't exist
    func createChatIfNeeded(with userId: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "MessagingService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])))
            return
        }
        
        let chatId = generateChatId(userId1: currentUser.uid, userId2: userId)
        
        // Check if chat already exists
        database.child("user-chats").child(currentUser.uid).child(chatId).observeSingleEvent(of: .value) { snapshot in
            if !snapshot.exists() {
                // Create chat metadata for both users
                let participants = [currentUser.uid, userId]
                let chatData: [String: Any] = [
                    "participants": participants,
                    "createdAt": ServerValue.timestamp(),
                    "unreadCount": 0
                ]
                
                self.database.child("user-chats").child(currentUser.uid).child(chatId).setValue(chatData)
                self.database.child("user-chats").child(userId).child(chatId).setValue(chatData)
            }
            
            completion(.success(chatId))
        }
    }
    
    /// Gets the total number of unread messages across all chats
    func getTotalUnreadMessagesCount(completion: @escaping (Int) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(0)
            return
        }
        
        database.child("user-chats").child(currentUser.uid).observeSingleEvent(of: .value) { snapshot in
            guard snapshot.exists() else {
                completion(0)
                return
            }
            
            var totalCount = 0
            
            for child in snapshot.children {
                guard let snapshot = child as? DataSnapshot,
                      let data = snapshot.value as? [String: Any],
                      let unreadCount = data["unreadCount"] as? Int else {
                    continue
                }
                
                totalCount += unreadCount
            }
            
            completion(totalCount)
        }
    }
    
    /// Removes a chat from the user's chat list (doesn't delete the actual messages)
    func deleteChat(chatId: String, completion: @escaping (Bool) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(false)
            return
        }
        
        database.child("user-chats").child(currentUser.uid).child(chatId).removeValue { error, _ in
            completion(error == nil)
        }
    }
    
    // Listener cleanup
    func removeObservers() {
        guard let currentUser = Auth.auth().currentUser else { return }
        database.child("user-chats").child(currentUser.uid).removeAllObservers()
    }
}
