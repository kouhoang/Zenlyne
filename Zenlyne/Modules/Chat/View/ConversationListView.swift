//
//  ConversationListView.swift
//  Zenlyne
//
//  Created by admin on 6/5/25.
//

import SwiftUI
import FirebaseAuth

struct ConversationListView: View {
    @StateObject var viewModel = MessagingViewModel()
    @Environment(\.presentationMode) var presentationMode
    @State private var showNewMessageSheet = false
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var selectedChat: Chat? = nil
    @State private var selectedOtherUserId: String? = nil
    @State private var showChatView = false
    
    private let firebaseService = FirebaseService()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Main content
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Text("Tin Nhắn")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        // Search button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isSearching.toggle()
                                if !isSearching {
                                    searchText = ""
                                }
                            }
                        }) {
                            IconContainer(systemName: "magnifyingglass")
                        }
                        
                        // New message button
                        Button(action: {
                            showNewMessageSheet = true
                        }) {
                            IconContainer(systemName: "square.and.pencil")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // Search bar
                if isSearching {
                    HStack {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                                .font(.system(size: 16))
                            
                            TextField("Tìm kiếm tin nhắn...", text: $searchText)
                                .foregroundColor(.white)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            
                            if !searchText.isEmpty {
                                Button(action: {
                                    searchText = ""
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.pink, Color.yellow]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .cornerRadius(8)
                        
                        Button("Hủy") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isSearching = false
                                searchText = ""
                            }
                        }
                        .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Content
                ZStack {
                    if viewModel.chats.isEmpty && !viewModel.isLoading {
                        emptyStateView
                    } else if filteredChats.isEmpty && !searchText.isEmpty {
                        // No search results
                        VStack(spacing: 20) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            
                            Text("Không tìm thấy kết quả")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Không có cuộc trò chuyện nào phù hợp với từ khóa \"\(searchText)\"")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                    } else {
                        conversationsList
                    }
                    
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                // Start real-time chat updates
                viewModel.loadChats()
                
                // Update friend online statuses
                updateContactStatuses()
            }
            .sheet(isPresented: $showNewMessageSheet) {
                NewMessageView(onSelectUser: { user in
                    // Don't dismiss immediately - let the sheet animation complete first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showNewMessageSheet = false
                        
                        // Add another small delay before opening chat to avoid race condition
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            openChatWithUser(user)
                        }
                    }
                })
            }
            
            // Sheet for individual chat view
            .sheet(isPresented: $showChatView) {
                if let chat = selectedChat,
                   let otherUserId = selectedOtherUserId,
                   let otherUser = viewModel.chatUsers[otherUserId] {
                    
                    // Create the chat view
                    ChatView(
                        viewModel: viewModel,
                        chatId: chat.id,
                        otherUserId: otherUserId
                    )
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "message.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Không có tin nhắn nào")
                .font(.headline)
                .foregroundColor(.white)
            
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
                ConversationRowView(
                    chat: chat,
                    user: viewModel.getOtherUser(in: chat)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if let currentUserId = Auth.auth().currentUser?.uid,
                       let otherUserId = chat.getOtherParticipantId(currentUserId: currentUserId) {
                        selectedChat = chat
                        selectedOtherUserId = otherUserId
                        showChatView = true
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        viewModel.deleteChat(chatId: chat.id)
                    } label: {
                        Label("Xóa", systemImage: "trash")
                    }
                }
                .listRowBackground(Color.black)
            }
        }
        .listStyle(PlainListStyle())
        .background(Color.black)
        .scrollContentBackground(.hidden)
        .refreshable {
            viewModel.loadChats()
            updateContactStatuses()
        }
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
                       user.email.localizedCaseInsensitiveContains(searchText) ||
                       (chat.lastMessage?.content.localizedCaseInsensitiveContains(searchText) ?? false)
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
                
                // Check if chat already exists in our list
                if let index = viewModel.chats.firstIndex(where: { $0.id == chatId }) {
                    // Chat already exists - open it
                    selectedChat = viewModel.chats[index]
                    selectedOtherUserId = user.id
                    showChatView = true
                } else {
                    // Create new chat entry and open it
                    let newChat = Chat(
                        id: chatId,
                        participants: [currentUserId, user.id],
                        lastMessage: nil,
                        unreadCount: 0
                    )
                    selectedChat = newChat
                    selectedOtherUserId = user.id
                    
                    // Slight delay to allow time for creation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showChatView = true
                    }
                }
            }
        }
    }
    
    // Start monitoring online status of chat participants
    private func updateContactStatuses() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // For each chat, monitor the other participant's online status
        for chat in viewModel.chats {
            if let otherUserId = chat.getOtherParticipantId(currentUserId: currentUserId) {
                firebaseService.observeUserOnlineStatus(userId: otherUserId) { isOnline in
                    DispatchQueue.main.async {
                        if var user = viewModel.chatUsers[otherUserId] {
                            user.isOnline = isOnline
                            viewModel.chatUsers[otherUserId] = user
                        }
                    }
                }
            }
        }
    }
}

