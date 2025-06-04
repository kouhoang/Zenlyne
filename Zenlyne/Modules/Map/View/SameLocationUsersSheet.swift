//
//  SameLocationUsersSheet.swift
//  Zenlyne
//
//  Created by kou on 4/6/25.
//

import SwiftUI
import CoreLocation

struct SameLocationUsersSheet: View {
    let users: [User]
    let location: UserLocation?
    let onUserSelected: (String) -> Void
    let onClose: () -> Void
    
    @State private var selectedUserId: String? = nil
    @State private var isExpanded = false
    
    private let animationDuration: Double = 0.3
    
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
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(users.count) người cùng vị trí")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if let location = location {
                            Text("Tọa độ: \(formatCoordinate(location.toCoordinate()))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.gray)
                    }
                }
                
                // Online status summary
                let onlineCount = users.filter { $0.isOnline }.count
                if onlineCount > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        
                        Text("\(onlineCount)/\(users.count) đang online")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                }
                
                // Location age info
                if let location = location {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundColor(.orange)
                        
                        Text("Cập nhật \(formatLocationAge(location))")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            // Users list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(users.sorted(by: { $0.isOnline && !$1.isOnline })) { user in
                        SameLocationUserRow(
                            user: user,
                            isSelected: selectedUserId == user.id
                        ) {
                            selectedUserId = user.id
                            
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isExpanded = false
                            }
                            
                            // Delay before closing and showing user info
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                onUserSelected(user.id)
                            }
                        }
                        
                        if user.id != users.last?.id {
                            Divider()
                                .padding(.leading, 76)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 400) // Limit height for scrolling
            
            // Quick actions
            if users.count > 1 {
                VStack(spacing: 12) {
                    Divider()
                    
                    HStack(spacing: 16) {
                        // Message all button
                        Button(action: {
                            print("Message all users at this location")
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "message.fill")
                                    .foregroundColor(.white)
                                Text("Nhắn tin nhóm")
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                            }
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        
                        // Navigate to location button
                        Button(action: {
                            handleNavigateToLocation()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "location.fill")
                                    .foregroundColor(.white)
                                Text("Chỉ đường")
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                            }
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal)
        .onAppear {
            withAnimation(.easeOut(duration: animationDuration)) {
                isExpanded = true
            }
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
            // Fallback to Google Maps web
            let webUrl = URL(string: "https://maps.google.com/maps?daddr=\(coordinate.latitude),\(coordinate.longitude)")
            if let webUrl = webUrl {
                UIApplication.shared.open(webUrl)
            }
        }
    }
}

struct SameLocationUserRow: View {
    let user: User
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Avatar with status indicator
                ZStack(alignment: .bottomTrailing) {
                    // Avatar circle
                    if let profileImageUrl = user.currentAvatarUrl,
                       let url = URL(string: profileImageUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(isSelected ? Color.blue : Color.white, lineWidth: 2)
                                )
                        } placeholder: {
                            ZStack {
                                Circle()
                                    .fill(user.isOnline ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                                Text(user.initials)
                                    .font(.system(size: 18))
                                    .foregroundColor(user.isOnline ? .green : .gray)
                            }
                            .frame(width: 50, height: 50)
                            .overlay(
                                Circle()
                                    .stroke(isSelected ? Color.blue : Color.white, lineWidth: 2)
                            )
                        }
                    } else {
                        ZStack {
                            Circle()
                                .fill(user.isOnline ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                                .frame(width: 50, height: 50)
                            Text(user.initials)
                                .font(.system(size: 18))
                                .foregroundColor(user.isOnline ? .green : .gray)
                        }
                        .overlay(
                            Circle()
                                .stroke(isSelected ? Color.blue : Color.white, lineWidth: 2)
                        )
                    }
                    
                    // Status indicator
                    Circle()
                        .fill(user.isOnline ? Color.green : Color.gray)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .offset(x: 2, y: 2)
                }
                .padding(.leading, 10)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.fullName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 4) {
                        if user.isOnline {
                            Text("Đang hoạt động")
                                .font(.system(size: 14))
                                .foregroundColor(.green)
                        } else if let lastSeen = user.lastSeen {
                            Text("Hoạt động \(formatLastSeen(lastSeen))")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        } else {
                            Text(user.email)
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Spacer()
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                } else {
                    Text("Xem")
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
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.white)
                    .opacity(isPressed ? 0.8 : 1.0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .onLongPressGesture(minimumDuration: 0) { pressing in
            isPressed = pressing
        } perform: {
            onTap()
        }
    }
    
    // Helper method to format last seen time
    private func formatLastSeen(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    SameLocationUsersSheet(
        users: [
            User(id: "1", fullName: "Nguyễn Văn A", email: "a@example.com"),
            User(id: "2", fullName: "Trần Thị B", email: "b@example.com"),
            User(id: "3", fullName: "Lê Văn C", email: "c@example.com")
        ],
        location: UserLocation(latitude: 21.0285, longitude: 105.8542),
        onUserSelected: { _ in },
        onClose: {}
    )
}
