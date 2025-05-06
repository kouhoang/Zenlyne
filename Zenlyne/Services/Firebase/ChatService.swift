//
//  FirestoreChatService.swift
//  Zenlyne
//
//  Created by admin on 6/5/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

class FirebaseChatService {
    private let firestore = Firestore.firestore()
    private var messageListeners: [ListenerRegistration] = []
    private var chatListeners: [ListenerRegistration] = []
    
    // MARK: - Chat Handling
    
    /// Generates a unique chat ID for two users
    private func generateChatId(userId1: String, userId2: String) -> String {
        let sortedIds = [userId1, userId2].sorted()
        return sortedIds.joined(separator: "_")
    }
    
    /// Sends a message to another user
    func sendMessage(to receiverId: String, content: String, completion: @escaping (Result<Message, Error>) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "FirestoreChatService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])))
            return
        }
        
        let senderId = currentUser.uid
        let chatId = generateChatId(userId1: senderId, userId2: receiverId)
        
        // Create message reference
        let messagesRef = firestore.collection("chats").document(chatId).collection("messages")
        let messageRef = messagesRef.document()
        let messageId = messageRef.documentID
        let timestamp = Date()
        
        let messageData: [String: Any] = [
            "id": messageId,
            "senderId": senderId,
            "receiverId": receiverId,
            "content": content,
            "timestamp": timestamp,
            "isRead": false
        ]
        
        // Save the message to the chat
        messageRef.setData(messageData) { error in
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
                "updatedAt": FieldValue.serverTimestamp()
            ]
            
            // Update the chat document
            self.firestore.collection("chats").document(chatId).setData(chatMetadata, merge: true)
            
            // Update user's chat list
            let batch = self.firestore.batch()
            
            // Update sender's chat list
            let senderChatRef = self.firestore.collection("user-chats").document(senderId).collection("chats").document(chatId)
            batch.setData([
                "chatId": chatId,
                "otherUserId": receiverId,
                "lastMessageTimestamp": timestamp,
                "lastActivity": FieldValue.serverTimestamp()
            ], forDocument: senderChatRef, merge: true)
            
