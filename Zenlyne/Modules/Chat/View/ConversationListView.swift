//
//  ConversationListView.swift
//  Zenlyne
//
//  Created by admin on 6/5/25.
//

import SwiftUI
import FirebaseAuth

struct ConversationListView: View {
    @StateObject private var viewModel = ConversationListViewModel()
    @StateObject private var newMessageViewModel = NewMessageViewModel()
    @Environment(\.presentationMode) var presentationMode
    @State private var showNewMessageSheet = false
    @State private var isSearching = false
    @State private var selectedChatInfo: (chatId: String, otherUserId: String)? = nil
    @State private var showChatView = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerView
                
                if isSearching {
                    searchBarView
                }
                
                contentView
            }
        }
        .onAppear {
            viewModel.refreshChats()
        }
        .sheet(isPresented: $showNewMessageSheet) {
            NewMessageView(viewModel: newMessageViewModel) { user in
                showNewMessageSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    openChatWithUser(user)
                }
            }
        }
        .sheet(isPresented: $showChatView) {
            if let chatInfo = selectedChatInfo {
                ChatView(chatId: chatInfo.chatId, otherUserId: chatInfo.otherUserId)
            }
        }
        .alert("Lỗi", isPresented: .constant(!viewModel.errorMessage.isEmpty)) {
            Button("OK") {
                viewModel.errorMessage = ""
            }
        } message: {
            Text(viewModel.errorMessage)
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
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
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isSearching.toggle()
                        if !isSearching {
                            viewModel.searchText = ""
                        }
                    }
                }) {
                    IconContainer(systemName: "magnifyingglass")
                }
                
                Button(action: {
                    showNewMessageSheet = true
                }) {
                    IconContainer(systemName: "square.and.pencil")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var searchBarView: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                    .font(.system(size: 16))
                
                TextField("Tìm kiếm tin nhắn...", text: $viewModel.searchText)
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                if !viewModel.searchText.isEmpty {
                    Button(action: {
                        viewModel.searchText = ""
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
                    viewModel.searchText = ""
                }
            }
            .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    private var contentView: some View {
        ZStack {
            if viewModel.chats.isEmpty && !viewModel.isLoading {
                emptyStateView
            } else if viewModel.filteredChats.isEmpty && !viewModel.searchText.isEmpty {
                noSearchResultsView
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
    
    private var noSearchResultsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Không tìm thấy kết quả")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Không có cuộc trò chuyện nào phù hợp với từ khóa \"\(viewModel.searchText)\"")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
    
    private var conversationsList: some View {
        List {
            ForEach(viewModel.filteredChats) { chat in
                ConversationRowView(
                    chat: chat,
                    user: viewModel.getOtherUser(in: chat)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if let currentUserId = Auth.auth().currentUser?.uid,
                       let otherUserId = chat.getOtherParticipantId(currentUserId: currentUserId) {
                        selectedChatInfo = (chatId: chat.id, otherUserId: otherUserId)
                        showChatView = true
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        viewModel.deleteChat(chat)
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
            viewModel.refreshChats()
        }
    }
    
    // MARK: - Helper Methods
    
    private func openChatWithUser(_ user: User) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        let chatId = [currentUserId, user.id].sorted().joined(separator: "_")
        
        viewModel.createChatIfNeeded(with: user.id) { success in
            if success {
                if viewModel.chatUsers[user.id] == nil {
                    viewModel.chatUsers[user.id] = user
                }
                
                selectedChatInfo = (chatId: chatId, otherUserId: user.id)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showChatView = true
                }
            }
        }
    }
}
