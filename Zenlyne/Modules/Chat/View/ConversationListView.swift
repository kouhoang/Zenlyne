//
//  ConversationListView.swift
//  Zenlyne
//
//  Created by admin on 26/4/25.
//

import SwiftUI
import FirebaseAuth

struct ConversationListView: View {
    @ObservedObject var viewModel = MessagingViewModel()
    @Environment(\.presentationMode) var presentationMode
    @State private var showNewMessageSheet = false
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(.systemBackground).ignoresSafeArea()
                
                // Content
                VStack {
                    // List of conversations
                    if viewModel.chats.isEmpty && !viewModel.isLoading {
                        emptyStateView
                    } else {
                        conversationsList
                    }
                }
                .navigationTitle("Tin Nhắn")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Image(systemName: "arrow.left")
                                .foregroundColor(.blue)
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showNewMessageSheet = true
                        }) {
                            Image(systemName: "square.and.pencil")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .overlay(
                Group {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                }
            )
            .onAppear {
                viewModel.loadChats()
            }
            .sheet(isPresented: $showNewMessageSheet) {
                NewMessageView(onSelectUser: { user in
                    showNewMessageSheet = false
                    openChatWithUser(user)
                })
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "message.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue.opacity(0.5))
            
            Text("Không có tin nhắn nào")
                .font(.headline)
            
            Text("Bắt đầu cuộc trò chuyện bằng cách chạm vào biểu tượng bút chì ở trên cùng")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: {
                showNewMessageSheet = true
            }) {
                Text("Tin nhắn mới")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 30)
                    .background(Color.blue)
                    .cornerRadius(20)
            }
            .padding(.top, 20)
        }
        .padding()
    }
    
    private var conversationsList: some View {
        List {
            ForEach(filteredChats) { chat in
                NavigationLink(destination: ChatView(viewModel: viewModel, chatId: chat.id, otherUserId: chat.getOtherParticipantId(currentUserId: Auth.auth().currentUser?.uid ?? ""))) {
                    ConversationRowView(
                        chat: chat,
                        user: viewModel.getOtherUser(in: chat)
                    )
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        viewModel.deleteChat(chatId: chat.id) { _ in
                            // Success/error handling could go here
                        }
                    } label: {
                        Label("Xóa", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
        .refreshable {
            viewModel.loadChats()
        }
        .searchable(text: $searchText, prompt: "Tìm kiếm")
    }
    
    // Filtered chats based on search text
    private var filteredChats: [Chat] {
        if searchText.isEmpty {
            return viewModel.chats
        } else {
            return viewModel.chats.filter { chat in
                guard let otherUserId = chat.getOtherParticipantId(currentUserId: Auth.auth().currentUser?.uid ?? ""),
                      let user = viewModel.chatUsers[otherUserId] else {
                    return false
                }
                
                return user.fullName.localizedCaseInsensitiveContains(searchText) ||
                       user.email.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    // Helper function to open a chat with a user
    private func openChatWithUser(_ user: User) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        let chatId = [currentUserId, user.id].sorted().joined(separator: "_")
        
        // Create chat if needed
        viewModel.createChatIfNeeded(with: user.id) { success in
            if success {
                // Add the user to chatUsers if not already there
                if viewModel.chatUsers[user.id] == nil {
                    viewModel.chatUsers[user.id] = user
                }
                
                // Navigate to the chat
                if let index = viewModel.chats.firstIndex(where: { $0.id == chatId }) {
                    // Chat already exists
                } else {
                    // Create new chat entry
                    let newChat = Chat(
                        participants: [currentUserId, user.id],
                        lastMessage: nil,
                        unreadCount: 0
                    )
                    viewModel.chats.insert(newChat, at: 0)
                }
            }
        }
    }
}

// Individual conversation row
struct ConversationRowView: View {
    let chat: Chat
    let user: User?
    
    // Format time relative to now
    private func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "" }
        
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            // Today, just show time
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            // Yesterday
            return "Hôm qua"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            // This week, show day name
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Day name
            return formatter.string(from: date)
        } else {
            // Show date
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yyyy"
            return formatter.string(from: date)
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile Photo
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                if let profileImage = user?.profileImageUrl {
                    AsyncImage(url: URL(string: profileImage)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Text(user?.initials ?? "?")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                } else {
                    Text(user?.initials ?? "?")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                
                // Online status indicator
                if let isOnline = user?.isOnline, isOnline {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .position(x: 48, y: 48)
                }
            }
            
            // Contact info and message preview
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(user?.fullName ?? "Người dùng")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(formatTime(chat.lastMessage?.timestamp))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                HStack {
                    if let lastMessage = chat.lastMessage {
                        // Truncate message preview if too long
                        Text(lastMessage.content.count > 30 ? 
                             String(lastMessage.content.prefix(30)) + "..." : 
                             lastMessage.content)
                            .font(.subheadline)
                            .foregroundColor(chat.unreadCount > 0 ? .primary : .gray)
                            .lineLimit(1)
                    } else {
                        Text("Bắt đầu trò chuyện")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .italic()
                    }
                    
                    Spacer()
                    
                    // Unread message indicator
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.caption)
                            .bold()
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .frame(height: 70)
    }
}

// View to select a new message recipient
struct NewMessageView: View {
    @State private var searchText = ""
    @State private var friends: [User] = []
    @State private var isLoading = false
    @Environment(\.presentationMode) var presentationMode
    
    let onSelectUser: (User) -> Void
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle())
                } else if friends.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        
                        Text("Không có bạn bè nào")
                            .font(.headline)
                        
                        Text("Thêm bạn bè trước khi bắt đầu cuộc trò chuyện")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(filteredFriends) { friend in
                            Button(action: {
                                onSelectUser(friend)
                            }) {
                                HStack {
                                    // Profile image
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue.opacity(0.2))
                                            .frame(width: 50, height: 50)
                                        
                                        if let profileImage = friend.profileImageUrl {
                                            AsyncImage(url: URL(string: profileImage)) { image in
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                            } placeholder: {
                                                Text(friend.initials)
                                                    .font(.title3)
                                                    .foregroundColor(.blue)
                                            }
                                            .frame(width: 46, height: 46)
                                            .clipShape(Circle())
                                        } else {
                                            Text(friend.initials)
                                                .font(.title3)
                                                .foregroundColor(.blue)
                                        }
                                        
                                        // Online status indicator
                                        if friend.isOnline {
                                            Circle()
                                                .fill(Color.green)
                                                .frame(width: 12, height: 12)
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color.white, lineWidth: 2)
                                                )
                                                .position(x: 40, y: 40)
                                        }
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(friend.fullName)
                                            .font(.headline)
                                        
                                        Text(friend.isOnline ? "Đang hoạt động" : "Không hoạt động")
                                            .font(.subheadline)
                                            .foregroundColor(friend.isOnline ? .green : .gray)
                                    }
                                    .padding(.leading, 8)
                                }
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Tin nhắn mới")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Tìm kiếm bạn bè")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hủy") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadFriends()
        }
    }
    
    private var filteredFriends: [User] {
        if searchText.isEmpty {
            return friends
        } else {
            return friends.filter { 
                $0.fullName.localizedCaseInsensitiveContains(searchText) ||
                $0.email.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private func loadFriends() {
        isLoading = true
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }
        
        let friendViewModel = FriendRequestViewModel()
        friendViewModel.fetchFriends(forUserId: currentUserId) { loadedFriends in
            DispatchQueue.main.async {
                self.friends = loadedFriends
                self.isLoading = false
            }
        }
    }
}