            // Update receiver's chat list and increment unread count
            let receiverChatRef = self.firestore.collection("user-chats").document(receiverId).collection("chats").document(chatId)
            self.firestore.collection("user-chats").document(receiverId).collection("chats").document(chatId).getDocument { snapshot, error in
                // Start with current unread count or 0
                var unreadCount = 0
                if let data = snapshot?.data(), let currentUnread = data["unreadCount"] as? Int {
                    unreadCount = currentUnread
                }
                
                // Create the document or update it
                batch.setData([
                    "chatId": chatId,
                    "otherUserId": senderId,
                    "unreadCount": unreadCount + 1,
                    "lastMessageTimestamp": timestamp,
                    "lastActivity": FieldValue.serverTimestamp()
                ], forDocument: receiverChatRef, merge: true)
                
                // Commit the batch
                batch.commit { error in
                    if let error = error {
                        print("Error updating chat metadata: \(error.localizedDescription)")
                    }
                    
                    // Create a message object to return
                    let message = Message(
                        id: messageId,
                        senderId: senderId,
                        receiverId: receiverId,
                        content: content,
                        timestamp: timestamp,
                        isRead: false
                    )
                    
                    completion(.success(message))
                }
            }
        }
    }
    
    /// Retrieves messages for a specific chat with real-time updates
    func getMessages(with userId: String, completion: @escaping (Result<[Message], Error>) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "FirestoreChatService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])))
            return
        }
        
        let chatId = generateChatId(userId1: currentUser.uid, userId2: userId)
        
        // Clear previous listeners if any
        removeMessageListeners()
        
        // Add new listener
        let listener = firestore.collection("chats").document(chatId).collection("messages")
            .order(by: "timestamp")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                var messages: [Message] = []
                let currentUserId = currentUser.uid
                var messagesToMarkAsRead: [String] = []
                
                for document in documents {
                    let data = document.data()
                    
                    guard let id = data["id"] as? String,
                          let senderId = data["senderId"] as? String,
                          let receiverId = data["receiverId"] as? String,
                          let content = data["content"] as? String,
                          let timestamp = data["timestamp"] as? Timestamp else {
                        continue
                    }
                    
                    let isRead = data["isRead"] as? Bool ?? false
                    
                    let message = Message(
                        id: id,
                        senderId: senderId,
                        receiverId: receiverId,
                        content: content,
                        timestamp: timestamp.dateValue(),
                        isRead: isRead
                    )
                    
                    messages.append(message)
                    
                    // Mark as read if current user is the receiver and message is unread
                    if receiverId == currentUserId && !isRead {
                        messagesToMarkAsRead.append(id)
                    }
                }
                
                // Mark messages as read and reset unread count
                if !messagesToMarkAsRead.isEmpty {
                    self.markMessagesAsRead(chatId: chatId, messageIds: messagesToMarkAsRead)
                    self.resetUnreadCount(chatId: chatId, userId: currentUserId)
                }
                
                completion(.success(messages))
            }
        
        messageListeners.append(listener)
    }
    
    /// Marks multiple messages as read
    private func markMessagesAsRead(chatId: String, messageIds: [String]) {
        let batch = firestore.batch()
        
        for messageId in messageIds {
            let messageRef = firestore.collection("chats").document(chatId).collection("messages").document(messageId)
            batch.updateData(["isRead": true], forDocument: messageRef)
        }
        
        batch.commit { error in
            if let error = error {
                print("Error marking messages as read: \(error.localizedDescription)")
            }
        }
    }
    
    /// Resets unread count for a chat
    private func resetUnreadCount(chatId: String, userId: String) {
        let chatRef = firestore.collection("user-chats").document(userId).collection("chats").document(chatId)
        chatRef.updateData(["unreadCount": 0]) { error in
            if let error = error {
                print("Error resetting unread count: \(error.localizedDescription)")
            }
        }
    }
    
    /// Gets a list of all user chats with real-time updates
    func getUserChats(completion: @escaping (Result<[Chat], Error>) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "FirestoreChatService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])))
            return
        }
        
        // Clear previous listeners if any
        removeChatListeners()
        
        // Add new listener for user's chats
        let listener = firestore.collection("user-chats").document(currentUser.uid).collection("chats")
            .order(by: "lastMessageTimestamp", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                var chatInfos: [(chatId: String, otherUserId: String, unreadCount: Int)] = []
                
                // First, extract basic chat info
                for document in documents {
                    let data = document.data()
                    
                    guard let chatId = data["chatId"] as? String,
                          let otherUserId = data["otherUserId"] as? String else {
                        continue
                    }
                    
                    let unreadCount = data["unreadCount"] as? Int ?? 0
                    chatInfos.append((chatId: chatId, otherUserId: otherUserId, unreadCount: unreadCount))
                }
                
                // Now fetch complete chat data with last messages
                let group = DispatchGroup()
                var chats: [Chat] = []
                
                for chatInfo in chatInfos {
                    group.enter()
                    
                    // Get chat metadata
                    self.firestore.collection("chats").document(chatInfo.chatId).getDocument { chatSnapshot, error in
                        defer { group.leave() }
                        
                        guard let chatDoc = chatSnapshot, chatDoc.exists,
                              let chatData = chatDoc.data() else {
                            return
                        }
                        
                        // Get last message if available
                        var lastMessage: Message?
                        
                        if let lastMessageId = chatData["lastMessageId"] as? String,
                           let lastMessageContent = chatData["lastMessageContent"] as? String,
                           let lastMessageSenderId = chatData["lastMessageSenderId"] as? String,
                           let lastMessageTimestamp = chatData["lastMessageTimestamp"] as? Timestamp {
                            
                            // Determine receiver ID
                            let lastMessageReceiverId = lastMessageSenderId == currentUser.uid ?
                                chatInfo.otherUserId : currentUser.uid
                            
                            lastMessage = Message(
                                id: lastMessageId,
                                senderId: lastMessageSenderId,
                                receiverId: lastMessageReceiverId,
                                content: lastMessageContent,
                                timestamp: lastMessageTimestamp.dateValue(),
                                isRead: chatInfo.unreadCount == 0 || lastMessageSenderId == currentUser.uid
                            )
                        }
                        
                        let chat = Chat(
                            id: chatInfo.chatId,
                            participants: [currentUser.uid, chatInfo.otherUserId],
                            lastMessage: lastMessage,
                            unreadCount: chatInfo.unreadCount
                        )
                        
                        chats.append(chat)
                    }
                }
                
                group.notify(queue: .main) {
                    // Sort chats by last message timestamp (most recent first)
                    chats.sort { (chat1, chat2) -> Bool in
                        let timestamp1 = chat1.lastMessage?.timestamp ?? Date(timeIntervalSince1970: 0)
                        let timestamp2 = chat2.lastMessage?.timestamp ?? Date(timeIntervalSince1970: 0)
                        return timestamp1 > timestamp2
                    }
                    
                    completion(.success(chats))
                }
            }
        
        chatListeners.append(listener)
    }
    
    /// Creates a new chat between two users if it doesn't exist
    func createChatIfNeeded(with userId: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "FirestoreChatService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])))
            return
        }
        
        let chatId = generateChatId(userId1: currentUser.uid, userId2: userId)
        
        // Check if chat already exists
        firestore.collection("chats").document(chatId).getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if snapshot?.exists != true {
                // Create chat document
                let chatData: [String: Any] = [
                    "participants": [currentUser.uid, userId],
                    "createdAt": FieldValue.serverTimestamp()
                ]
                
                self.firestore.collection("chats").document(chatId).setData(chatData) { error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }
                    
                    // Create user-chat entries for both users
                    let batch = self.firestore.batch()
                    
                    let currentUserChatRef = self.firestore.collection("user-chats").document(currentUser.uid).collection("chats").document(chatId)
                    batch.setData([
                        "chatId": chatId,
                        "otherUserId": userId,
                        "unreadCount": 0,
                        "lastActivity": FieldValue.serverTimestamp()
                    ], forDocument: currentUserChatRef)
                    
                    let otherUserChatRef = self.firestore.collection("user-chats").document(userId).collection("chats").document(chatId)
                    batch.setData([
                        "chatId": chatId,
                        "otherUserId": currentUser.uid,
                        "unreadCount": 0,
                        "lastActivity": FieldValue.serverTimestamp()
                    ], forDocument: otherUserChatRef)
                    
                    batch.commit { error in
                        if let error = error {
                            completion(.failure(error))
                        } else {
                            completion(.success(chatId))
                        }
                    }
                }
            } else {
                // Chat already exists
                completion(.success(chatId))
            }
        }
    }
    
    /// Gets the total number of unread messages across all chats
    func getTotalUnreadMessagesCount(completion: @escaping (Int) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(0)
            return
        }
        
        firestore.collection("user-chats").document(currentUser.uid).collection("chats")
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error getting unread counts: \(error.localizedDescription)")
                    completion(0)
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(0)
                    return
                }
                
                let totalCount = documents.reduce(0) { result, document in
                    let unreadCount = document.data()["unreadCount"] as? Int ?? 0
                    return result + unreadCount
                }
                
                completion(totalCount)
            }
    }
    
    /// Deletes a chat from the user's list
    func deleteChat(chatId: String, completion: @escaping (Bool) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(false)
            return
        }
        
        // Delete from user-chats collection
        let userChatRef = firestore.collection("user-chats").document(currentUser.uid).collection("chats").document(chatId)
        userChatRef.delete { error in
            if let error = error {
                print("Error deleting chat: \(error.localizedDescription)")
                completion(false)
            } else {
                completion(true)
            }
        }
    }
    
    // MARK: - Listener Cleanup
    
    /// Removes message listeners
    private func removeMessageListeners() {
        for listener in messageListeners {
            listener.remove()
        }
        messageListeners.removeAll()
    }
    
    /// Removes chat listeners
    private func removeChatListeners() {
        for listener in chatListeners {
            listener.remove()
        }
        chatListeners.removeAll()
    }
    
    /// Removes all listeners
    func removeAllObservers() {
        removeMessageListeners()
        removeChatListeners()
    }
}
