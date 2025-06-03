//
//  MapView.swift
//  Zenlyne
//
//  Created by admin on 19/3/25.
//

import SwiftUI
import MapboxMaps
import CoreLocation
import FirebaseAuth
import Combine

struct MapView: View {
    @StateObject private var viewModel = LocationViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    
    // UI State
    @State private var showProfileView = false
    @State private var showFriendsListView = false
    @State private var showFriendRequestsView = false
    @State private var showAddFriendView = false
    @State private var showConversationList = false
    @State private var selectedFriendId: String? = nil
    @State private var pendingRequestsCount: Int = 0
    @State private var showMapStyleMenu = false
    
    // Friend cluster support
    @State private var showClusterSelection: Bool = false
    @State private var selectedClusterFriendIds: [String] = []
    @State private var isDraggingClusterPanel: Bool = false
    @State private var clusterPanelOffset: CGSize = .zero
    @State private var clusterPanelHeight: CGFloat = 400
    
    // Map refresh trigger
    @State private var mapRefreshTrigger = false
    @State private var locationGroups: [LocationGroup] = []
    
    // Combine
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        ZStack {
            // Base Map View
            MapViewRepresentable(viewModel: viewModel)
                .ignoresSafeArea()
                .id(mapRefreshTrigger)
            
            // Overlay Views
            VStack {
                HStack {
                    Spacer()
                    
                    VStack(spacing: 10) {
                        // Profile Button
                        profileButton
                        
                        // Friends List Button
                        friendsListButton
                        
                        // Add Friend Button
                        addFriendButton
                        
                        // Chat button
                        chatButton
                        
                        // Map Style Button
                        MapStyleButton(viewModel: viewModel)
                    }
                    .padding(.top, 70)
                    .padding(.trailing, 8)
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
                clusterSelectionOverlay
            }
        }
        // Sheets for overlays
        .sheet(isPresented: $showProfileView) {
            ProfileView()
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showFriendsListView) {
            FriendsListView(locationViewModel: viewModel)
                .environmentObject(authViewModel)
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
            setupView()
        }
    }
    
    // MARK: - View Components
    
