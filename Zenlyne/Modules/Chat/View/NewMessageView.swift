//
//  NewMessageView.swift
//  Zenlyne
//
//  Created by admin on 6/5/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// View to select a new message recipient
struct NewMessageView: View {
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var friends: [User] = []
    @State private var isLoading = false
    @Environment(\.presentationMode) var presentationMode
    
    let onSelectUser: (User) -> Void
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
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
                            
                            TextField("Tìm kiếm bạn bè...", text: $searchText)
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
                
                // Friends list
                ZStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    } else if friends.isEmpty {
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
                    } else if sortedFriends.isEmpty && !searchText.isEmpty {
                        // No search results
                        VStack(spacing: 20) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            
                            Text("Không tìm thấy kết quả")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Không có bạn bè nào phù hợp với từ khóa \"\(searchText)\"")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding()
                    } else {
                        List {
                            ForEach(sortedFriends) { friend in
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadFriends()
        }
    }
    
    private var sortedFriends: [User] {
        let filteredUsers = searchText.isEmpty ? friends : friends.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchText) ||
            $0.email.localizedCaseInsensitiveContains(searchText)
        }
        
        return filteredUsers.sorted { (user1, user2) -> Bool in
            if user1.isOnline && !user2.isOnline {
                return true
            } else if !user1.isOnline && user2.isOnline {
                return false
            } else {
                return user1.fullName < user2.fullName
            }
        }
    }
    
    private func loadFriends() {
        isLoading = true
        
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }
        
        let db = Firestore.firestore()
        db.collection("users").document(currentUserId).getDocument { snapshot, error in
            if snapshot == nil || error != nil {
                self.isLoading = false
                return
            }
            
            guard let document = snapshot,
                  let data = document.data(),
                  let friendIds = data["friendIds"] as? [String] else {
                self.isLoading = false
                return
            }
            
            if friendIds.isEmpty {
                self.isLoading = false
                return
            }
            
            let group = DispatchGroup()
            var loadedFriends: [User] = []
            
            for friendId in friendIds {
                group.enter()
                
                db.collection("users").document(friendId).getDocument { document, error in
                    defer { group.leave() }
                    
                    guard let document = document,
                          let data = document.data(),
                          let fullName = data["fullName"] as? String,
                          let email = data["email"] as? String else {
                        return
                    }
                    
                    var user = User(id: friendId, fullName: fullName, email: email)
                    user.profileImageUrl = data["profileImageUrl"] as? String
                    user.isOnline = data["isOnline"] as? Bool ?? false
                    
                    if let lastSeenTimestamp = data["lastSeen"] as? TimeInterval {
                        user.lastSeen = Date(timeIntervalSince1970: lastSeenTimestamp)
                    }
                    
                    loadedFriends.append(user)
                }
            }
            
            group.notify(queue: .main) {
                self.friends = loadedFriends
                self.isLoading = false
            }
        }
    }
}

// Friend row view for message selection - similar to EnhancedFriendRow
struct MessageFriendRowView: View {
    let user: User
    
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
            // Avatar with online/offline status
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                
                if let profileImage = user.profileImageUrl {
                    AsyncImage(url: URL(string: profileImage)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Text(user.initials)
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
                } else {
                    Text(user.initials)
                        .font(.title3)
                        .foregroundColor(.white)
                }
                
                // Online status indicator
                Circle()
                    .fill(user.isOnline ? Color.green : Color.red)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(Color.black, lineWidth: 2)
                    )
                    .position(x: 40, y: 40)
            }
            .frame(width: 50)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(user.fullName)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Group {
                    if user.isOnline {
                        Text("Đang hoạt động")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    } else {
                        Text(lastSeenText(for: user))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                .frame(height: 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            // Right chevron
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.system(size: 14))
                .frame(width: 20)
        }
        .padding(.vertical, 8)
        .frame(height: 70)
    }
}

#Preview {
    NewMessageView(onSelectUser: { _ in })
        .preferredColorScheme(.dark)
}
