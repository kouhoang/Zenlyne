//
//  ChatView.swift
//  Zenlyne
//
//  Created by admin on 6/5/25.
//  Updated to better support sheet presentation

import SwiftUI
import FirebaseAuth

struct ChatView: View {
    @ObservedObject var viewModel: MessagingViewModel
    let chatId: String
    let otherUserId: String?
    
    @State private var showingProfile = false
    @State private var scrollToBottom = false
    @FocusState private var isInputFocused: Bool
    
    @Environment(\.presentationMode) var presentationMode
    
    init(viewModel: MessagingViewModel, chatId: String, otherUserId: String?) {
        self.viewModel = viewModel
        self.chatId = chatId
        self.otherUserId = otherUserId
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom header
            ChatHeaderView(
                user: otherUser,
                onDismiss: { presentationMode.wrappedValue.dismiss() },
                onProfileTap: { showingProfile = true }
            )
            
            ZStack {
                // Background
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if viewModel.isLoading && viewModel.messages.isEmpty {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                        Spacer()
                    } else {
                        // Messages list
                        ScrollViewReader { scrollView in
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    ForEach(viewModel.messages) { message in
                                        MessageRow(message: message, otherUser: otherUser)
                                            .id(message.id)
                                    }
                                    
                                    // Invisible spacer for auto-scrolling
                                    Color.clear
                                        .frame(height: 1)
                                        .id("bottom")
                                }
                                .padding(.horizontal)
                                .padding(.top, 8)
                            }
                            .onChange(of: viewModel.messages.count) { _ in
                                withAnimation {
                                    scrollView.scrollTo("bottom", anchor: .bottom)
                                }
                            }
                            .onChange(of: scrollToBottom) { _ in
                                withAnimation {
                                    scrollView.scrollTo("bottom", anchor: .bottom)
                                }
                            }
                            .onAppear {
                                // Auto-scroll to bottom after a short delay to ensure view is loaded
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    scrollToBottom.toggle()
                                }
                            }
                        }
                        
                        // Message input bar
                        HStack(spacing: 8) {
                            // Message text field
                            ZStack {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color(.systemBackground))
                                
                                TextEditor(text: $viewModel.newMessageText)
                                    .focused($isInputFocused)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.clear)
                                    .frame(minHeight: 40)
                            }
                            .frame(minHeight: 40, maxHeight: 120)
                            
                            // Send button
                            Button(action: sendMessage) {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "arrow.up")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                            }
                            .disabled(viewModel.newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color(.systemBackground))
                    }
                }
            }
        }
        .onAppear {
            if let otherUserId = otherUserId {
                // Start real-time message loading
                viewModel.loadMessages(forChatWithUser: otherUserId)
            }
        }
        .sheet(isPresented: $showingProfile) {
            if let user = otherUser {
                FriendProfileView(user: user)
            }
        }
    }
    
    private var otherUser: User? {
        guard let otherUserId = otherUserId else { return nil }
        return viewModel.chatUsers[otherUserId]
    }
    
    private func sendMessage() {
        guard let otherUserId = otherUserId else { return }
        
        // Send message with animation
        withAnimation {
            viewModel.sendMessage(to: otherUserId) { success in
                if success {
                    // Auto-scroll to bottom after sending
                    scrollToBottom.toggle()
                }
            }
        }
    }
}

// Custom chat header view
struct ChatHeaderView: View {
    let user: User?
    let onDismiss: () -> Void
    let onProfileTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Close button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
            .padding(.leading, 8)
            
            // User avatar
            Button(action: onProfileTap) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 36, height: 36)
                    
                    if let profileImage = user?.profileImageUrl {
                        AsyncImage(url: URL(string: profileImage)) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Text(user?.initials ?? "")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                    } else {
                        Text(user?.initials ?? "")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    // Online status dot
                    if let isOnline = user?.isOnline, isOnline {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 1)
                            )
                            .position(x: 26, y: 26)
                    }
                }
            }
            
            // User info
            VStack(alignment: .leading, spacing: 2) {
                Text(user?.fullName ?? "Chat")
                    .font(.headline)
                
                if let user = user {
                    if user.isOnline {
                        Text("Đang hoạt động")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else if let lastSeen = user.lastSeen {
                        Text("Hoạt động \(formatRelativeTime(lastSeen))")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .onTapGesture {
                onProfileTap()
            }
            
            Spacer()
            
            // Options button
            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundColor(.gray)
                    .rotationEffect(.degrees(90))
            }
            .padding(.trailing, 12)
        }
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
    }
    
    // Helper method to format the relative time
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct MessageRow: View {
    let message: Message
    let otherUser: User?
    
    private var isFromCurrentUser: Bool {
        return message.senderId == Auth.auth().currentUser?.uid
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var body: some View {
        HStack {
            if isFromCurrentUser {
                Spacer()
            } else {
                // Avatar for other user's messages
                AvatarView(user: otherUser)
                    .frame(width: 30, height: 30)
            }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 2) {
                // Message bubble
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isFromCurrentUser ? Color.blue : Color(.systemGray5))
                    .foregroundColor(isFromCurrentUser ? .white : .primary)
                    .cornerRadius(16)
                
                // Timestamp
                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 4)
            }
            
            if !isFromCurrentUser {
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

//struct AvatarView: View {
//    let user: User?
//    
//    var body: some View {
//        ZStack {
//            Circle()
//                .fill(Color.blue.opacity(0.2))
//            
//            if let profileImage = user?.profileImageUrl {
//                AsyncImage(url: URL(string: profileImage)) { image in
//                    image
//                        .resizable()
//                        .scaledToFill()
//                } placeholder: {
//                    Text(user?.initials ?? "?")
//                        .font(.caption)
//                        .foregroundColor(.blue)
//                }
//                .clipShape(Circle())
//            } else {
//                Text(user?.initials ?? "?")
//                    .font(.caption)
//                    .foregroundColor(.blue)
//            }
//            
//            // Online status indicator
//            if let isOnline = user?.isOnline, isOnline {
//                Circle()
//                    .fill(Color.green)
//                    .frame(width: 8, height: 8)
//                    .overlay(
//                        Circle()
//                            .stroke(Color.white, lineWidth: 1)
//                    )
//                    .position(x: 22, y: 22)
//            }
//        }
//    }
//}

struct FriendProfileView: View {
    let user: User
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .topTrailing) {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.gray)
                        .padding()
                }
                
                // Main
                VStack(spacing: 20) {
                    // Profile Image
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 120, height: 120)
                        
                        if let profileImage = user.profileImageUrl {
                            AsyncImage(url: URL(string: profileImage)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Text(user.initials)
                                    .font(.title)
                                    .foregroundColor(.blue)
                            }
                            .frame(width: 116, height: 116)
                            .clipShape(Circle())
                        } else {
                            Text(user.initials)
                                .font(.title)
                                .foregroundColor(.blue)
                        }
                        
                        // Online status
                        if user.isOnline {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                )
                                .position(x: 100, y: 100)
                        }
                    }
                    .padding(.top, 40)
                    
                    // User Info
                    Text(user.fullName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    if user.isOnline {
                        Text("Đang hoạt động")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    } else if let lastSeen = user.lastSeen {
                        let formatter = RelativeDateTimeFormatter()
                        Text("Hoạt động \(formatter.localizedString(for: lastSeen, relativeTo: Date()))")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    Text(user.email)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Thông tin bạn bè")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    ChatView(
        viewModel: MessagingViewModel(),
        chatId: "test_chat_id",
        otherUserId: "test_user_id"
    )
}
