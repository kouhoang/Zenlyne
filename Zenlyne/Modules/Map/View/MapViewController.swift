//
//  MapViewController.swift
//  Zenlyne
//
//  Created by admin on 19/3/25.
//

import SwiftUI
import MapboxMaps
import CoreLocation

struct MapViewController: View {
    @StateObject private var viewModel = LocationViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    
    @State private var showProfileView = false
    @State private var showFriendsListView = false
    @State private var showFriendRequestsView = false
    @State private var showAddFriendView = false
    @State private var selectedFriendId: String? = nil
    @State private var pendingRequestsCount: Int = 0
    
    var body: some View {
        ZStack {
            // Base Map View
            MapViewRepresentable(viewModel: viewModel)
                .ignoresSafeArea()
            
            // Overlay Views
            VStack {
                HStack {
                    Spacer()
                    
                    VStack(spacing: 10) { // Các nút xếp theo chiều dọc
                        // Profile Button
                        Button(action: {
                            showProfileView.toggle()
                        }) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                                .background(Color.white.clipShape(Circle()))
                                .shadow(radius: 4)
                        }
                        
                        // Friends List Button
                        Button(action: {
                            showFriendsListView.toggle()
                        }) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.green)
                                .background(Color.white.clipShape(Circle()))
                                .shadow(radius: 4)
                        }
                        
                        // Friend Requests Button
                        Button(action: {
                            showFriendRequestsView.toggle()
                        }) {
                            ZStack {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.purple)
                                    .background(Color.white.clipShape(Circle()))
                                    .shadow(radius: 4)
                                
                                // Hiển thị badge số lượng lời mời kết bạn
                                if pendingRequestsCount > 0 {
                                    Text("\(pendingRequestsCount)")
                                        .font(.caption)
                                        .padding(5)
                                        .foregroundColor(.white)
                                        .background(Color.red)
                                        .clipShape(Circle())
                                        .offset(x: 15, y: -15)
                                }
                            }
                        }
                        
                        // Add Friend Button
                        Button(action: {
                            showAddFriendView.toggle()
                        }) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 40))
                                .foregroundColor(.orange)
                                .background(Color.white.clipShape(Circle()))
                                .shadow(radius: 4)
                        }
                    }
                    .padding(.top, 10)
                    .padding(.trailing, 10)
                }
                
                Spacer()
                
                // Friend info panel (hiển thị khi chọn một người bạn)
                if let friendId = selectedFriendId, let friend = viewModel.getFriend(byId: friendId) {
                    FriendInfoPanel(
                        friend: friend,
                        location: viewModel.friendLocations[friendId],
                        onClose: { selectedFriendId = nil }
                    )
                    .transition(.move(edge: .bottom))
                    .padding(.bottom, 80)
                }
                
                // Bottom Row Buttons
                HStack {
                    Spacer()
                    
                    // Location Focus Button
                    LocationButton(
                        action: {
                            viewModel.focusOnUserLocation()
                        },
                        isTracking: viewModel.isTrackingLocation
                    )
                }
                .padding(.bottom, 30)
                .padding(.horizontal)
            }
            
            // Overlay Views (Sheets)
            .sheet(isPresented: $showProfileView) {
                ProfileViewController()
                    .environmentObject(authViewModel)
            }
            
            .sheet(isPresented: $showFriendsListView) {
                FriendsListView(viewModel: viewModel)
            }
            
            .sheet(isPresented: $showFriendRequestsView) {
                FriendRequestsView()
                    .environmentObject(authViewModel)
            }
            
            .sheet(isPresented: $showAddFriendView) {
                AddFriendView()
                    .environmentObject(authViewModel)
            }
        }
        .onAppear {
            // Cập nhật currentUser từ AuthViewModel
            if let user = authViewModel.currentUser {
                viewModel.currentUser = user
            }
            
            // Start tracking location when app appears
            viewModel.startTrackingLocation()
            
            // Thiết lập listener cho việc chọn bạn bè trên bản đồ
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("FriendSelected"),
                object: nil,
                queue: .main
            ) { notification in
                if let friendId = notification.userInfo?["friendId"] as? String {
                    self.selectedFriendId = friendId
                }
            }
            
            // Listener cho việc đóng panel thông tin khi tap vào map
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("MapTapped"),
                object: nil,
                queue: .main
            ) { _ in
                self.selectedFriendId = nil
            }
            
            // Kiểm tra số lượng lời mời kết bạn đang chờ
            checkPendingFriendRequests()
        }
        .onDisappear {
            // Dừng lắng nghe vị trí của bạn bè khi view biến mất
            viewModel.stopTrackingLocation()
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    // Kiểm tra số lượng lời mời kết bạn đang chờ
    private func checkPendingFriendRequests() {
        guard let userId = authViewModel.currentUser?.id else { return }
        
        let firebaseService = FirebaseService()
        firebaseService.getPendingFriendRequestsCount(for: userId) { count in
            DispatchQueue.main.async {
                self.pendingRequestsCount = count
            }
        }
    }
}

struct FriendInfoPanel: View {
    let friend: User
    let location: UserLocation?
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                // Avatar
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
                    
                    // Online indicator
                    if friend.isOnline {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                            .position(x: 48, y: 48)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.fullName)
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    if friend.isOnline {
                        Text("Online now")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    } else if let lastSeen = friend.lastSeen {
                        Text("Last seen \(lastSeen, formatter: RelativeDateTimeFormatter())")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    if let location = location {
                        let timeAgo = Date(timeIntervalSince1970: location.timestamp)
                        Text("Location updated \(timeAgo, formatter: RelativeDateTimeFormatter())")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
            }
            
            HStack(spacing: 20) {
                // Message button
                Button(action: {
                    // Xử lý gửi tin nhắn
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 20))
                        Text("Message")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // Call button
                Button(action: {
                    // Xử lý gọi điện
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 20))
                        Text("Call")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // Directions button
                Button(action: {
                    // Xử lý chỉ đường
                    if let location = location {
                        let url = URL(string: "maps://?daddr=\(location.latitude),\(location.longitude)")
                        if let url = url, UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        }
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.system(size: 20))
                        Text("Directions")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
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
}


#Preview {
    MapViewController()
}
