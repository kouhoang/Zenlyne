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
        
        let db = Firestore.firestore()
        // Fix for the 'Initializer for conditional binding must have Optional type' error
        db.collection("users").document(currentUserId).getDocument { snapshot, error in
            // Don't use conditional binding with self here
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
