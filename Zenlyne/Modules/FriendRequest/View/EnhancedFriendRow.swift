//
//  EnhancedFriendRow.swift
//  Zenlyne
//
//  Created by admin on 22/4/25.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct EnhancedFriendRow: View {
    let friend: User
    let hasLocation: Bool
    let isOnline: Bool
    let lastSeen: Date?
    let timeSinceLastUpdate: String?
    let onTap: () -> Void
    
    // Format time display
    private let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    
    // Determine location freshness color
    private var locationFreshnessColor: Color {
        guard timeSinceLastUpdate != nil else {
            return .gray
        }
        
        if let location = friend.lastLocation {
            let oneHourAgo = Date().timeIntervalSince1970 - (60 * 60)
            if location.timestamp > oneHourAgo {
                return .green
            }
            
            let twentyFourHoursAgo = Date().timeIntervalSince1970 - (24 * 60 * 60)
            if location.timestamp > twentyFourHoursAgo {
                return .orange
            }
        }
        
        return .red
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar with online/offline status
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
                    Circle()
                        .fill(isOnline ? Color.green : Color.red)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .position(x: 40, y: 40)
                }
                .frame(width: 50)
                
                
                VStack(alignment: .leading, spacing: 0) {
                    // Use lineLimit to limit the length of the username
                    Text(friend.fullName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    // Online status
                    Group {
                        if isOnline {
                            Text("Đang hoạt động")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        } else if let lastSeen = lastSeen {
                            Text("Hoạt động \(formatter.localizedString(for: lastSeen, relativeTo: Date()))")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                    .frame(height: 18)
                    
                    Group {
                        if let timeSinceLastUpdate = timeSinceLastUpdate {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(locationFreshnessColor)
                                    .frame(width: 6, height: 6)
                                
                                Text("Vị trí cập nhật \(timeSinceLastUpdate)")
                                    .font(.caption)
                                    .foregroundColor(locationFreshnessColor)
                                    .lineLimit(1)
                            }
                        } else {
                            Text("")
                                .font(.caption)
                        }
                    }
                    .frame(height: 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
                
                HStack(spacing: 8) {
                    // Location status icon with color indication
                    if hasLocation {
                        Image(systemName: "location.fill")
                            .foregroundColor(locationFreshnessColor)
                            .font(.system(size: 18))
                    } else {
                        Image(systemName: "location.slash")
                            .foregroundColor(.gray)
                            .font(.system(size: 18))
                    }
                    
                    // Right chevron
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                        .font(.system(size: 14))
                }
                .frame(width: 40)
            }
            .padding(.vertical, 8)
            .frame(height: 70)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(action: {
                // Start navigation to friend
                if let location = friend.lastLocation {
                    let url = URL(string: "maps://?daddr=\(location.latitude),\(location.longitude)")
                    if let url = url, UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                    }
                }
            }) {
                Label("Chỉ đường", systemImage: "arrow.triangle.turn.up.right.diamond")
            }
            .disabled(!hasLocation)
            
            Button(action: {
                // Implement message functionality
            }) {
                Label("Nhắn tin", systemImage: "message")
            }
            
            Divider()
            
            Button(role: .destructive, action: {
                // Delete friend feature in context menu
                if let currentUser = Auth.auth().currentUser {
                    let firebaseService = FirebaseService()
                    firebaseService.removeFriend(currentUserId: currentUser.uid, friendId: friend.id) { _ in }
                }
            }) {
                Label("Xóa bạn bè", systemImage: "person.badge.minus")
            }
        }
    }
}

struct EnhancedFriendRow_Previews: PreviewProvider {
    static var previews: some View {
        var mockFriend = User.MOCK_USER
        mockFriend.isOnline = true
        mockFriend.lastSeen = Date()
        
        return EnhancedFriendRow(
            friend: mockFriend,
            hasLocation: true,
            isOnline: true,
            lastSeen: Date().addingTimeInterval(-3600), // 1 hour ago
            timeSinceLastUpdate: "30 phút trước",
            onTap: {}
        )
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
