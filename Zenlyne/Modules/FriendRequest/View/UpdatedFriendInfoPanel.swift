//
//  UpdatedFriendInfoPanel.swift
//  Zenlyne
//
//  Created by admin on 26/4/25.
//

import SwiftUI
import UIKit
import FirebaseAuth

// Extension to update the existing FriendInfoPanel with messaging functionality
//struct UpdatedFriendInfoPanel: View {
//    let friend: User
//    let location: UserLocation?
//    let onClose: () -> Void
//    @State private var showChatView = false
//    @State private var showCallOptions = false
//    
//    // Format coordinates nicely
//    private func formatCoordinate(_ coordinate: CLLocationCoordinate2D) -> String {
//        return String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
//    }
//    
//    // Calculate how old the location data is
//    private func locationAge() -> String {
//        guard let location = location else {
//            return "Không xác định"
//        }
//        
//        let locationDate = Date(timeIntervalSince1970: location.timestamp)
//        let formatter = RelativeDateTimeFormatter()
//        formatter.unitsStyle = .short
//        
//        return formatter.localizedString(for: locationDate, relativeTo: Date())
//    }
//    
//    // Determine location freshness color
//    private var locationFreshnessColor: Color {
//        guard let location = location else {
//            return .gray
//        }
//        
//        let oneHourAgo = Date().timeIntervalSince1970 - (60 * 60)
//        if location.timestamp > oneHourAgo {
//            return .green
//        }
//        
//        let twentyFourHoursAgo = Date().timeIntervalSince1970 - (24 * 60 * 60)
//        if location.timestamp > twentyFourHoursAgo {
//            return .orange
//        }
//        
//        return .red
//    }
//    
//    var body: some View {
//        VStack(spacing: 12) {
//            // Top section styled like the contact card in the image
//            VStack(spacing: 8) {
//                HStack {
//                    Spacer()
//                    // Close button (X) positioned at top-right
//                    Button(action: onClose) {
//                        Image(systemName: "xmark.circle.fill")
//                            .font(.system(size: 20))
//                            .foregroundColor(.gray)
//                    }
//                }
//                
//                // Avatar/initials with exact styling from the image
//                ZStack {
//                    Circle()
//                        .fill(Color.blue.opacity(0.2))
//                        .frame(width: 60, height: 60)
//                    
//                    if let profileImage = friend.profileImageUrl {
//                        AsyncImage(url: URL(string: profileImage)) { image in
//                            image
//                                .resizable()
//                                .scaledToFill()
//                        } placeholder: {
//                            Text(friend.initials)
//                                .font(.title2)
//                                .foregroundColor(.blue)
//                        }
//                        .frame(width: 56, height: 56)
//                        .clipShape(Circle())
//                    } else {
//                        Text(friend.initials)
//                            .font(.title2)
//                            .foregroundColor(.blue)
//                    }
//                }
//                
//                // Name styled like in the image
//                Text(friend.fullName)
//                    .font(.headline)
//                    .fontWeight(.semibold)
//                
//                // Online status with green dot like in the image
//                HStack(spacing: 4) {
//                    Circle()
//                        .fill(friend.isOnline ? Color.green : Color.gray)
//                        .frame(width: 6, height: 6)
//                    
//                    Text(friend.isOnline ? "Đang hoạt động" : "Không hoạt động")
//                        .font(.subheadline)
//                        .foregroundColor(friend.isOnline ? .green : .gray)
//                }
//                
//                // Last active timestamp
//                if let lastSeen = friend.lastSeen {
//                    Text("Hoạt động \(lastSeen, formatter: RelativeDateTimeFormatter())")
//                        .font(.caption)
//                        .foregroundColor(.gray)
//                }
//            }
//            .padding(.bottom, 8)
//            
//            // Location details
//            if let location = location {
//                HStack(alignment: .top) {
//                    VStack(alignment: .leading, spacing: 4) {
//                        Text("Vị trí")
//                            .font(.caption)
//                            .foregroundColor(.gray)
//                        
//                        Text(formatCoordinate(location.toCoordinate()))
//                            .font(.caption)
//                            .fontWeight(.medium)
//                    }
//                    
//                    Spacer()
//                    
//                    VStack(alignment: .trailing, spacing: 4) {
//                        Text("Thời gian")
//                            .font(.caption)
//                            .foregroundColor(.gray)
//                        
//                        Text(locationAge())
//                            .font(.caption)
//                            .fontWeight(.medium)
//                            .foregroundColor(locationFreshnessColor)
//                    }
//                }
//                .padding(.horizontal, 4)
//                .padding(.vertical, 8)
//                .background(Color.gray.opacity(0.1))
//                .cornerRadius(8)
//            }
//            
//            // Action buttons with updated messaging functionality
//            HStack(spacing: 20) {
//                // Message button
//                Button(action: {
//                    showChatView = true
//                }) {
//                    VStack(spacing: 4) {
//                        Image(systemName: "message.fill")
//                            .font(.system(size: 20))
//                        Text("Nhắn tin")
//                            .font(.caption)
//                    }
//                    .frame(maxWidth: .infinity)
//                }
//                .fullScreenCover(isPresented: $showChatView) {
//                    // Navigate to chat with this friend
//                    NavigationView {
//                        ChatView(
//                            viewModel: MessagingViewModel(),
//                            chatId: [Auth.auth().currentUser?.uid ?? "", friend.id].sorted().joined(separator: "_"),
//                            otherUserId: friend.id
//                        )
//                    }
//                }
//                
//                // Call button
//                Button(action: {
//                    showCallOptions = true
//                }) {
//                    VStack(spacing: 4) {
//                        Image(systemName: "phone.fill")
//                            .font(.system(size: 20))
//                        Text("Gọi điện")
//                            .font(.caption)
//                    }
//                    .frame(maxWidth: .infinity)
//                }
//                .actionSheet(isPresented: $showCallOptions) {
//                    ActionSheet(
//                        title: Text("Gọi cho \(friend.fullName)"),
//                        buttons: [
//                            .default(Text("Gọi điện thoại")) {
//                                // Handle phone call here
//                                if let url = URL(string: "tel://+84123456789") {
//                                    UIApplication.shared.open(url)
//                                }
//                            },
//                            .default(Text("Gọi video")) {
//                                // Handle video call here
//                                // This would connect to your video call implementation
//                            },
//                            .cancel(Text("Hủy"))
//                        ]
//                    )
//                }
//                
//                // Directions button
//                Button(action: {
//                    if let location = location {
//                        let url = URL(string: "maps://?daddr=\(location.latitude),\(location.longitude)")
//                        if let url = url, UIApplication.shared.canOpenURL(url) {
//                            UIApplication.shared.open(url)
//                        }
//                    }
//                }) {
//                    VStack(spacing: 4) {
//                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
//                            .font(.system(size: 20))
//                        Text("Chỉ đường")
//                            .font(.caption)
//                    }
//                    .frame(maxWidth: .infinity)
//                }
//                .disabled(location == nil)
//                .opacity(location == nil ? 0.5 : 1.0)
//            }
//            .foregroundColor(.blue)
//        }
//        .padding()
//        .background(
//            RoundedRectangle(cornerRadius: 16)
//                .fill(Color.white)
//                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
//        )
//        .padding(.horizontal)
//        .onAppear {
//            // Create chat if it doesn't exist yet
//            if let currentUserId = Auth.auth().currentUser?.uid {
//                let messagingService = MessagingService()
//                messagingService.createChatIfNeeded(with: friend.id) { _ in }
//            }
//        }
//    }
//}
