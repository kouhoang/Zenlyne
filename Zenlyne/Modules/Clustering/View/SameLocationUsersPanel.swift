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
            // Header
            headerSection
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // Users list with scrolling
            usersListSection
            
            // Quick actions if there is more than 1 user
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
            // Close button and title
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
                // Show both online and offline, only sort by online status
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
                        
                        // Animation when selecting
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