// Individual conversation row - similar to EnhancedFriendRow
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
    
    // Helper method to show last seen text
    private func lastSeenText(for user: User) -> String {
        if let lastSeen = user.lastSeen {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Hoạt động \(formatter.localizedString(for: lastSeen, relativeTo: Date()))"
        } else {
            return "Không hoạt động"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar with online/offline status - similar to EnhancedFriendRow
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                
                if let profileImage = user?.profileImageUrl {
                    AsyncImage(url: URL(string: profileImage)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Text(user?.initials ?? "?")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
                } else {
                    Text(user?.initials ?? "?")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                
                // Online status indicator
                if let user = user {
                    Circle()
                        .fill(user.isOnline ? Color.green : Color.red)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.black, lineWidth: 2)
                        )
                        .position(x: 40, y: 40)
                }
            }
            .frame(width: 50)
            
            VStack(alignment: .leading, spacing: 0) {
                // User name
                Text(user?.fullName ?? "Người dùng")
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                // Online status or last seen
                Group {
                    if let user = user {
                        if user.isOnline {
                            Text("Đang hoạt động")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        } else if let lastSeen = user.lastSeen {
                            let formatter = RelativeDateTimeFormatter()
                            Text("Hoạt động \(formatter.localizedString(for: lastSeen, relativeTo: Date()))")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(height: 18)
                
                // Last message preview
                Group {
                    if let lastMessage = chat.lastMessage {
                        Text(lastMessage.content.count > 30 ?
                             String(lastMessage.content.prefix(30)) + "..." :
                             lastMessage.content)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    } else {
                        Text("Bắt đầu trò chuyện")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .italic()
                    }
                }
                .frame(height: 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                // Message time
                Text(formatTime(chat.lastMessage?.timestamp))
                    .font(.caption)
                    .foregroundColor(.gray)
                
                // Unread count badge
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
            .frame(width: 60)
        }
        .padding(.vertical, 8)
        .frame(height: 70)
    }
}

// Custom chat avatar view
struct ChatAvatarView: View {
    let user: User?
    let size: CGFloat
    
    init(user: User?, size: CGFloat = 32) {
        self.user = user
        self.size = size
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: size, height: size)
            
            if let profileImage = user?.profileImageUrl {
                AsyncImage(url: URL(string: profileImage)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Text(user?.initials ?? "?")
                        .font(.system(size: size * 0.4))
                        .foregroundColor(.white)
                }
                .frame(width: size - 4, height: size - 4)
                .clipShape(Circle())
            } else {
                Text(user?.initials ?? "?")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(.white)
            }
        }
    }
}

#Preview {
    ConversationListView()
        .preferredColorScheme(.dark)
}
