//
//  UpdatedFriendInfoPanel.swift
//  Zenlyne
//
//  Created by admin on 19/3/25.
//

import SwiftUI
import CoreLocation
import FirebaseAuth

struct UpdatedFriendInfoPanel: View {
    let friend: User
    let location: UserLocation?
    let onClose: () -> Void
    @State private var showChatView = false
    @State private var showCallOptions = false
    
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
    
    var body: some View {
        VStack(spacing: 12) {
            // Top section styled like the contact card
            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    // Close button (X) positioned at top-right
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                    }
                }
                
                // Avatar/initials with exact styling from the image
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 60, height: 60)
                    
                    if let profileImage = friend.profileImageUrl {
                        AsyncImage(url: URL(string: profileImage)) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Text(friend.initials)
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                    } else {
                        Text(friend.initials)
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
                
                // Name styled like in the image
                Text(friend.fullName)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                // Online status with green dot like in the image
                HStack(spacing: 4) {
                    Circle()
                        .fill(friend.isOnline ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    
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
            .padding(.bottom, 8)
            
            // Location details
            if let location = location {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vị trí")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text(formatCoordinate(location.toCoordinate()))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Thời gian")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text(locationAge())
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(locationFreshnessColor)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Action buttons with updated messaging functionality
            HStack(spacing: 20) {
                // Message button
                Button(action: {
                    showChatView = true
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 20))
                        Text("Nhắn tin")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .sheet(isPresented: $showChatView) {
                    ChatViewContainer(friend: friend)
                }
                
                // Call button
                Button(action: {
                    showCallOptions = true
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 20))
                        Text("Gọi điện")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
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
                Button(action: {
                    handleDirections()
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.system(size: 20))
                        Text("Chỉ đường")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(location == nil)
                .opacity(location == nil ? 0.5 : 1.0)
            }
            .foregroundColor(.blue)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal)
    }
    
    // MARK: - Action Handlers
    
    private func handlePhoneCall() {
        // Handle phone call here - you might want to get actual phone number from friend data
        if let url = URL(string: "tel://+84123456789") {
            UIApplication.shared.open(url)
        }
    }
    
    private func handleVideoCall() {
        // Handle video call here
        // This would connect to your video call implementation
        print("Starting video call with \(friend.fullName)")
    }
    
    private func handleDirections() {
        guard let location = location else { return }
        
        let url = URL(string: "maps://?daddr=\(location.latitude),\(location.longitude)")
        if let url = url, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            // Fallback to Google Maps web if Apple Maps is not available
            let webUrl = URL(string: "https://maps.google.com/maps?daddr=\(location.latitude),\(location.longitude)")
            if let webUrl = webUrl {
                UIApplication.shared.open(webUrl)
            }
        }
    }
}

// MARK: - Chat View Container (Updated for new MVVM architecture)

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
                        }
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("Vui lòng đăng nhập để chat")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Bạn cần đăng nhập để có thể gửi tin nhắn")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Đóng") {
                            presentationMode.wrappedValue.dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func getChatId(currentUserId: String) -> String {
        return [currentUserId, friend.id].sorted().joined(separator: "_")
    }
}

// MARK: - Extension for UserLocation

//extension UserLocation {
//    func toCoordinate() -> CLLocationCoordinate2D {
//        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
//    }
//}

// MARK: - Preview

#Preview {
    UpdatedFriendInfoPanel(
        friend: User(id: "preview_id", fullName: "Nguyễn Văn A", email: "nguyenvana@example.com"),
        location: UserLocation(latitude: 21.0285, longitude: 105.8542, timestamp: Date().timeIntervalSince1970),
        onClose: {}
    )
}
