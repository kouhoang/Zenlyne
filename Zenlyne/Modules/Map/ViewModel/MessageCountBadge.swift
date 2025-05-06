//
//  MessageCountBadge.swift
//  Zenlyne
//
//  Created by admin on 26/4/25.
//

import SwiftUI
import FirebaseAuth

// Extension to integrate messaging functionality in MapViewController
extension MapViewController {
    // Method to show the conversation list
    func showConversationList() -> some View {
        ConversationListView()
    }
    
    // Method to show a chat with a specific friend
    func showChatWithFriend(_ friend: User) -> some View {
        let messagingViewModel = MessagingViewModel()
        
        // Pre-load the friend info to avoid delay
        messagingViewModel.chatUsers[friend.id] = friend
        
        // Create chat if needed
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return AnyView(Text("Error: User not logged in"))
        }
        
        let chatId = [currentUserId, friend.id].sorted().joined(separator: "_")
        
        return AnyView(
            ChatView(
                viewModel: messagingViewModel,
                chatId: chatId,
                otherUserId: friend.id
            )
        )
    }
}

// Update FriendInfoPanel to include messaging functionality
extension UpdatedFriendInfoPanel {
    // Modified button actions
    func messageAction() {
        // Show chat with friend
        let friendId = friend.id
        
        // Go to chat view
        if let window = UIApplication.shared.windows.first,
           let rootViewController = window.rootViewController {
            
            let messagingViewModel = MessagingViewModel()
            messagingViewModel.chatUsers[friendId] = friend
            
            // Create chat if it doesn't exist
            messagingViewModel.createChatIfNeeded(with: friendId)
            
            let chatId = [Auth.auth().currentUser?.uid, friendId].compactMap { $0 }.sorted().joined(separator: "_")
            
            let chatView = ChatView(
                viewModel: messagingViewModel,
                chatId: chatId,
                otherUserId: friendId
            )
            
            let hostingController = UIHostingController(rootView: 
                NavigationView {
                    chatView
                }
            )
            
            rootViewController.present(hostingController, animated: true)
        }
    }
}

// Badge to show unread message count
struct MessageCountBadge: View {
    @ObservedObject private var viewModel = MessagingViewModel()
    @State private var showingBadge = false
    
    var body: some View {
        ZStack {
            Image(systemName: "envelope.fill")
                .font(.system(size: 40))
                .foregroundColor(.purple)
                .background(Color.white.clipShape(Circle()))
                .shadow(radius: 4)
            
            if viewModel.totalUnreadCount > 0 {
                Text("\(viewModel.totalUnreadCount)")
                    .font(.caption)
                    .padding(5)
                    .foregroundColor(.white)
                    .background(Color.red)
                    .clipShape(Circle())
                    .offset(x: 15, y: -15)
                    .opacity(showingBadge ? 1 : 0)
                    .animation(.easeInOut, value: showingBadge)
            }
        }
        .onAppear {
            viewModel.updateTotalUnreadCount()
            
            // Add a small delay so the animation is visible
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingBadge = true
            }
            
            // Set up a timer to refresh unread count periodically
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                viewModel.updateTotalUnreadCount()
            }
        }
    }
}
