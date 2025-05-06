//
//  MapViewController.swift
//  Zenlyne
//
//  Created by admin on 19/3/25.
//

import SwiftUI
import MapboxMaps
import CoreLocation
import FirebaseAuth

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
                    
                    VStack(spacing: 10) {
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
                        
                        // Button for message count badge - wrapped in AnyView to fix the error
                        AnyView(
                            MessageCountButton()
                        )
                    }
                    .padding(.top, 70)
                    .padding(.trailing, 0)
                }
                
                Spacer()
                
                // Friend info panel
                if let friendId = selectedFriendId, let friend = viewModel.getFriend(byId: friendId) {
                    UpdatedFriendInfoPanel(
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
            print("DEBUG: MapViewController appeared")
            
            // Update currentUser from AuthViewModel
            if let user = authViewModel.currentUser {
                print("DEBUG: Current user set: \(user.fullName)")
                viewModel.currentUser = user
            } else {
                print("DEBUG: No current user from AuthViewModel")
            }
            
            // Start tracking location when app appears
            viewModel.startTrackingLocation()
            
            // Đảm bảo chúng ta load bạn bè và vị trí của họ
            if let currentUserId = Auth.auth().currentUser?.uid {
                print("DEBUG: Loading friends for current user: \(currentUserId)")
                let friendViewModel = FriendRequestViewModel()
                friendViewModel.fetchFriends(forUserId: currentUserId) { friends in
                    print("DEBUG: Loaded \(friends.count) friends from Firebase")
                    DispatchQueue.main.async {
                        self.viewModel.friends = friends
                        
                        if !friends.isEmpty {
                            let friendIds = friends.map { $0.id }
                            print("DEBUG: Starting to observe \(friendIds.count) friends")
                            self.viewModel.startObservingFriendLocations(friendIds: friendIds)
                            self.viewModel.startObservingFriendOnlineStatus(friendIds: friendIds)
                        }
                    }
                }
            } else {
                print("DEBUG: No current user ID available")
            }
            
            // Set up a listener to select friends on the map
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("FriendSelected"),
                object: nil,
                queue: .main
            ) { notification in
                if let friendId = notification.userInfo?["friendId"] as? String {
                    print("DEBUG: Friend selected: \(friendId)")
                    self.selectedFriendId = friendId
                    
                    // Đảm bảo tập trung vị trí vào bạn bè được chọn
                    self.viewModel.focusOnFriendLocation(friendId: friendId)
                }
            }
            
            // Listener for closing the info panel when tapping on the map
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("MapTapped"),
                object: nil,
                queue: .main
            ) { _ in
                self.selectedFriendId = nil
            }
            
            // Check the number of pending friend requests
            checkPendingFriendRequests()
        }
    }
    
    // Check the number of pending friend requests
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

// Message Badge Button that conforms to View
struct MessageCountButton: View {
    @StateObject private var viewModel = MessagingViewModel()
    @State private var showingBadge = false
    @State private var showConversationList = false
    
    var body: some View {
        Button(action: {
            showConversationList = true
        }) {
            ZStack {
                Image(systemName: "message.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.purple)
                    .background(Color.white.clipShape(Circle()))
                    .shadow(radius: 4)
                
                if viewModel.totalUnreadCount > 0 {
                    Text("\(viewModel.totalUnreadCount)")
                        .font(.caption)
                        .padding(5)
                        .foregroundColor(.white)
                        .background(Color.red)
                        .clipShape(Circle())
                        .offset(x: 15, y: -15)
                        .opacity(showingBadge ? 1 : 0)
                }
            }
        }
        .fullScreenCover(isPresented: $showConversationList) {
            NavigationView {
                ConversationListView()
            }
        }
        .onAppear {
            viewModel.updateTotalUnreadCount()
            
            // Add a small delay so the animation is visible
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingBadge = true
            }
            
            // Set up a timer to refresh unread count periodically
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                viewModel.updateTotalUnreadCount()
            }
        }
    }
}

struct UpdatedFriendInfoPanel: View {
    let friend: User
    let location: UserLocation?
    let onClose: () -> Void
    @State private var showChatView = false
    @State private var showCallOptions = false
    
    // Format coordinates nicely
    private func formatCoordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        return String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }
    
    // Calculate how old the location data is
    private func locationAge() -> String {
        guard let location = location else {
            return "Không xác định"
        }
        
        let locationDate = Date(timeIntervalSince1970: location.timestamp)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        
        return formatter.localizedString(for: locationDate, relativeTo: Date())
    }
    
    // Determine location freshness color
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
            // Top section styled like the contact card in the image
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
                    Text("Hoạt động \(lastSeen, formatter: RelativeDateTimeFormatter())")
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
                // Message button - Using ChatButtonView to fix the View issue
                ChatButtonView(friend: friend)
                
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
                                // Handle phone call here
                                if let url = URL(string: "tel://+84123456789") {
                                    UIApplication.shared.open(url)
                                }
                            },
                            .default(Text("Gọi video")) {
                                // Handle video call here
                                // This would connect to your video call implementation
                            },
                            .cancel(Text("Hủy"))
                        ]
                    )
                }
                
                // Directions button
                Button(action: {
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
}

#Preview {
    MapViewController()
}
