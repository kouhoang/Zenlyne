//
//  EnhancedFriendClusterSelectionView.swift
//  Zenlyne
//
//  Created by admin on 20/5/25.
//

import SwiftUI

struct EnhancedFriendClusterSelectionView: View {
    let friends: [User]
    let onFriendSelected: (String) -> Void
    let onClose: () -> Void
    
    @State private var isExpanded = false
    private let animationDuration: Double = 0.3
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle for dragging/collapsing
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
                Text("\(friends.count) Friends in this Area")
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
            
            // Online status summary
            let onlineCount = friends.filter { $0.isOnline }.count
            if onlineCount > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    
                    Text("\(onlineCount) online now")
                        .font(.subheadline)
                        .foregroundColor(.green)
                        .padding(.bottom, 8)
                }
            }
            
            Divider()
            
            // Friends list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(friends) { friend in
                        EnhancedFriendClusterRow(friend: friend) {
                            withAnimation {
                                self.isExpanded = false
                            }
                            
                            // Slight delay before notifying selection to allow animation to complete
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                onFriendSelected(friend.id)
                            }
                        }
                        
                        if friend.id != friends.last?.id {
                            Divider()
                                .padding(.leading, 76)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Quick action buttons
            HStack(spacing: 20) {
                // Message All button
                Button(action: {
                    // This would open a group chat with all these friends
                    print("Message all tapped")
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "message.fill")
                            .foregroundColor(.white)
                        Text("Message All")
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                
                // Navigate button
                Button(action: {
                    print("Navigate tapped")
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .foregroundColor(.white)
                        Text("Navigate")
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal)
        .onAppear {
            // Animate expansion when view appears
            withAnimation(.easeOut(duration: animationDuration)) {
                isExpanded = true
            }
        }
    }
}

struct EnhancedFriendClusterRow: View {
    let friend: User
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Avatar with status indicator
                ZStack(alignment: .bottomTrailing) {
                    // Avatar circle
                    if let profileImageUrl = friend.currentAvatarUrl,
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
                            Text("Online")
                                .font(.system(size: 14))
                                .foregroundColor(.green)
                        } else if let lastSeen = friend.lastSeen {
                            Text("Last seen \(formatLastSeen(lastSeen))")
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
                
                // Distance (if available)
                if let _ = friend.lastLocation {
                    Text("Show")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .opacity(0.01)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    // Helper method to format last seen time
    private func formatLastSeen(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// Button style for a subtle scale effect on tap
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
            .background(
                configuration.isPressed ?
                    Color.gray.opacity(0.1).cornerRadius(12) :
                    Color.clear.cornerRadius(12)
            )
    }
}

#Preview {
    EnhancedFriendClusterSelectionView(
        friends: [User.MOCK_USER],
        onFriendSelected: { _ in },
        onClose: {}
    )
}
