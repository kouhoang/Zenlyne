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

protocol ChatServiceProtocol {
    func sendMessage(to receiverId: String, content: String) -> AnyPublisher<Message, Error>
    func getMessages(with userId: String) -> AnyPublisher<[Message], Error>
    func getUserChats() -> AnyPublisher<[Chat], Error>
    func createChatIfNeeded(with userId: String) -> AnyPublisher<String, Error>
    func getTotalUnreadMessagesCount() -> AnyPublisher<Int, Error>
    func deleteChat(chatId: String) -> AnyPublisher<Bool, Error>
}

class FirebaseChatService: ChatServiceProtocol {
    private let firestore = Firestore.firestore()
    private var messageListeners: [ListenerRegistration] = []
    private var chatListeners: [ListenerRegistration] = []
    
    deinit {
        removeAllObservers()
    }
    
    // MARK: - Private Methods
    
    private func generateChatId(userId1: String, userId2: String) -> String {
        let sortedIds = [userId1, userId2].sorted()
        return sortedIds.joined(separator: "_")
    }
    
    // MARK: - Public Methods
    
    func sendMessage(to receiverId: String, content: String) -> AnyPublisher<Message, Error> {
        return Future<Message, Error> { [weak self] promise in
            guard let self = self,
                  let currentUser = Auth.auth().currentUser else {
                promise(.failure(ChatError.notLoggedIn))
                return
            }
            
            let senderId = currentUser.uid
            let chatId = self.generateChatId(userId1: senderId, userId2: receiverId)
            
            let messagesRef = self.firestore.collection("chats").document(chatId).collection("messages")
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
            
            messageRef.setData(messageData) { error in
                if let error = error {
                    promise(.failure(error))
                    return
                }
                
                self.updateChatMetadata(chatId: chatId, messageId: messageId, content: content, timestamp: timestamp, senderId: senderId, receiverId: receiverId)
                
                let message = Message(
                    id: messageId,
                    senderId: senderId,
                    receiverId: receiverId,
                    content: content,
                    timestamp: timestamp,
                    isRead: false
                )
                
                promise(.success(message))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func getMessages(with userId: String) -> AnyPublisher<[Message], Error> {
        return Future<[Message], Error> { [weak self] promise in
            guard let self = self,
                  let currentUser = Auth.auth().currentUser else {
                promise(.failure(ChatError.notLoggedIn))
                return
            }
            
            let chatId = self.generateChatId(userId1: currentUser.uid, userId2: userId)
            
            self.removeMessageListeners()
            
            let listener = self.firestore.collection("chats").document(chatId).collection("messages")
                .order(by: "timestamp")
                .addSnapshotListener { snapshot, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        promise(.success([]))
                        return
                    }
                    
                    var messages: [Message] = []
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
                        
                        if receiverId == currentUser.uid && !isRead {
                            messagesToMarkAsRead.append(id)
                        }
                    }
                    
                    if !messagesToMarkAsRead.isEmpty {
                        self.markMessagesAsRead(chatId: chatId, messageIds: messagesToMarkAsRead)
                        self.resetUnreadCount(chatId: chatId, userId: currentUser.uid)
                    }
                    
                    promise(.success(messages))
                }
            
            self.messageListeners.append(listener)
        }
        .eraseToAnyPublisher()
    }
    
    func getUserChats() -> AnyPublisher<[Chat], Error> {
        return Future<[Chat], Error> { [weak self] promise in
            guard let self = self,
                  let currentUser = Auth.auth().currentUser else {
                promise(.failure(ChatError.notLoggedIn))
                return
            }
            
            self.removeChatListeners()
            
            let listener = self.firestore.collection("user-chats").document(currentUser.uid).collection("chats")
                .order(by: "lastMessageTimestamp", descending: true)
                .addSnapshotListener { snapshot, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        promise(.success([]))
                        return
                    }
                    
                    var chatInfos: [(chatId: String, otherUserId: String, unreadCount: Int)] = []
                    
                    for document in documents {
                        let data = document.data()
                        
                        guard let chatId = data["chatId"] as? String,
                              let otherUserId = data["otherUserId"] as? String else {
                            continue
                        }
                        
                        let unreadCount = data["unreadCount"] as? Int ?? 0
                        chatInfos.append((chatId: chatId, otherUserId: otherUserId, unreadCount: unreadCount))
                    }
                    
                    self.fetchCompleteChatsData(chatInfos: chatInfos, currentUserId: currentUser.uid) { chats in
                        promise(.success(chats))
                    }
                }
            
            self.chatListeners.append(listener)
        }
        .eraseToAnyPublisher()
    }
    
