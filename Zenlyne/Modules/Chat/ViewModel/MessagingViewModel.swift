//
//  FirestoreMessagingViewModel.swift
//  Zenlyne
//
//  Created by admin on 6/5/25.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

class MessagingViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var messages: [Message] = []
    @Published var chats: [Chat] = []
    @Published var chatUsers: [String: User] = [:]
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    @Published var newMessageText: String = ""
    @Published var totalUnreadCount: Int = 0
    
    // MARK: - Private Properties
    
    private let chatService = FirebaseChatService()
    private let firestore = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Init & Deinit
    
    init() {
        setupPublishers()
    }
    
    deinit {
        chatService.removeAllObservers()
    }
    
    // MARK: - Setup
    
    private func setupPublishers() {
        // You could add Combine publishers here if needed
    }
    
    // MARK: - Public Methods
    
    /// Loads all chats for the current user with real-time updates
    func loadChats() {
        isLoading = true
        
        chatService.getUserChats { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let chats):
                    self.chats = chats
                    self.loadUsersForChats(chats)
                    self.updateTotalUnreadCount()
                case .failure(let error):
                    self.errorMessage = "Không thể tải danh sách trò chuyện: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// Loads all messages for a specific chat with a user
    func loadMessages(forChatWithUser userId: String) {
        isLoading = true
        
        chatService.getMessages(with: userId) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let messages):
                    self.messages = messages
                case .failure(let error):
                    self.errorMessage = "Không thể tải tin nhắn: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// Sends a new message to a user
    func sendMessage(to userId: String, completion: @escaping (Bool) -> Void = { _ in }) {
        guard !newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(false)
            return
        }
        
        let messageContent = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        chatService.sendMessage(to: userId, content: messageContent) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let message):
                    // Add the new message to the list if we're in a chat view
                    if let index = self.messages.firstIndex(where: { $0.id == message.id }) {
                        // Message already exists (from real-time update)
                    } else {
                        self.messages.append(message)
                    }
                    self.newMessageText = ""
                    completion(true)
                case .failure(let error):
                    self.errorMessage = "Không thể gửi tin nhắn: \(error.localizedDescription)"
                    completion(false)
                }
            }
        }
    }
    
    /// Creates a new chat with a user if it doesn't exist
    func createChatIfNeeded(with userId: String, completion: @escaping (Bool) -> Void = { _ in }) {
        chatService.createChatIfNeeded(with: userId) { result in
            switch result {
            case .success(_):
                completion(true)
            case .failure(_):
                completion(false)
            }
        }
    }
    
    /// Retrieves the total count of unread messages
    func updateTotalUnreadCount() {
        chatService.getTotalUnreadMessagesCount { [weak self] count in
            DispatchQueue.main.async {
                self?.totalUnreadCount = count
            }
        }
    }
    
    /// Deletes a chat from the user's list
    func deleteChat(chatId: String, completion: @escaping (Bool) -> Void = { _ in }) {
        chatService.deleteChat(chatId: chatId) { [weak self] success in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if success {
                    // Remove from local list
                    self.chats.removeAll { $0.id == chatId }
                    completion(true)
                } else {
                    self.errorMessage = "Không thể xóa cuộc trò chuyện"
                    completion(false)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Loads user information for each chat
    private func loadUsersForChats(_ chats: [Chat]) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        let userIds = Set(chats.compactMap { $0.getOtherParticipantId(currentUserId: currentUserId) })
        
        for userId in userIds {
            loadUserInfo(userId: userId)
        }
    }
    
    /// Loads information for a specific user from Firestore
    private func loadUserInfo(userId: String) {
        firestore.collection("users").document(userId).getDocument { [weak self] snapshot, error in
            guard let self = self,
                  let document = snapshot,
                  let data = document.data(),
                  let fullName = data["fullName"] as? String,
                  let email = data["email"] as? String else {
                return
            }
            
            DispatchQueue.main.async {
                var user = User(id: userId, fullName: fullName, email: email)
                user.profileImageUrl = data["profileImageUrl"] as? String
                user.isOnline = data["isOnline"] as? Bool ?? false
                
                if let lastSeenTimestamp = data["lastSeen"] as? Timestamp {
                    user.lastSeen = lastSeenTimestamp.dateValue()
                }
                
                self.chatUsers[userId] = user
            }
        }
    }
    
    /// Gets a chat by its ID
    func getChat(forId chatId: String) -> Chat? {
        return chats.first { $0.id == chatId }
    }
    
    /// Gets a user by their ID
    func getUser(forId userId: String, completion: @escaping (User?) -> Void) {
        if let user = chatUsers[userId] {
            completion(user)
            return
        }
        
        loadUserInfo(userId: userId)
        
        // Try to find the user after a short delay to allow loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            completion(self?.chatUsers[userId])
        }
    }
    
    /// Gets the other user in a chat
    func getOtherUser(in chat: Chat) -> User? {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let otherUserId = chat.getOtherParticipantId(currentUserId: currentUserId) else {
            return nil
        }
        
        return chatUsers[otherUserId]
    }
}
