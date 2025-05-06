//
//  FirebaseChatManager.swift
//  Zenlyne
//
//  Created by admin on 6/5/25.
//

import Foundation
import SwiftUI
import FirebaseAuth

// A globally accessible class to handle chat functionality across the app
class FirebaseChatManager {
    // Singleton instance
    static let shared = FirebaseChatManager()
    
    // Service
    let chatService = FirebaseChatService()
    
    private init() {}
    
    // MARK: - Helper Methods
    
    // Get a shared or new messaging view model
    func getMessagingViewModel() -> MessagingViewModel {
        return MessagingViewModel()
    }
    
    // Create a chat view for a specific user
    func createChatView(with user: User) -> some View {
        let viewModel = getMessagingViewModel()
        
        // Preload user info
        viewModel.chatUsers[user.id] = user
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return AnyView(Text("Error: User not logged in"))
        }
        
        let chatId = [currentUserId, user.id].sorted().joined(separator: "_")
        
        // Create chat if needed
        chatService.createChatIfNeeded(with: user.id) { _ in }
        
        return AnyView(
            NavigationView {
                ChatView(
                    viewModel: viewModel,
                    chatId: chatId,
                    otherUserId: user.id
                )
            }
        )
    }
    
    // Create a conversation list view
    func createConversationListView() -> some View {
        return AnyView(ConversationListView())
    }
    
    // Get the total number of unread messages
    func getTotalUnreadCount(completion: @escaping (Int) -> Void) {
        chatService.getTotalUnreadMessagesCount(completion: completion)
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
