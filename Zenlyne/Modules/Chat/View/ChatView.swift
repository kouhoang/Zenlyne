//
//  ChatView.swift
//  Zenlyne
//
//  Created by admin on 6/5/25.
//

import SwiftUI
import FirebaseAuth

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @State private var showingProfile = false
    @State private var scrollToBottom = false
    @FocusState private var isInputFocused: Bool
    @Environment(\.presentationMode) var presentationMode
    
    init(chatId: String, otherUserId: String) {
        self._viewModel = StateObject(wrappedValue: ChatViewModel(chatId: chatId, otherUserId: otherUserId))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom header
            ChatHeaderView(
                user: viewModel.otherUser,
                onDismiss: { presentationMode.wrappedValue.dismiss() },
                onProfileTap: { showingProfile = true }
            )
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if viewModel.isLoading && viewModel.messages.isEmpty {
                        loadingView
                    } else {
                        messagesListView
                        messageInputView
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showingProfile) {
            if let user = viewModel.otherUser {
                FriendProfileView(user: user)
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
    
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            Spacer()
        }
    }
    
    private var messagesListView: some View {
        ScrollViewReader { scrollView in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageRow(
                            message: message,
                            otherUser: viewModel.otherUser,
                            isFromCurrentUser: viewModel.isMessageFromCurrentUser(message)
                        )
                        .id(message.id)
                    }
                    
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    scrollToBottom.toggle()
                }
            }
        }
    }
    
    private var messageInputView: some View {
        HStack(spacing: 12) {
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
            
            Button(action: viewModel.sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(viewModel.canSendMessage ? Color.blue : Color.gray)
                    )
            }
            .disabled(!viewModel.canSendMessage)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black)
    }
}
