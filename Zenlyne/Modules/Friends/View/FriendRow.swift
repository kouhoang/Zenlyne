//
//  EnhancedFriendRow.swift
//  Zenlyne
//
//  Created by admin on 22/4/25.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

struct FriendRow: View {
    let friend: User
    let hasLocation: Bool
    let isOnline: Bool
    let lastSeen: Date?
    let timeSinceLastUpdate: String?
    let onTap: () -> Void
    let onRemoveFriend: (() -> Void)? // Added callback for friend removal
    
    @State private var showingContextMenu = false
    @State private var isPressed = false
    @State private var showingRemoveAlert = false // Added confirmation alert
    @State private var isRemoving = false // Added loading state
    
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
        
        return .gray
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                avatarSection
                userInfoSection
                Spacer()
                statusSection
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isPressed ? Color.gray.opacity(0.2) : Color.clear)
                    .animation(.easeInOut(duration: 0.1), value: isPressed)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .listRowBackground(Color.black)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
        .contextMenu {
            contextMenuItems
        }
        .onLongPressGesture(minimumDuration: 0.1, maximumDistance: 50) {
            // Handle long press
        } onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
        .alert("Xóa bạn bè", isPresented: $showingRemoveAlert) {
            Button("Hủy", role: .cancel) { }
            Button("Xóa", role: .destructive) {
                onRemoveFriend?()
            }
        } message: {
            Text("Bạn có chắc chắn muốn xóa \(friend.fullName) khỏi danh sách bạn bè?")
        }
        .disabled(isRemoving)
    }
    
    // MARK: - View Components
    
    private var avatarSection: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.gray.opacity(0.3),
                            Color.gray.opacity(0.1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 56, height: 56)
            
            if let profileImage = friend.profileImageUrl {
                AsyncImage(url: URL(string: profileImage)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                        
                        Text(friend.initials)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
            } else {
                Text(friend.initials)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            
            // Online status indicator with animation
            Circle()
                .fill(isOnline ? Color.green : Color.red)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .stroke(Color.black, lineWidth: 2)
                )
                .overlay(
                    Circle()
                        .stroke(isOnline ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 4)
                        .scaleEffect(isOnline ? 1.2 : 1.0)
                        .opacity(isOnline ? 0.6 : 0.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isOnline)
                )
                .offset(x: 20, y: 20)
        }
    }
    
    private var userInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Name with truncation
            Text(friend.fullName)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            
            // Online status with better formatting
            onlineStatusView
            
            // Location status with better visual feedback
            locationStatusView
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var onlineStatusView: some View {
        Group {
            if isOnline {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    
                    Text("Đang hoạt động")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
            } else if let lastSeen = lastSeen {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 6, height: 6)
                    
                    Text("Hoạt động \(formatter.localizedString(for: lastSeen, relativeTo: Date()))")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 6, height: 6)
                    
                    Text("Không rõ trạng thái")
                        .font(.subheadline)
                        .foregroundColor(.gray.opacity(0.7))
                }
            }
        }
        .frame(height: 20)
    }
    
    private var locationStatusView: some View {
        Group {
            if let timeSinceLastUpdate = timeSinceLastUpdate {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundColor(locationFreshnessColor)
                    
                    Text("Vị trí cập nhật \(timeSinceLastUpdate)")
                        .font(.caption)
                        .foregroundColor(locationFreshnessColor)
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "location.slash")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.6))
                    
                    Text("Chưa chia sẻ vị trí")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.6))
                }
            }
        }
        .frame(height: 18)
    }
    
    private var statusSection: some View {
        VStack(spacing: 8) {
            // Location status icon with enhanced visual feedback
            locationIconView
            
            // Right chevron with animation
            Image(systemName: "chevron.right")
                .foregroundColor(.gray.opacity(0.6))
                .font(.system(size: 14, weight: .medium))
                .scaleEffect(isPressed ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .frame(width: 44)
    }
    
    private var locationIconView: some View {
        ZStack {
            Circle()
                .fill(locationFreshnessColor.opacity(0.2))
                .frame(width: 32, height: 32)
            
            if hasLocation {
                Image(systemName: "location.fill")
                    .foregroundColor(locationFreshnessColor)
                    .font(.system(size: 16, weight: .medium))
                
                // Pulsing animation for fresh locations
                if locationFreshnessColor == .green {
                    Circle()
                        .stroke(locationFreshnessColor.opacity(0.4), lineWidth: 2)
                        .frame(width: 36, height: 36)
                        .scaleEffect(1.2)
                        .opacity(0.0)
                        .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false), value: UUID())
                }
            } else {
                Image(systemName: "location.slash")
                    .foregroundColor(.gray.opacity(0.6))
                    .font(.system(size: 16, weight: .medium))
            }
        }
    }
    
    // MARK: - Context Menu
    
    @ViewBuilder
    private var contextMenuItems: some View {
        // Focus on map
        Button(action: {
            onTap()
        }) {
            Label("Xem trên bản đồ", systemImage: "map")
        }
        
        // Navigation
        if hasLocation {
            Button(action: {
                navigateToFriend()
            }) {
                Label("Chỉ đường", systemImage: "arrow.triangle.turn.up.right.diamond")
            }
        }
        
        // Message
        Button(action: {
            messageToFriend()
        }) {
            Label("Nhắn tin", systemImage: "message")
        }
        
        // Call (if phone number available)
        Button(action: {
            callFriend()
        }) {
            Label("Gọi điện", systemImage: "phone")
        }
        
        Divider()
        
        // Share location with friend
        Button(action: {
            shareLocationWithFriend()
        }) {
            Label("Chia sẻ vị trí", systemImage: "location.circle")
        }
        
        // Friend profile
        Button(action: {
            viewFriendProfile()
        }) {
            Label("Xem hồ sơ", systemImage: "person.circle")
        }
        
        Divider()
        
        // Remove friend - Updated implementation with callback
        if onRemoveFriend != nil {
            Button(role: .destructive, action: {
                showingRemoveAlert = true
            }) {
                Label("Xóa bạn bè", systemImage: "person.badge.minus")
            }
            .disabled(isRemoving)
        }
    }
    
    // MARK: - Action Methods
    
    private func navigateToFriend() {
        if let location = friend.lastLocation {
            let url = URL(string: "maps://?daddr=\(location.latitude),\(location.longitude)")
            if let url = url, UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                // Fallback to Apple Maps web
                let webUrl = URL(string: "https://maps.apple.com/?daddr=\(location.latitude),\(location.longitude)")
                if let webUrl = webUrl {
                    UIApplication.shared.open(webUrl)
                }
            }
        }
    }
    
    private func messageToFriend() {
        // TODO: Implement messaging functionality
        // This could open the chat view or integrate with FirebaseChatManager
        print("Opening chat with \(friend.fullName)")
        
        // Example implementation - you can customize this based on your chat system
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenChatWithFriend"),
            object: nil,
            userInfo: [
                "friendId": friend.id,
                "friendName": friend.fullName
            ]
        )
    }
    
    private func callFriend() {
        // TODO: Implement calling functionality
        // This would require phone number in User model
        print("Calling \(friend.fullName)")
        
        // Example implementation if you have phone numbers
        // if let phoneNumber = friend.phoneNumber {
        //     let url = URL(string: "tel://\(phoneNumber)")
        //     if let url = url, UIApplication.shared.canOpenURL(url) {
        //         UIApplication.shared.open(url)
        //     }
        // }
        
        // For now, show an alert that this feature is not implemented
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowFeatureNotImplemented"),
            object: nil,
            userInfo: ["feature": "Gọi điện"]
        )
    }
    
    private func shareLocationWithFriend() {
        // TODO: Implement location sharing
        print("Sharing location with \(friend.fullName)")
        
        // Example implementation
        NotificationCenter.default.post(
            name: NSNotification.Name("ShareLocationWithFriend"),
            object: nil,
            userInfo: [
                "friendId": friend.id,
                "friendName": friend.fullName
            ]
        )
    }
    
    private func viewFriendProfile() {
        // TODO: Implement profile viewing
        print("Viewing profile of \(friend.fullName)")
        
        // Example implementation
        NotificationCenter.default.post(
            name: NSNotification.Name("ViewFriendProfile"),
            object: nil,
            userInfo: [
                "friendId": friend.id,
                "friend": friend
            ]
        )
    }
}

