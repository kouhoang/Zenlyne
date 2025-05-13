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
    @State private var friends: [User] = []
    @State private var isLoading = false
    @Environment(\.presentationMode) var presentationMode
    
    let onSelectUser: (User) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Hủy")
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                Text("Tin nhắn mới")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Spacer to balance the layout
                Text("").frame(width: 40)
            }
            .padding()
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                    .padding(.leading, 8)
                
                TextField("Tìm kiếm bạn bè", text: $searchText)
                    .padding(10)
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .padding(.trailing, 8)
                }
            }
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
            
            // Friends list
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle())
                Spacer()
            } else if friends.isEmpty {
                Spacer()
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
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedFriends) { friend in
                            Button(action: {
                                onSelectUser(friend)
                            }) {
                                FriendRowView(user: friend)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Divider()
                                .padding(.leading, 72)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .background(Color(.systemBackground))
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

struct FriendRowView: View {
    let user: User
    
    // Helper method để hiển thị thời gian hoạt động cuối
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
            // Profile Photo with status indicator
            ZStack(alignment: .bottomTrailing) {
                // Avatar background
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                // User image or initials
                if let profileImage = user.profileImageUrl {
                    AsyncImage(url: URL(string: profileImage)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Text(user.initials)
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                    .padding(2)
                } else {
                    Text(user.initials)
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 56, height: 56)
                        .padding(2)
                }
                
                // Status indicator
                Circle()
                    .fill(user.isOnline ? Color.green : Color.gray)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .offset(x: 0, y: 0)
            }
            .frame(width: 60, height: 60)
            
            // User info
            VStack(alignment: .leading, spacing: 4) {
                Text(user.fullName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(user.isOnline ? "Đang hoạt động" : lastSeenText(for: user))
                    .font(.subheadline)
                    .foregroundColor(user.isOnline ? .green : .gray)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(Color(.systemBackground))
    }
}

#Preview {
    NewMessageView(onSelectUser: { _ in })
}
