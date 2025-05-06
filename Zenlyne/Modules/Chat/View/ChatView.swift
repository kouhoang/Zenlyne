//
//  ChatView.swift
//  Zenlyne
//
//  Created by admin on 26/4/25.
//

import SwiftUI
import FirebaseAuth

struct ChatView: View {
    @ObservedObject var viewModel: MessagingViewModel
    let chatId: String
    let otherUserId: String?
    
    @State private var showingProfile = false
    @State private var scrollToBottom = false
    @FocusState private var isInputFocused: Bool
    
    @Environment(\.presentationMode) var presentationMode // Để đóng view
    
    init(viewModel: MessagingViewModel, chatId: String, otherUserId: String?) {
        self.viewModel = viewModel
        self.chatId = chatId
        self.otherUserId = otherUserId
    }
    
    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground).ignoresSafeArea()
            
            VStack(spacing: 0) {
                if viewModel.isLoading && viewModel.messages.isEmpty {
                    Spacer()
                    ProgressView()
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
        .navigationTitle(otherUser?.fullName ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.gray)
                }
            }

            // Show friend profile
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingProfile = true
                }) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(otherUser?.isOnline ?? false ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        
                        Text(otherUser?.isOnline ?? false ? "Đang hoạt động" : "Không hoạt động")
                            .font(.caption)
                            .foregroundColor(otherUser?.isOnline ?? false ? .green : .gray)
                    }
                }
            }
        }
        .onAppear {
            if let otherUserId = otherUserId {
                viewModel.loadMessages(forChatWithUser: otherUserId)
            }
        }
        .sheet(isPresented: $showingProfile) {
            Group {
                if let user = otherUser {
                    FriendProfileView(user: user)
                } else {
                    EmptyView()
                }
            }
        }
    }
    
    private var otherUser: User? {
        guard let otherUserId = otherUserId else { return nil }
        return viewModel.chatUsers[otherUserId]
    }
    
    private func sendMessage() {
        guard let otherUserId = otherUserId else { return }
        viewModel.sendMessage(to: otherUserId)
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
                if !isFromCurrentUser {
                    AvatarView(user: otherUser)
                        .frame(width: 30, height: 30)
                }
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

struct AvatarView: View {
    let user: User?
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.2))
            
            if let profileImage = user?.profileImageUrl {
                AsyncImage(url: URL(string: profileImage)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Text(user?.initials ?? "?")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .clipShape(Circle())
            } else {
                Text(user?.initials ?? "?")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            // Online status indicator
            if let isOnline = user?.isOnline, isOnline {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 1)
                    )
                    .position(x: 22, y: 22)
            }
        }
    }
}

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
//                        formatter.unitsStyle = .full
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
