//
//  SameLocationUsersPanel.swift
//  Zenlyne
//
//  Created by kou on 4/6/25.
//

import SwiftUI
import CoreLocation

struct SameLocationUsersPanel: View {
    let users: [User]
    let location: UserLocation?
    let onUserSelected: (String) -> Void
    let onClose: () -> Void
    
    @State private var selectedUserId: String? = nil
    @State private var showingAnimation = false
    
    private let animationDuration: Double = 0.3
    
    var body: some View {
        VStack(spacing: 0) {
            // Header với dark theme
            headerSection
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // Users list với scrolling
            usersListSection
            
            // Quick actions nếu có nhiều hơn 1 user
            if users.count > 1 {
                quickActionsSection
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 15, x: 0, y: 8)
        )
        .frame(minHeight: 600)
        .padding(.horizontal, 16)
        .scaleEffect(showingAnimation ? 1.0 : 0.8)
        .opacity(showingAnimation ? 1.0 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                showingAnimation = true
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Close button và title
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(users.count) người cùng vị trí")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    if let location = location {
                        Text("Tọa độ: \(formatCoordinate(location.toCoordinate()))")
                            .font(.caption)
                            .foregroundColor(Color.gray.opacity(0.8))
                    }
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingAnimation = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onClose()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.7))
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.3))
                                .frame(width: 32, height: 32)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Status indicators
            HStack(spacing: 16) {
                // Online status
                let onlineCount = users.filter { $0.isOnline }.count
                if onlineCount > 0 {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        
                        Text("\(onlineCount)/\(users.count) đang online")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                }
                
                Spacer()
                
                // Location age
                if let location = location {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        
                        Text("Cập nhật \(formatLocationAge(location))")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Users List Section

    private var usersListSection: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                // SỬA LOGIC SORT: Hiển thị cả online và offline, chỉ sort theo online status
                ForEach(users.sorted(by: { user1, user2 in
                    // Online users first, then offline users
                    if user1.isOnline && !user2.isOnline {
                        return true
                    } else if !user1.isOnline && user2.isOnline {
                        return false
                    } else {
                        // If both have same online status, sort by name
                        return user1.fullName < user2.fullName
                    }
                })) { user in
                    SameLocationUserRow(
                        user: user,
                        isSelected: selectedUserId == user.id
                    ) {
                        selectedUserId = user.id
                        
                        // Animation khi select
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showingAnimation = false
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onUserSelected(user.id)
                        }
                    }
                    
                    if user.id != users.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.1))
                            .padding(.leading, 80)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .frame(maxHeight: 350)
    }
    
    // MARK: - Quick Actions Section
    
    private var quickActionsSection: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.gray.opacity(0.3))
            
            HStack(spacing: 12) {
                // Message all button
                Button(action: {
                    print("Message all users at this location")
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 16))
                        Text("Nhắn tin nhóm")
                            .fontWeight(.medium)
                            .font(.system(size: 15))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Navigate button
                Button(action: handleNavigateToLocation) {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 16))
                        Text("Chỉ đường")
                            .fontWeight(.medium)
                            .font(.system(size: 15))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.orange, Color.orange.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatCoordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        return String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }
    
    private func formatLocationAge(_ location: UserLocation) -> String {
        let locationDate = Date(timeIntervalSince1970: location.timestamp)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: locationDate, relativeTo: Date())
    }
    
    private func handleNavigateToLocation() {
        guard let location = location else { return }
        
        let coordinate = location.toCoordinate()
        let url = URL(string: "maps://?daddr=\(coordinate.latitude),\(coordinate.longitude)")
        
        if let url = url, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            let webUrl = URL(string: "https://maps.google.com/maps?daddr=\(coordinate.latitude),\(coordinate.longitude)")
            if let webUrl = webUrl {
                UIApplication.shared.open(webUrl)
            }
        }
    }
}

// MARK: - Updated User Row với Dark Theme

struct SameLocationUserRow: View {
    let user: User
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Avatar với status indicator
                avatarSection
                
                // User info
                userInfoSection
                
                Spacer()
                
                // Action indicator
                actionIndicator
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isSelected ?
                        Color.blue.opacity(0.3) :
                        (isPressed ? Color.white.opacity(0.1) : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.blue.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.98 : 1)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .onLongPressGesture(minimumDuration: 0) { pressing in
            isPressed = pressing
        } perform: {
            onTap()
        }
    }
    
    private var avatarSection: some View {
        ZStack(alignment: .bottomTrailing) {
            // Avatar
            if let profileImageUrl = user.currentAvatarUrl,
               let url = URL(string: profileImageUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(
                                    isSelected ? Color.blue : Color.white.opacity(0.3),
                                    lineWidth: 2
                                )
                        )
                } placeholder: {
                    ZStack {
                        Circle()
                            .fill(user.isOnline ? Color.green.opacity(0.3) : Color.gray.opacity(0.3))
                        Text(user.initials)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .frame(width: 52, height: 52)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(user.isOnline ? Color.green.opacity(0.3) : Color.gray.opacity(0.3))
                        .frame(width: 52, height: 52)
                    Text(user.initials)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            
            // Status indicator
            Circle()
                .fill(user.isOnline ? Color.green : Color.gray)
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .stroke(Color.black, lineWidth: 2)
                )
                .offset(x: 2, y: 2)
        }
    }
    
    private var userInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(user.fullName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            
            // SỬA LOGIC HIỂN thị STATUS
            if user.isOnline {
                Text("Đang hoạt động")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
            } else if let lastSeen = user.lastSeen {
                // Kiểm tra xem có quá 72 tiếng không
                let hoursSinceLastSeen = Date().timeIntervalSince(lastSeen) / 3600
                if hoursSinceLastSeen <= 72 {
                    Text("Hoạt động \(formatLastSeen(lastSeen))")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                } else {
                    Text("Offline hơn 3 ngày")
                        .font(.system(size: 14))
                        .foregroundColor(.red.opacity(0.7))
                }
            } else {
                // Fallback nếu không có lastSeen
                Text("Trạng thái không rõ")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
        }
    }
    
    private var actionIndicator: some View {
        Group {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.blue)
            } else {
                HStack(spacing: 6) {
                    Text("Xem")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.blue.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
    }
    
    private func formatLastSeen(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
