//
//  FriendInfoPanel.swift
//  Zenlyne
//
//  Created by admin on 19/3/25.
//

import SwiftUI
import CoreLocation
import FirebaseAuth

struct FriendInfoPanel: View {
    let friend: User
    let location: UserLocation?
    let onClose: () -> Void
    @State private var showChatView = false
    @State private var showCallOptions = false
    @State private var showingAnimation = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Header với close button
            headerSection
            
            // Avatar và thông tin chính
            profileSection
            
            // Location details
            if let location = location {
                locationSection(location)
            }
            
            // Action buttons
            actionButtonsSection
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 15, x: 0, y: 8)
        )
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
        HStack {
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
    }
    
    // MARK: - Profile Section
    
    private var profileSection: some View {
        VStack(spacing: 12) {
            // Avatar với status indicator
            ZStack(alignment: .bottomTrailing) {
                if let profileImage = friend.profileImageUrl {
                    AsyncImage(url: URL(string: profileImage)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.3))
                            Text(friend.initials)
                                .font(.title)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(width: 80, height: 80)
                        Text(friend.initials)
                            .font(.title)
                            .foregroundColor(.white)
                    }
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )
                }
                
                // Status indicator
                Circle()
                    .fill(friend.isOnline ? Color.green : Color.gray)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(Color.black, lineWidth: 3)
                    )
                    .offset(x: 4, y: 4)
            }
            
            // Name
            Text(friend.fullName)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            // Online status
            HStack(spacing: 6) {
                Circle()
                    .fill(friend.isOnline ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                Text(friend.isOnline ? "Đang hoạt động" : "Không hoạt động")
                    .font(.subheadline)
                    .foregroundColor(friend.isOnline ? .green : .gray)
            }
            
            // Last active timestamp
            if let lastSeen = friend.lastSeen {
                Text("Hoạt động \(formatRelativeTime(lastSeen))")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
    
    // MARK: - Location Section
    
    private func locationSection(_ location: UserLocation) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Thông tin vị trí")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("Tọa độ")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Text(formatCoordinate(location.toCoordinate()))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("Cập nhật")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Text(locationAge())
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(locationFreshnessColor)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        HStack(spacing: 16) {
            // Message button
            actionButton(
                icon: "message.fill",
                title: "Nhắn tin",
                color: .blue
            ) {
                showChatView = true
            }
            .sheet(isPresented: $showChatView) {
                ChatViewContainer(friend: friend)
            }
            
            // Call button
            actionButton(
                icon: "phone.fill",
                title: "Gọi điện",
                color: .green
            ) {
                showCallOptions = true
            }
            .actionSheet(isPresented: $showCallOptions) {
                ActionSheet(
                    title: Text("Gọi cho \(friend.fullName)"),
                    buttons: [
                        .default(Text("Gọi điện thoại")) {
                            handlePhoneCall()
                        },
                        .default(Text("Gọi video")) {
                            handleVideoCall()
                        },
                        .cancel(Text("Hủy"))
                    ]
                )
            }
            
            // Directions button
            actionButton(
                icon: "arrow.triangle.turn.up.right.diamond.fill",
                title: "Chỉ đường",
                color: .orange
            ) {
                handleDirections()
            }
            .disabled(location == nil)
            .opacity(location == nil ? 0.5 : 1.0)
        }
    }
    
    private func actionButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(color.opacity(0.3))
                            .overlay(
                                Circle()
                                    .stroke(color.opacity(0.5), lineWidth: 1)
                            )
                    )
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Methods
    
    private func formatCoordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        return String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }
    
    private func locationAge() -> String {
        guard let location = location else {
            return "Không xác định"
        }
        
        let locationDate = Date(timeIntervalSince1970: location.timestamp)
        return formatRelativeTime(locationDate)
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private var locationFreshnessColor: Color {
        guard let location = location else {
            return .gray
        }
        
        let oneHourAgo = Date().timeIntervalSince1970 - (60 * 60)
        if location.timestamp > oneHourAgo {
            return .green
        }
        
        let twentyFourHoursAgo = Date().timeIntervalSince1970 - (24 * 60 * 60)
        if location.timestamp > twentyFourHoursAgo {
            return .orange
        }
        
        return .red
    }
    
    // MARK: - Action Handlers
    
    private func handlePhoneCall() {
        if let url = URL(string: "tel://+84123456789") {
            UIApplication.shared.open(url)
        }
    }
    
    private func handleVideoCall() {
        print("Starting video call with \(friend.fullName)")
    }
    
    private func handleDirections() {
        guard let location = location else { return }
        
        let url = URL(string: "maps://?daddr=\(location.latitude),\(location.longitude)")
        if let url = url, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            let webUrl = URL(string: "https://maps.google.com/maps?daddr=\(location.latitude),\(location.longitude)")
            if let webUrl = webUrl {
                UIApplication.shared.open(webUrl)
            }
        }
    }
}

// MARK: - Chat View Container (Dark Theme)

struct ChatViewContainer: View {
    let friend: User
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Group {
                if let currentUserId = Auth.auth().currentUser?.uid {
                    ChatView(
                        chatId: getChatId(currentUserId: currentUserId),
                        otherUserId: friend.id
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarBackButtonHidden(true)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Đóng") {
                                presentationMode.wrappedValue.dismiss()
                            }
                            .foregroundColor(.white)
                        }
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("Vui lòng đăng nhập để chat")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("Bạn cần đăng nhập để có thể gửi tin nhắn")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        
                        Button("Đóng") {
                            presentationMode.wrappedValue.dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(Color.black)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func getChatId(currentUserId: String) -> String {
        return [currentUserId, friend.id].sorted().joined(separator: "_")
    }
}

// MARK: - Preview

#Preview {
    FriendInfoPanel(
        friend: User(id: "preview_id", fullName: "Nguyễn Văn A", email: "nguyenvana@example.com"),
        location: UserLocation(latitude: 21.0285, longitude: 105.8542, timestamp: Date().timeIntervalSince1970),
        onClose: {}
    )
    .background(Color.blue.opacity(0.3))
}