// MARK: - Convenience Initializers

extension FriendRow {
    // Initializer without remove callback for backward compatibility
    init(
        friend: User,
        hasLocation: Bool,
        isOnline: Bool,
        lastSeen: Date?,
        timeSinceLastUpdate: String?,
        onTap: @escaping () -> Void
    ) {
        self.friend = friend
        self.hasLocation = hasLocation
        self.isOnline = isOnline
        self.lastSeen = lastSeen
        self.timeSinceLastUpdate = timeSinceLastUpdate
        self.onTap = onTap
        self.onRemoveFriend = nil
    }
}

// MARK: - Preview Provider

struct EnhancedFriendRow_Previews: PreviewProvider {
    static var previews: some View {
        let sampleFriend = User(
            id: "sample-id",
            fullName: "Nguyễn Văn An",
            email: "nguyen.van.an@example.com"
        )
        
        List {
            FriendRow(
                friend: sampleFriend,
                hasLocation: true,
                isOnline: true,
                lastSeen: Date(),
                timeSinceLastUpdate: "5 phút trước",
                onTap: {
                    print("Tapped on friend")
                },
                onRemoveFriend: {
                    print("Remove friend tapped")
                }
            )
            
            FriendRow(
                friend: sampleFriend,
                hasLocation: false,
                isOnline: false,
                lastSeen: Date().addingTimeInterval(-3600),
                timeSinceLastUpdate: nil,
                onTap: {
                    print("Tapped on friend")
                }
            )
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}
