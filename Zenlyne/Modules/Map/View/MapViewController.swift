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
    @State private var showConversationList = false
    @State private var selectedFriendId: String? = nil
    @State private var pendingRequestsCount: Int = 0
    
    // Friend cluster support
    @State private var showClusterSelection: Bool = false
    @State private var selectedClusterFriendIds: [String] = []
    @State private var isDraggingClusterPanel: Bool = false
    @State private var clusterPanelOffset: CGSize = .zero
    @State private var clusterPanelHeight: CGFloat = 400  // Default height, will be adjusted dynamically
    
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
                        // Profile Button with avatar - KEEP THE ROUNDED SQUARE
                        Button(action: {
                            showProfileView.toggle()
                        }) {
                            ProfileAvatarView(user: viewModel.currentUser)
                                .frame(width: 50, height: 50)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(radius: 4)
                        }
                        
                        // Friends List Button - NO CIRCLE, JUST ICON
                        Button(action: {
                            showFriendsListView.toggle()
                        }) {
                            Image("friends") // Using your asset name
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                                .foregroundColor(.green)
                        }
                        
                        // Add Friend Button - NO CIRCLE, JUST ICON
                        Button(action: {
                            showAddFriendView.toggle()
                        }) {
                            Image("add-friend") // Using your asset name
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                                .foregroundColor(.orange)
                        }
                        
                        // Chat button - NO CIRCLE, JUST ICON WITH BADGE
                        Button(action: {
                            showConversationList = true
                        }) {
                            ZStack {
                                Image("chat") // Using your asset name
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 40, height: 40)
                                    .foregroundColor(.purple)
                                
                                MessageCountBadge()
                            }
                        }
                    }
                    .padding(.top, 70)
                    .padding(.trailing, 8) // CHANGED FROM 0 TO 8
                }
                
                Spacer()
                
                // Friend info panel
                if let friendId = selectedFriendId, let friend = viewModel.getFriend(byId: friendId) {
                    UpdatedFriendInfoPanel(
                        friend: friend,
                        location: viewModel.friendLocations[friendId],
                        onClose: { selectedFriendId = nil }
                    )
                    .transition(.bottomSlide)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedFriendId != nil)
                    .zIndex(1)
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
            
            // Friend Cluster Selection Overlay
            if showClusterSelection {
                // Semi-transparent background overlay
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showClusterSelection = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(2)
                
                VStack {
                    Spacer()
                    
                    EnhancedFriendClusterSelectionView(
                        friends: viewModel.friends.filter { selectedClusterFriendIds.contains($0.id) },
                        onFriendSelected: { friendId in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showClusterSelection = false
                                
                                // Short delay before showing individual friend info
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    selectedFriendId = friendId
                                    viewModel.focusOnFriendLocation(friendId: friendId)
                                }
                            }
                        },
                        onClose: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showClusterSelection = false
                            }
                        }
                    )
                    .transition(.bottomSlide)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showClusterSelection)
                    .zIndex(3)
                    .offset(y: clusterPanelOffset.height)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                // Only allow dragging down
                                if gesture.translation.height > 0 {
                                    self.clusterPanelOffset = gesture.translation
                                }
                            }
                            .onEnded { gesture in
                                // If dragged down more than 100 points, dismiss
                                if gesture.translation.height > 100 {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        self.showClusterSelection = false
                                    }
                                } else {
                                    // Reset offset
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        self.clusterPanelOffset = .zero
                                    }
                                }
                            }
                    )
                }
            }
        }
        // Now using sheets instead of full screen covers for all overlays
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
        .sheet(isPresented: $showConversationList) {
            ConversationListView()
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
            
            // Make sure they load their friends and location
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
                    
                    // Make sure the location is focused on the selected friend
                    self.viewModel.focusOnFriendLocation(friendId: friendId)
                }
            }
            
            // Set up a listener for friend cluster selections
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("FriendClusterSelected"),
                object: nil,
                queue: .main
            ) { notification in
                if let friendIds = notification.userInfo?["friendIds"] as? [String] {
                    print("DEBUG: Friend cluster selected with \(friendIds.count) friends")
                    
                    // Reset any previous panel state
                    self.clusterPanelOffset = .zero
                    
                    // Update the selected cluster data
                    self.selectedClusterFriendIds = friendIds
                    
                    // Show the cluster selection panel with animation
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        self.showClusterSelection = true
                    }
                    
                    // Focus the camera on the cluster
                    if let firstFriendId = friendIds.first {
                        self.viewModel.focusOnFriendLocation(friendId: firstFriendId)
                    }
                }
            }
            
            // Listener for closing the info panel when tapping on the map
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("MapTapped"),
                object: nil,
                queue: .main
            ) { _ in
                // Close panels with animation
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.selectedFriendId = nil
                    self.showClusterSelection = false
                }
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

// Helper extension to create combined animation for transitions
extension AnyTransition {
    static var bottomSlide: AnyTransition {
        AnyTransition.move(edge: .bottom).combined(with: .opacity)
    }
}

// New component for showing user avatar
struct ProfileAvatarView: View {
    let user: User
    
    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.2))
            
            // User profile image or initials
            if let profileImageUrl = user.profileImageUrl,
               let url = URL(string: profileImageUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Text(user.initials)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.blue)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(4)
            } else {
                Text(user.initials)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.blue)
            }
        }
    }
}

// Separate component for message count badge
struct MessageCountBadge: View {
    @StateObject private var viewModel = MessagingViewModel()
    @State private var showingBadge = false
    
    var body: some View {
        ZStack {
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

// Chat button integration - FIXED
struct ChatButtonView: View {
    let friend: User
    @State private var showChatView = false
    
    var body: some View {
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
    }
}

// This is a separate container view to handle all the chat setup
struct ChatViewContainer: View {
    let friend: User
    @StateObject private var viewModel = MessagingViewModel()
    
    var body: some View {
        Group {
            if let currentUserId = Auth.auth().currentUser?.uid {
                ChatView(
                    viewModel: viewModel,
                    chatId: getChatId(currentUserId: currentUserId),
                    otherUserId: friend.id
                )
                .onAppear {
                    setupChat(currentUserId: currentUserId)
                }
            } else {
                Text("Please log in to chat")
                    .padding()
            }
        }
    }
    
    // Helper method to get chat ID
    private func getChatId(currentUserId: String) -> String {
        return [currentUserId, friend.id].sorted().joined(separator: "_")
    }
    
    // Helper method to set up the chat
    private func setupChat(currentUserId: String) {
        // Pre-load the friend info
        viewModel.chatUsers[friend.id] = friend
        
        // Create chat if needed
        FirebaseChatManager.shared.chatService.createChatIfNeeded(with: friend.id) { _ in }
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
        return formatRelativeTime(locationDate)
    }
    
    // Helper to format relative time
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
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
                
                // Last active timestamp - FIXED
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
                    // This would navigate to this location
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
                    if let profileImageUrl = friend.profileImageUrl,
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
                            // Fixed formatter issue
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
                if let lastLocation = friend.lastLocation {
                    // This would display distance if available
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
                    .opacity(0.01) // Almost invisible but makes the whole row tappable
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
    MapViewController()
}
