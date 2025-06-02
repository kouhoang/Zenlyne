//
//  NewMessageView.swift
//  Zenlyne
//
//  Created by admin on 6/5/25.
//

//
//  Views/Chat/NewMessageView.swift
//  Zenlyne
//

import SwiftUI

struct NewMessageView: View {
    @ObservedObject var viewModel: NewMessageViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var isSearching = false
    
    let onSelectUser: (User) -> Void
    
    init(viewModel: NewMessageViewModel, onSelectUser: @escaping (User) -> Void) {
        self.viewModel = viewModel
        self.onSelectUser = onSelectUser
    }
    
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
                Text("Hủy")
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Text("Tin nhắn mới")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Spacer()
            
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
                
                TextField("Tìm kiếm bạn bè...", text: $viewModel.searchText)
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
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            } else if viewModel.friends.isEmpty {
                emptyStateView
            } else if viewModel.sortedFriends.isEmpty && !viewModel.searchText.isEmpty {
                noSearchResultsView
            } else {
                friendsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Không có bạn bè nào")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Thêm bạn bè trước khi bắt đầu cuộc trò chuyện")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
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
            
            Text("Không có bạn bè nào phù hợp với từ khóa \"\(viewModel.searchText)\"")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
    
    private var friendsList: some View {
        List {
            ForEach(viewModel.sortedFriends) { friend in
                Button(action: {
                    onSelectUser(friend)
                }) {
                    MessageFriendRowView(user: friend)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .listRowBackground(Color.black)
            }
        }
        .listStyle(PlainListStyle())
        .background(Color.black)
        .scrollContentBackground(.hidden)
    }
}
