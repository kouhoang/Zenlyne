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
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if viewModel.isLoading && viewModel.messages.isEmpty {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Spacer()
                    } else {
                        // Messages list
                        ScrollViewReader { scrollView in
                            ScrollView {
                                LazyVStack(spacing: 12) {
                                    ForEach(viewModel.messages) { message in
                                        MessageRow(message: message, otherUser: otherUser)
                                            .id(message.id)
                                    }
                                    
                                    // Invisible spacer for auto-scrolling
                                    Color.clear
                                        .frame(height: 1)
                                        .id("bottom")
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, 8)
                            }
                            .onChange(of: viewModel.messages.count) { _ in
                                withAnimation(.easeOut(duration: 0.3)) {
                                    scrollView.scrollTo("bottom", anchor: .bottom)
                                }
                            }
                            .onChange(of: scrollToBottom) { _ in
                                withAnimation(.easeOut(duration: 0.3)) {
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
                        HStack(spacing: 12) {
                            // Message text field container
                            HStack(spacing: 8) {
                                TextField("Gửi tin nhắn...", text: $viewModel.newMessageText, axis: .vertical)
                                    .focused($isInputFocused)
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(24)
                                    .lineLimit(1...4)
                            }
                            
                            // Send button
                            Button(action: sendMessage) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        Circle()
                                            .fill(viewModel.newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
                                                  Color.gray : Color.blue)
                                    )
                            }
                            .disabled(viewModel.newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.black)
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
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
            // Back button
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            .padding(.leading, 4)
            
            // User avatar
            Button(action: onProfileTap) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 40)
                    
                    if let profileImage = user?.profileImageUrl {
                        AsyncImage(url: URL(string: profileImage)) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Text(user?.initials ?? "")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    } else {
                        Text(user?.initials ?? "")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                }
            }
            
            // User info
            VStack(alignment: .leading, spacing: 2) {
                Text(user?.fullName ?? "Chat")
                    .font(.headline)
                    .foregroundColor(.white)
                
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
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(90))
            }
            .padding(.trailing, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black)
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
        HStack(alignment: .bottom, spacing: 8) {
            if isFromCurrentUser {
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    // Message bubble for current user
                    HStack {
                        Spacer()
                        Text(message.content)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray4))
                            .foregroundColor(.black)
                            .cornerRadius(20, corners: [.topLeft, .topRight, .bottomLeft])
                            .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: .trailing)
                    }
                    
                    // Timestamp
                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .padding(.trailing, 8)
                }
            } else {
                // Avatar for other user's messages
                ChatAvatarView(user: otherUser, size: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Message bubble for other user
                    Text(message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray))
                        .foregroundColor(.white)
                        .cornerRadius(20, corners: [.topLeft, .topRight, .bottomRight])
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: .leading)
                    
                    // Timestamp
                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .padding(.leading, 8)
                }
                
                Spacer()
            }
        }
    }
}

// Extension for corner radius
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

struct FriendProfileView: View {
    let user: User
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.gray)
                        .padding()
                }
                
                // Main content
                VStack(spacing: 20) {
                    // Profile Image
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 120)
                        
                        if let profileImage = user.profileImageUrl {
                            AsyncImage(url: URL(string: profileImage)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Text(user.initials)
                                    .font(.title)
                                    .foregroundColor(.white)
                            }
                            .frame(width: 116, height: 116)
                            .clipShape(Circle())
                        } else {
                            Text(user.initials)
                                .font(.title)
                                .foregroundColor(.white)
                        }
                        
                        // Online status
                        if user.isOnline {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(Color.black, lineWidth: 2)
                                )
                                .position(x: 100, y: 100)
                        }
                    }
                    .padding(.top, 40)
                    
                    // User Info
                    Text(user.fullName)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
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
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ChatView(
        viewModel: MessagingViewModel(),
        chatId: "test_chat_id",
        otherUserId: "test_user_id"
    )
    .preferredColorScheme(.dark)
}
