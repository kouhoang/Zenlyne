//
//  ChatHeaderView.swift
//  Zenlyne
//
//  Created by admin on 2/6/25.
//

import SwiftUI

struct ChatHeaderView: View {
    let user: User?
    let onDismiss: () -> Void
    let onProfileTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            .padding(.leading, 4)
            
            Button(action: onProfileTap) {
                ChatAvatarView(user: user, size: 40)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(user?.fullName ?? "Chat")
                    .font(.headline)
                    .foregroundColor(.white)
                
                if let user = user {
                    if user.isOnline {
                        Text("Đang hoạt động")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else if let lastSeen = user.lastSeen {
                        Text("Hoạt động \(formatRelativeTime(lastSeen))")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .onTapGesture {
                onProfileTap()
            }
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(90))
            }
            .padding(.trailing, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black)
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
