//
//  FirebaseChatManager.swift
//  Zenlyne
//
//  Created by admin on 6/5/25.
//

import Foundation
import SwiftUI
import FirebaseAuth
import Combine

class FirebaseChatManager: ObservableObject {
    static let shared = FirebaseChatManager()
    
    @Published var totalUnreadCount: Int = 0
    
    private let chatService: ChatServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    private init(chatService: ChatServiceProtocol = FirebaseChatService()) {
        self.chatService = chatService
        setupUnreadCountMonitoring()
    }
    
    private func setupUnreadCountMonitoring() {
        // Monitor unread count every 30 seconds
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateUnreadCount()
            }
            .store(in: &cancellables)
        
        // Initial load
        updateUnreadCount()
    }
    
    private func updateUnreadCount() {
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
    
    // MARK: - Public Methods
    
    func createChatView(with user: User) -> some View {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return AnyView(Text("Error: User not logged in"))
        }
        
        let chatId = [currentUserId, user.id].sorted().joined(separator: "_")
        
        return AnyView(
            NavigationView {
                ChatView(chatId: chatId, otherUserId: user.id)
            }
        )
    }
    
    func createConversationListView() -> some View {
        return AnyView(ConversationListView())
    }
    
    func refreshUnreadCount() {
        updateUnreadCount()
    }
}

// Extension to help with starting chats from anywhere in the app
extension View {
    func openChatWith(_ user: User) -> some View {
        let manager = FirebaseChatManager.shared
        return NavigationLink(destination: manager.createChatView(with: user)) {
            self
        }
    }
}
