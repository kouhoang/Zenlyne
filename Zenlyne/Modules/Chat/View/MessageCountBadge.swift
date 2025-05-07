//
//  MessageCountBadge.swift
//  Zenlyne
//
//  Created by admin on 6/5/25.
//

import SwiftUI
import FirebaseAuth

// This struct is specifically designed to be used directly in the MapViewController
struct MessageCountBadge: View {
    @StateObject private var viewModel = MessagingViewModel()
    @State private var showingBadge = false
    @State private var showConversationList = false
    
    var body: some View {
        Button(action: {
            showConversationList = true
        }) {
            ZStack {
                Image(systemName: "message.fill")
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
        }
        .fullScreenCover(isPresented: $showConversationList) {
            ConversationListView()
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

// This view solves the issue with ChatButtonView functionality in the friend info panel
struct ChatButtonView: View {
    let friend: User
    @State private var showChatView = false
    
    var body: some View {
        Button(action: {
            showChatView = true
        }) {
            VStack(spacing: 4) {
                Image(systemName: "message.fill")
                    .font(.system(size: 20))
                Text("Nhắn tin")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.blue)
        }
        .fullScreenCover(isPresented: $showChatView) {
            // Directly open chat with this friend
            createChatView(with: friend)
        }
    }
    
    private func createChatView(with friend: User) -> some View {
        let viewModel = MessagingViewModel()
        // Preload the friend info
        viewModel.chatUsers[friend.id] = friend
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return AnyView(Text("Error: User not logged in"))
        }
        
        let chatId = [currentUserId, friend.id].sorted().joined(separator: "_")
        
        // Create a navigation view with the chat view
        return AnyView(
            ChatView(
                viewModel: viewModel,
                chatId: chatId,
                otherUserId: friend.id
            )
        )
    }
}

// Extension to integrate messaging functionality in MapViewController
extension MapViewController {
    // Method to show the conversation list
    func showConversationList() -> some View {
        return AnyView(
            ConversationListView()
        )
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
