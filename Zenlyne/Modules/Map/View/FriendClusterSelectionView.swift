//
//  FriendClusterSelectionView.swift
//  Zenlyne
//
//  Created by admin on 20/5/25.
//


import SwiftUI

struct FriendClusterSelectionView: View {
    let friends: [User]
    let onFriendSelected: (String) -> Void
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle for dragging
            HStack {
                Spacer()
                Rectangle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 40, height: 5)
                    .cornerRadius(2.5)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                Spacer()
            }
            
            // Header
            HStack {
                Text("\(friends.count) bạn bè ở đây")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            // Friends list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(friends) { friend in
                        FriendClusterRow(friend: friend) {
                            onFriendSelected(friend.id)
                        }
                        
                        if friend.id != friends.last?.id {
                            Divider()
                                .padding(.leading, 76)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal)
    }
}

struct FriendClusterRow: View {
    let friend: User
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Avatar with status indicator
                ZStack(alignment: .bottomTrailing) {
                    // Avatar circle
                    if let profileImageUrl = friend.profileImageUrl,
                       let url = URL(string: profileImageUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                )
                        } placeholder: {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                Text(friend.initials)
                                    .font(.system(size: 18))
                                    .foregroundColor(.blue)
                            }
                            .frame(width: 50, height: 50)
                        }
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 50, height: 50)
                            Text(friend.initials)
                                .font(.system(size: 18))
                                .foregroundColor(.blue)
                        }
                    }
                    
                    // Status indicator
                    Circle()
                        .fill(friend.isOnline ? Color.green : Color.gray)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .offset(x: 2, y: 2)
                }
                .padding(.leading, 10)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.fullName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 4) {
                        if friend.isOnline {
                            Text("Đang hoạt động")
                                .font(.system(size: 14))
                                .foregroundColor(.green)
                        } else if let lastSeen = friend.lastSeen {
                            Text("Hoạt động \(lastSeen, formatter: RelativeDateTimeFormatter())")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        } else {
                            Text(friend.email)
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