    private var profileButton: some View {
        Button(action: {
            showProfileView.toggle()
        }) {
            SafeProfileAvatarView(user: viewModel.currentUser)
                .frame(width: 50, height: 50)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 4)
        }
    }
    
    private var friendsListButton: some View {
        Button(action: {
            showFriendsListView.toggle()
        }) {
            Image("friends")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundColor(.green)
        }
    }
    
    private var addFriendButton: some View {
        Button(action: {
            showAddFriendView.toggle()
        }) {
            Image("add-friend")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundColor(.orange)
        }
    }
    
    private var chatButton: some View {
        Button(action: {
            showConversationList = true
        }) {
            ZStack {
                Image("chat")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundColor(.purple)
                
                MessageCountBadge()
            }
        }
    }
    
    private var clusterSelectionOverlay: some View {
        VStack {
            // Semi-transparent background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showClusterSelection = false
                    }
                }
                .transition(.opacity)
                .zIndex(2)
            
            Spacer()
            
            FriendClusterSelectionView(
                friends: viewModel.friends.filter { selectedClusterFriendIds.contains($0.id) },
                onFriendSelected: { friendId in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showClusterSelection = false
                        
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
                        if gesture.translation.height > 0 {
                            self.clusterPanelOffset = gesture.translation
                        }
                    }
                    .onEnded { gesture in
                        if gesture.translation.height > 100 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                self.showClusterSelection = false
                            }
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                self.clusterPanelOffset = .zero
                            }
                        }
                    }
            )
        }
    }
    
    // MARK: - Setup Methods
    
    private func setupView() {
        print("DEBUG: MapView appeared")
        
        setupCurrentUser()
        setupCombineObservers()
        
        // Start tracking location when app appears
        viewModel.startTrackingLocation()
        
        // Set up notification listeners
        setupNotificationListeners()
        
        // Check pending friend requests
        checkPendingFriendRequests()
    }
    
    private func setupCurrentUser() {
        if let user = authViewModel.currentUser {
            print("DEBUG: Current user set: \(user.fullName)")
            viewModel.currentUser = user
            loadCurrentUserAvatar()
        } else if let currentUserId = Auth.auth().currentUser?.uid,
                  let email = Auth.auth().currentUser?.email {
            print("DEBUG: Creating temporary user from Auth")
            let tempUser = User(
                id: currentUserId,
                fullName: Auth.auth().currentUser?.displayName ?? "User",
                email: email
            )
            viewModel.currentUser = tempUser
            loadCurrentUserAvatar()
        } else {
            print("DEBUG: No current user available")
        }
    }
    
    private func setupCombineObservers() {
        // Observe current user changes from AuthViewModel
        authViewModel.currentUserPublisher
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [self] user in
                viewModel.currentUser = user
                refreshMapMarkers()
            }
            .store(in: &cancellables)
        
        // Observe location tracking state
        viewModel.locationTrackingStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { state in
                switch state {
                case .denied:
                    print("DEBUG: Location access denied")
                case .error(let message):
                    print("DEBUG: Location error: \(message)")
                case .tracking:
                    print("DEBUG: Location tracking active")
                case .idle, .requesting:
                    break
                }
            }
            .store(in: &cancellables)
        
        // Observe user location changes
        viewModel.userLocationPublisher
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { location in
                print("DEBUG: User location updated via Combine: \(location.latitude), \(location.longitude)")
            }
            .store(in: &cancellables)
        
        // Observe friend locations changes and refresh map
        viewModel.friendLocationsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [self] locations in
                print("DEBUG: Friend locations updated via Combine: \(locations.count) locations")
                refreshMapMarkers()
            }
            .store(in: &cancellables)
        
        // Observe friends list changes
        viewModel.friendsPublisher
            .receive(on: DispatchQueue.main)
            .sink { friends in
                print("DEBUG: Friends list updated via Combine: \(friends.count) friends")
            }
            .store(in: &cancellables)
        
        // Observe map style changes
        viewModel.mapStylePublisher
            .receive(on: DispatchQueue.main)
            .sink { style in
                print("DEBUG: Map style changed to: \(style.displayName)")
                refreshMapMarkers()
            }
            .store(in: &cancellables)
        
        // Observe location groups (clusters) changes
        viewModel.locationGroupsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [self] groups in
                print("DEBUG: Location groups updated: \(groups.count) groups")
                locationGroups = groups
                refreshMapMarkers()
            }
            .store(in: &cancellables)
        
        // Observe zoom level changes
        viewModel.zoomLevelPublisher
            .receive(on: DispatchQueue.main)
            .sink { zoomLevel in
                print("DEBUG: Zoom level changed to: \(zoomLevel)")
            }
            .store(in: &cancellables)
        
        // Observe camera update requests
        viewModel.$shouldUpdateCamera
            .receive(on: DispatchQueue.main)
            .sink { [self] shouldUpdate in
                if shouldUpdate {
                    // Trigger map refresh which will update camera
                    refreshMapMarkers()
                    // Reset the flag
                    viewModel.shouldUpdateCamera = false
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadCurrentUserAvatar() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        let firebaseService = FirebaseService()
        firebaseService.getUserAvatar(userId: currentUserId) { avatarUrl in
            DispatchQueue.main.async {
                if let avatarUrl = avatarUrl {
                    print("DEBUG: Loaded current user avatar: \(avatarUrl)")
                    self.viewModel.currentUser.avatarUrl = avatarUrl
                    self.viewModel.currentUser.profileImageUrl = avatarUrl
                    self.refreshMapMarkers()
                } else {
                    print("DEBUG: No avatar found for current user")
                }
            }
        }
    }
    
    private func refreshMapMarkers() {
        mapRefreshTrigger.toggle()
    }
    
    private func setupNotificationListeners() {
        // Set up a listener to select friends on the map
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("FriendSelected"),
            object: nil,
            queue: .main
        ) { notification in
            if let friendId = notification.userInfo?["friendId"] as? String {
                print("DEBUG: Friend selected: \(friendId)")
                self.selectedFriendId = friendId
                self.viewModel.focusOnFriendLocation(friendId: friendId)
            }
        }
        
        // Listen for when user avatar is loaded from database
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("UserAvatarLoaded"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let userId = userInfo["userId"] as? String,
               let avatarUrl = userInfo["avatarUrl"] as? String,
               userId == Auth.auth().currentUser?.uid {
                print("DEBUG: User avatar loaded from database: \(avatarUrl)")
                self.viewModel.currentUser.avatarUrl = avatarUrl
                self.viewModel.currentUser.profileImageUrl = avatarUrl
                self.refreshMapMarkers()
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
                
                self.clusterPanelOffset = .zero
                self.selectedClusterFriendIds = friendIds
                
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.showClusterSelection = true
                }
                
                if let firstFriendId = friendIds.first {
                    self.viewModel.focusOnFriendLocation(friendId: firstFriendId)
                }
            }
        }
        
        // Listen for cluster toggle events
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ClusterToggled"),
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let clusterId = userInfo["clusterId"] as? String,
                  let isExpanded = userInfo["isExpanded"] as? Bool else {
                return
            }
            
            print("DEBUG: Cluster \(clusterId) toggled to \(isExpanded ? "expanded" : "collapsed")")
            
            // If expanded, show cluster selection panel
            if isExpanded {
                // Find the cluster friends
                if let group = self.locationGroups.first(where: {
                    $0.type == .cluster &&
                    $0.friendIds.sorted().joined(separator: "_") == clusterId
                }) {
                    self.selectedClusterFriendIds = group.friendIds
                    
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        self.showClusterSelection = true
                    }
                }
            }
            
            // Refresh map to show/hide expanded markers
            self.refreshMapMarkers()
        }
        
        // Listener for closing the info panel when tapping on the map
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MapTapped"),
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.selectedFriendId = nil
                self.showClusterSelection = false
            }
        }
        
        // Listen for avatar updates
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AvatarUpdated"),
            object: nil,
            queue: .main
        ) { notification in
            self.handleAvatarUpdate(notification)
        }
    }
    
    private func handleAvatarUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let userId = userInfo["userId"] as? String,
              let avatarUrl = userInfo["avatarUrl"] as? String else {
            return
        }
        
        // Update current user's avatar if it's them
        if userId == Auth.auth().currentUser?.uid {
            print("DEBUG: Updating current user avatar: \(avatarUrl)")
            viewModel.currentUser.avatarUrl = avatarUrl
            viewModel.currentUser.profileImageUrl = avatarUrl
        }
        
        // Update friend's avatar if it's one of them
        if let friendIndex = viewModel.friends.firstIndex(where: { $0.id == userId }) {
            print("DEBUG: Updating friend avatar for \(viewModel.friends[friendIndex].fullName): \(avatarUrl)")
            viewModel.friends[friendIndex].avatarUrl = avatarUrl
            viewModel.friends[friendIndex].profileImageUrl = avatarUrl
        }
        
        refreshMapMarkers()
    }
    
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

// Safe component for showing user avatar
struct SafeProfileAvatarView: View {
    let user: User
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.2))
            
            if let profileImageUrl = user.currentAvatarUrl,
               let url = URL(string: profileImageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(4)
                    case .failure(_), .empty:
                        Text(user.initials)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.blue)
                    @unknown default:
                        Text(user.initials)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.blue)
                    }
                }
            } else {
                Text(user.initials)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.blue)
            }
        }
    }
}

// Message count badge component
struct MessageCountBadge: View {
    @StateObject private var viewModel = ConversationListViewModel()
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
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingBadge = true
            }
            
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                viewModel.updateTotalUnreadCount()
            }
        }
    }
}

// Chat button integration
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

#Preview {
    MapView()
        .environmentObject(AuthViewModel())
}
