//
//  SameLocationUserRow.swift
//  Zenlyne
//
//  Created by admin on 26/6/25.
//

import SwiftUICore
import SwiftUI

struct SameLocationUserRow: View {
    let user: User
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Avatar with status indicator
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
            
            // Show status
            if user.isOnline {
                Text("Đang hoạt động")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
            } else if let lastSeen = user.lastSeen {
                // Check if it's been more than 72 hours
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
                // Fallback if no lastSeen
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
