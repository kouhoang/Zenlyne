//
//  ChatButtonView.swift
//  Zenlyne
//
//  Created by admin on 6/5/25.
//

import SwiftUI
import FirebaseAuth

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
        }
        .fullScreenCover(isPresented: $showChatView) {
            // Using the navigation view and passing the chat view directly
            NavigationView {
                ChatViewContainer(friend: friend)
            }
        }
    }
}

// Helper view to contain the ChatView and avoid the View conformance issues
struct ChatViewContainer: View {
    let friend: User
    
    var body: some View {
        let viewModel = MessagingViewModel()
        // Pre-load the friend
        viewModel.chatUsers[friend.id] = friend
        
        let chatId = [Auth.auth().currentUser?.uid ?? "", friend.id].sorted().joined(separator: "_")
        
        return ChatView(
            viewModel: viewModel,
            chatId: chatId,
            otherUserId: friend.id
        )
    }
}
