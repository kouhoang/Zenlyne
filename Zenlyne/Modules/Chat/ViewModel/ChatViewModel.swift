//
//  ChatViewModel.swift
//  Zenlyne
//
//  Created by admin on 2/6/25.
//


import Foundation
import Combine
import FirebaseAuth

class ChatViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var messages: [Message] = []
    @Published var newMessageText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    @Published var otherUser: User?
    
    // MARK: - Private Properties
    
    private let chatService: ChatServiceProtocol
    private let userService: UserServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    private let chatId: String
    private let otherUserId: String
    
    // MARK: - Computed Properties
    
    var canSendMessage: Bool {
        !newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Initialization
    
    init(chatId: String, otherUserId: String, chatService: ChatServiceProtocol = FirebaseChatService(), userService: UserServiceProtocol = UserService()) {
        self.chatId = chatId
        self.otherUserId = otherUserId
        self.chatService = chatService
        self.userService = userService
        
        setupBindings()
        loadData()
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
    }
    
    private func loadData() {
        loadOtherUser()
        loadMessages()
    }
    
    private func loadOtherUser() {
        userService.getUser(by: otherUserId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Không thể tải thông tin người dùng: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] user in
                    self?.otherUser = user
                }
            )
            .store(in: &cancellables)
    }
    
    private func loadMessages() {
        isLoading = true
        
        chatService.getMessages(with: otherUserId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Không thể tải tin nhắn: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] messages in
                    self?.messages = messages
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    func sendMessage() {
        guard canSendMessage else { return }
        
        let messageContent = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        newMessageText = ""
        
        chatService.sendMessage(to: otherUserId, content: messageContent)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Không thể gửi tin nhắn: \(error.localizedDescription)"
                        // Restore message text on failure
                        self?.newMessageText = messageContent
                    }
                },
                receiveValue: { [weak self] message in
                    // Message will be added via real-time listener
                    // But we can add it immediately for better UX
                    if let index = self?.messages.firstIndex(where: { $0.id == message.id }) {
                        self?.messages[index] = message
                    } else {
                        self?.messages.append(message)
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func isMessageFromCurrentUser(_ message: Message) -> Bool {
        return message.senderId == Auth.auth().currentUser?.uid
    }
    
    func refreshMessages() {
        loadMessages()
    }
}

extension Array where Element == Message {
    func groupedByDate() -> [(Date, [Message])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: self) { message in
            calendar.startOfDay(for: message.timestamp)
        }
        
        return grouped.sorted { $0.key < $1.key }
    }
}

extension Message {
    func shouldShowTime(in messages: [Message]) -> Bool {
        guard let messageIndex = messages.firstIndex(where: { $0.id == self.id }) else {
            return true
        }
        
        if messageIndex == messages.count - 1 {
            return true
        }
        
        let nextMessage = messages[messageIndex + 1]
        
        if nextMessage.senderId != self.senderId {
            return true
        }
        
        let timeDifference = nextMessage.timestamp.timeIntervalSince(self.timestamp)
        return timeDifference > 300 // 5 minutes
    }
}