    func createChatIfNeeded(with userId: String) -> AnyPublisher<String, Error> {
        return Future<String, Error> { [weak self] promise in
            guard let self = self,
                  let currentUser = Auth.auth().currentUser else {
                promise(.failure(ChatError.notLoggedIn))
                return
            }
            
            let chatId = self.generateChatId(userId1: currentUser.uid, userId2: userId)
            
            self.firestore.collection("chats").document(chatId).getDocument { snapshot, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }
                
                if snapshot?.exists != true {
                    self.createNewChat(chatId: chatId, currentUserId: currentUser.uid, otherUserId: userId) { result in
                        promise(result)
                    }
                } else {
                    promise(.success(chatId))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    func getTotalUnreadMessagesCount() -> AnyPublisher<Int, Error> {
        return Future<Int, Error> { [weak self] promise in
            guard let self = self,
                  let currentUser = Auth.auth().currentUser else {
                promise(.failure(ChatError.notLoggedIn))
                return
            }
            
            self.firestore.collection("user-chats").document(currentUser.uid).collection("chats")
                .getDocuments { snapshot, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        promise(.success(0))
                        return
                    }
                    
                    let totalCount = documents.reduce(0) { result, document in
                        let unreadCount = document.data()["unreadCount"] as? Int ?? 0
                        return result + unreadCount
                    }
                    
                    promise(.success(totalCount))
                }
        }
        .eraseToAnyPublisher()
    }
    
    func deleteChat(chatId: String) -> AnyPublisher<Bool, Error> {
        return Future<Bool, Error> { [weak self] promise in
            guard let self = self,
                  let currentUser = Auth.auth().currentUser else {
                promise(.failure(ChatError.notLoggedIn))
                return
            }
            
            let userChatRef = self.firestore.collection("user-chats").document(currentUser.uid).collection("chats").document(chatId)
            userChatRef.delete { error in
                if let error = error {
                    promise(.failure(error))
                } else {
                    promise(.success(true))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Helper Methods
    
    private func updateChatMetadata(chatId: String, messageId: String, content: String, timestamp: Date, senderId: String, receiverId: String) {
        let chatMetadata: [String: Any] = [
            "lastMessageId": messageId,
            "lastMessageContent": content,
            "lastMessageTimestamp": timestamp,
            "lastMessageSenderId": senderId,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        firestore.collection("chats").document(chatId).setData(chatMetadata, merge: true)
        
        let batch = firestore.batch()
        
        let senderChatRef = firestore.collection("user-chats").document(senderId).collection("chats").document(chatId)
        batch.setData([
            "chatId": chatId,
            "otherUserId": receiverId,
            "lastMessageTimestamp": timestamp,
            "lastActivity": FieldValue.serverTimestamp()
        ], forDocument: senderChatRef, merge: true)
        
        let receiverChatRef = firestore.collection("user-chats").document(receiverId).collection("chats").document(chatId)
        firestore.collection("user-chats").document(receiverId).collection("chats").document(chatId).getDocument { snapshot, error in
            var unreadCount = 0
            if let data = snapshot?.data(), let currentUnread = data["unreadCount"] as? Int {
                unreadCount = currentUnread
            }
            
            batch.setData([
                "chatId": chatId,
                "otherUserId": senderId,
                "unreadCount": unreadCount + 1,
                "lastMessageTimestamp": timestamp,
                "lastActivity": FieldValue.serverTimestamp()
            ], forDocument: receiverChatRef, merge: true)
            
            batch.commit()
        }
    }
    
    private func fetchCompleteChatsData(chatInfos: [(chatId: String, otherUserId: String, unreadCount: Int)], currentUserId: String, completion: @escaping ([Chat]) -> Void) {
        let group = DispatchGroup()
        var chats: [Chat] = []
        
        for chatInfo in chatInfos {
            group.enter()
            
            firestore.collection("chats").document(chatInfo.chatId).getDocument { chatSnapshot, error in
                defer { group.leave() }
                
                guard let chatDoc = chatSnapshot, chatDoc.exists,
                      let chatData = chatDoc.data() else {
                    return
                }
                
                var lastMessage: Message?
                
                if let lastMessageId = chatData["lastMessageId"] as? String,
                   let lastMessageContent = chatData["lastMessageContent"] as? String,
                   let lastMessageSenderId = chatData["lastMessageSenderId"] as? String,
                   let lastMessageTimestamp = chatData["lastMessageTimestamp"] as? Timestamp {
                    
                    let lastMessageReceiverId = lastMessageSenderId == currentUserId ?
                        chatInfo.otherUserId : currentUserId
                    
                    lastMessage = Message(
                        id: lastMessageId,
                        senderId: lastMessageSenderId,
                        receiverId: lastMessageReceiverId,
                        content: lastMessageContent,
                        timestamp: lastMessageTimestamp.dateValue(),
                        isRead: chatInfo.unreadCount == 0 || lastMessageSenderId == currentUserId
                    )
                }
                
                let chat = Chat(
                    id: chatInfo.chatId,
                    participants: [currentUserId, chatInfo.otherUserId],
                    lastMessage: lastMessage,
                    unreadCount: chatInfo.unreadCount
                )
                
                chats.append(chat)
            }
        }
        
        group.notify(queue: .main) {
            chats.sort { (chat1, chat2) -> Bool in
                let timestamp1 = chat1.lastMessage?.timestamp ?? Date(timeIntervalSince1970: 0)
                let timestamp2 = chat2.lastMessage?.timestamp ?? Date(timeIntervalSince1970: 0)
                return timestamp1 > timestamp2
            }
            
            completion(chats)
        }
    }
    
    private func createNewChat(chatId: String, currentUserId: String, otherUserId: String, completion: @escaping (Result<String, Error>) -> Void) {
        let chatData: [String: Any] = [
            "participants": [currentUserId, otherUserId],
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        firestore.collection("chats").document(chatId).setData(chatData) { error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            let batch = self.firestore.batch()
            
            let currentUserChatRef = self.firestore.collection("user-chats").document(currentUserId).collection("chats").document(chatId)
            batch.setData([
                "chatId": chatId,
                "otherUserId": otherUserId,
                "unreadCount": 0,
                "lastActivity": FieldValue.serverTimestamp()
            ], forDocument: currentUserChatRef)
            
            let otherUserChatRef = self.firestore.collection("user-chats").document(otherUserId).collection("chats").document(chatId)
            batch.setData([
                "chatId": chatId,
                "otherUserId": currentUserId,
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
    }
    
    private func markMessagesAsRead(chatId: String, messageIds: [String]) {
        let batch = firestore.batch()
        
        for messageId in messageIds {
            let messageRef = firestore.collection("chats").document(chatId).collection("messages").document(messageId)
            batch.updateData(["isRead": true], forDocument: messageRef)
        }
        
        batch.commit()
    }
    
    private func resetUnreadCount(chatId: String, userId: String) {
        let chatRef = firestore.collection("user-chats").document(userId).collection("chats").document(chatId)
        chatRef.updateData(["unreadCount": 0])
    }
    
    private func removeMessageListeners() {
        for listener in messageListeners {
            listener.remove()
        }
        messageListeners.removeAll()
    }
    
    private func removeChatListeners() {
        for listener in chatListeners {
            listener.remove()
        }
        chatListeners.removeAll()
    }
    
    func removeAllObservers() {
        removeMessageListeners()
        removeChatListeners()
    }
}
