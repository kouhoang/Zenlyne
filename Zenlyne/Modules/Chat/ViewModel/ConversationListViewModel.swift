//
//  ConversationListViewModel.swift
//  Zenlyne
//
//  Created by admin on 2/6/25.
//

import Foundation
import Combine
import FirebaseAuth

class ConversationListViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var chats: [Chat] = []
    @Published var chatUsers: [String: User] = [:]
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    @Published var totalUnreadCount: Int = 0
    
    // MARK: - Private Properties
    
    private let chatService: ChatServiceProtocol
    private let userService: UserServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
    var filteredChats: [Chat] {
        if searchText.isEmpty {
            return chats
        } else {
            return chats.filter { chat in
                guard let otherUserId = chat.getOtherParticipantId(currentUserId: Auth.auth().currentUser?.uid ?? ""),
                      let user = chatUsers[otherUserId] else {
                    return false
                }
                
                return user.fullName.localizedCaseInsensitiveContains(searchText) ||
                       user.email.localizedCaseInsensitiveContains(searchText) ||
                       (chat.lastMessage?.content.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
    
    // MARK: - Initialization
    
    init(chatService: ChatServiceProtocol = FirebaseChatService(), userService: UserServiceProtocol = UserService()) {
        self.chatService = chatService
        self.userService = userService
        
        setupBindings()
        loadChats()
        updateTotalUnreadCount()
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Auto-clear error message after 5 seconds
        $errorMessage
            .compactMap { $0.isEmpty ? nil : $0 }
            .delay(for: .seconds(5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.errorMessage = ""
            }
            .store(in: &cancellables)
        
        // Update user info when chats change
        $chats
            .sink { [weak self] chats in
                self?.loadUsersForChats(chats)
            }
            .store(in: &cancellables)
    }
    
    private func loadUsersForChats(_ chats: [Chat]) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        let userIds = Set(chats.compactMap { $0.getOtherParticipantId(currentUserId: currentUserId) })
        
        for userId in userIds {
            if chatUsers[userId] == nil {
                loadUserInfo(userId: userId)
            }
        }
    }
    
    private func loadUserInfo(userId: String) {
        userService.getUser(by: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] user in
                    self?.chatUsers[userId] = user
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    func loadChats() {
        isLoading = true
        
        chatService.getUserChats()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Không thể tải danh sách trò chuyện: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] chats in
                    self?.chats = chats
                    self?.updateTotalUnreadCount()
                }
            )
            .store(in: &cancellables)
    }
    
    func deleteChat(_ chat: Chat) {
        chatService.deleteChat(chatId: chat.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Không thể xóa cuộc trò chuyện: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] success in
                    if success {
                        self?.chats.removeAll { $0.id == chat.id }
                        self?.updateTotalUnreadCount()
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func updateTotalUnreadCount() {
        chatService.getTotalUnreadMessagesCount()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] count in
                    self?.totalUnreadCount = count
                }
            )
            .store(in: &cancellables)
    }
    
    func getOtherUser(in chat: Chat) -> User? {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let otherUserId = chat.getOtherParticipantId(currentUserId: currentUserId) else {
            return nil
        }
        
        return chatUsers[otherUserId]
    }
    
    func createChatIfNeeded(with userId: String, completion: @escaping (Bool) -> Void) {
        chatService.createChatIfNeeded(with: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completionResult in
                    if case .failure(_) = completionResult {
                        completion(false)
                    }
                },
                receiveValue: { _ in
                    completion(true)
                }
            )
            .store(in: &cancellables)
    }
    
    func refreshChats() {
        loadChats()
    }
}
