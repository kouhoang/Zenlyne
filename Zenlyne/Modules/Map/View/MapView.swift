//
//  MapViewController.swift
//  Zenlyne
//
//  Created by kou on 4/6/25.

//

import SwiftUI
import MapboxMaps
import CoreLocation
import FirebaseAuth
import Combine

struct MapView: View {
    @StateObject private var viewModel = LocationViewModel()
    @StateObject private var clusterAnimationManager = ClusterAnimationManager()
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
    
    // NEW: Same location support
    @State private var showSameLocationSheet: Bool = false
    @State private var sameLocationUsers: [User] = []
    @State private var sameLocationCoordinate: CLLocationCoordinate2D?
    
    // Smart refresh management
    @State private var needsMapRefresh: Bool = false
    @State private var lastRefreshTrigger: Date = Date()
    @State private var locationGroups: [LocationGroup] = []
    
    // Animation state
    @State private var expandedClusters: Set<String> = []
    @State private var animatingClusters: Set<String> = []
    
    // User interaction tracking
    @State private var isUserInteractingWithMap: Bool = false
    @State private var lastUserMapInteraction: Date = Date()
    
    // Combine
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        ZStack {
            // Base Map View
            MapViewRepresentable(viewModel: viewModel)
                .ignoresSafeArea()
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UserMapInteractionStarted"))) { _ in
                    isUserInteractingWithMap = true
                    lastUserMapInteraction = Date()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UserMapInteractionEnded"))) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isUserInteractingWithMap = false
                    }
                }
            
            // Overlay Views
            VStack {
                HStack {
                    // Location display in top-left corner
                    VStack(alignment: .leading) {
                        LocationDisplayView(reverseGeocodingService: viewModel.reverseGeocodingService)
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
                        
                        Spacer()
                    }
                    .padding(.top, 50)
                    .padding(.leading, 8)
                    
                    Spacer()
                    
                    VStack(spacing: 10) {
                        profileButton
                        friendsListButton
                        addFriendButton
                        chatButton
                        SmartMapStyleButton(viewModel: viewModel)
                    }
                    .padding(.top, 20)
                    .padding(.trailing, 8)
                }
                
                Spacer()
                
                // Friend info panel
                if let friendId = selectedFriendId, let friend = viewModel.getFriend(byId: friendId) {
                    FriendInfoPanel(
                        friend: friend,
                        location: viewModel.friendLocations[friendId],
                        onClose: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedFriendId = nil
                            }
                        }
                    )
                    .transition(.bottomSlide)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedFriendId != nil)
                    .zIndex(1)
                    .padding(.bottom, 80)
                }
                
                // Same Location Users Panel
                if showSameLocationSheet && !sameLocationUsers.isEmpty {
                    SameLocationUsersPanel(
                        users: sameLocationUsers,
                        location: sameLocationCoordinate != nil ? UserLocation(coordinate: sameLocationCoordinate!) : nil,
                        onUserSelected: { userId in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showSameLocationSheet = false
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                selectedFriendId = userId
                                focusOnFriendSafely(friendId: userId)
                            }
                        },
                        onClose: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showSameLocationSheet = false
                            }
                        }
                    )
                    .transition(.bottomSlide)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showSameLocationSheet)
                    .zIndex(4)
                    .padding(.bottom, 80)
                }
                
                // Cluster expansion info overlay
                if !animatingClusters.isEmpty {
                    ClusterExpansionIndicator(
                        animatingClusters: Array(animatingClusters),
                        viewModel: viewModel
                    )
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: animatingClusters.isEmpty)
                    .zIndex(2)
                    .padding(.bottom, 120)
                }
                
                // Bottom Row Buttons
                HStack {
                    Spacer()
                    
                    SmartLocationButton(
                        viewModel: viewModel,
                        isUserInteracting: isUserInteractingWithMap
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showProfileView.toggle()
            }
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showFriendsListView.toggle()
            }
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showAddFriendView.toggle()
            }
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
                            focusOnFriendSafely(friendId: friendId)
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
    
    // MARK: - Smart Setup Methods
    
    private func setupView() {
        print("DEBUG: MapView appeared - Smart setup with same-location support")
        
        setupCurrentUser()
        setupSmartCombineObservers()
        setupClusterAnimationObservers()
        
        viewModel.startTrackingLocation()
        setupNotificationListeners()
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
    
    private func setupSmartCombineObservers() {
        // Observe current user changes from AuthViewModel
        authViewModel.currentUserPublisher
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [self] user in
                viewModel.currentUser = user
                triggerSmartRefresh(reason: "User changed")
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
        
        // Observe friend locations changes - SMART refresh only
        viewModel.friendLocationsPublisher
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [self] locations in
                print("DEBUG: Friend locations updated via Combine: \(locations.count) locations")
                if shouldRefreshForLocationChanges() {
                    triggerSmartRefresh(reason: "Friend locations changed")
                }
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
                triggerSmartRefresh(reason: "Map style changed")
            }
            .store(in: &cancellables)
        
        // Observe location groups (clusters) changes
        viewModel.locationGroupsPublisher
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [self] groups in
                print("DEBUG: Location groups updated: \(groups.count) groups")
                locationGroups = groups
            }
            .store(in: &cancellables)
        
        // Observe zoom level changes
        viewModel.zoomLevelPublisher
            .receive(on: DispatchQueue.main)
            .sink { zoomLevel in
                print("DEBUG: Zoom level changed to: \(zoomLevel)")
                
                if zoomLevel < 12.0 && !expandedClusters.isEmpty && !isUserInteractingWithMap {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        collapseAllClusters()
                    }
                }
            }
            .store(in: &cancellables)
        
        // Observe camera update requests
        viewModel.$shouldUpdateCamera
            .receive(on: DispatchQueue.main)
            .sink { [self] shouldUpdate in
                if shouldUpdate && !isUserInteractingWithMap {
                    print("DEBUG: Camera update requested and allowed")
                } else if shouldUpdate && isUserInteractingWithMap {
                    print("DEBUG: Camera update requested but blocked - user is interacting")
                    viewModel.shouldUpdateCamera = false
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Smart Refresh Logic
    
    private func shouldRefreshForLocationChanges() -> Bool {
        if isUserInteractingWithMap {
            return false
        }
        
        let timeSinceLastRefresh = Date().timeIntervalSince(lastRefreshTrigger)
        if timeSinceLastRefresh < 2.0 {
            return false
        }
        
        return true
    }
    
    private func triggerSmartRefresh(reason: String) {
        guard !isUserInteractingWithMap,
              Date().timeIntervalSince(lastRefreshTrigger) > 1.0 else {
            print("DEBUG: Skipped refresh for '\(reason)' - user interacting or too frequent")
            return
        }
        
        print("DEBUG: Smart refresh triggered for: \(reason)")
        lastRefreshTrigger = Date()
        
        DispatchQueue.main.async {
            self.needsMapRefresh.toggle()
        }
    }
    
    private func focusOnFriendSafely(friendId: String) {
        guard !isUserInteractingWithMap else {
            print("DEBUG: Skipped focus - user is interacting with map")
            return
        }
        
        viewModel.focusOnFriendLocation(friendId: friendId)
    }
    
    private func collapseAllClusters() {
        clusterAnimationManager.cancelAllAnimations()
        expandedClusters.removeAll()
        animatingClusters.removeAll()
        viewModel.friendLocationGrouper.collapseAllClusters()
        
        print("DEBUG: Collapsed all clusters")
    }
    
    private func setupClusterAnimationObservers() {
        clusterAnimationManager.animationStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [self] animationStates in
                animatingClusters = Set(animationStates.keys)
                
                for (clusterId, state) in animationStates {
                    switch state {
                    case .expanded:
                        expandedClusters.insert(clusterId)
                    case .contracted:
                        expandedClusters.remove(clusterId)
                    case .expanding, .contracting, .animating:
                        break
                    case .idle:
                        break
                    }
                }
            }
            .store(in: &cancellables)
        
        clusterAnimationManager.animationCompletionPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [self] (clusterId, finalState) in
                print("DEBUG: Cluster \(clusterId) animation completed with state: \(finalState)")
                
                switch finalState {
                case .expanded:
                    expandedClusters.insert(clusterId)
                case .contracted:
                    expandedClusters.remove(clusterId)
                default:
                    break
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
                } else {
                    print("DEBUG: No avatar found for current user")
                }
            }
        }
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
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.selectedFriendId = friendId
                }
                self.focusOnFriendSafely(friendId: friendId)
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
                    self.focusOnFriendSafely(friendId: firstFriendId)
                }
            }
        }
        
        // NEW: Listen for same-location group selections
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SameLocationGroupSelected"),
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let friendIds = userInfo["friendIds"] as? [String],
                  let latitude = userInfo["latitude"] as? Double,
                  let longitude = userInfo["longitude"] as? Double else {
                return
            }
            
            print("DEBUG: Same-location group selected with \(friendIds.count) friends")
            
            // Get the users at this location
            let usersAtLocation = self.viewModel.friends.filter { friendIds.contains($0.id) }
            
            // Set the data for the sheet
            self.sameLocationUsers = usersAtLocation
            self.sameLocationCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            
            // Show the sheet
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.showSameLocationSheet = true
            }
            
            // Optional: Focus on the location (but don't interrupt user)
            if !self.isUserInteractingWithMap {
                self.viewModel.cameraOptions = CameraOptions(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    zoom: 15.0,
                    bearing: 0,
                    pitch: 0
                )
                self.viewModel.shouldUpdateCamera = true
            }
        }
        
        // Listen for cluster toggle events with smooth animation
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ClusterToggled"),
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let clusterId = userInfo["clusterId"] as? String,
                  let isExpanded = userInfo["isExpanded"] as? Bool,
                  let latitude = userInfo["latitude"] as? Double,
                  let longitude = userInfo["longitude"] as? Double else {
                return
            }
            
            print("DEBUG: Cluster \(clusterId) toggled to \(isExpanded ? "expanded" : "collapsed")")
            
            let clusterCenter = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            
            if isExpanded {
                self.startClusterExpansion(clusterId: clusterId, center: clusterCenter)
            } else {
                self.startClusterContraction(clusterId: clusterId, center: clusterCenter)
            }
        }
        
        // Listen for cluster animation updates
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ClusterAnimationUpdate"),
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let clusterId = userInfo["clusterId"] as? String,
                  let positions = userInfo["positions"] as? [String: CLLocationCoordinate2D],
                  let progress = userInfo["progress"] as? Double,
                  let type = userInfo["type"] as? String else {
                return
            }
            
            print("DEBUG: Cluster \(clusterId) animation update: \(type) progress \(progress)")
        }
        
        // Listener for closing panels when tapping on the map
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MapTapped"),
            object: nil,
            queue: .main
        ) { _ in
            if !self.isUserInteractingWithMap {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.selectedFriendId = nil
                    self.showClusterSelection = false
                    self.showSameLocationSheet = false
                    self.collapseAllClusters()
                }
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
    
    // MARK: - Cluster Animation Helpers
    
    private func startClusterExpansion(clusterId: String, center: CLLocationCoordinate2D) {
        guard let group = locationGroups.first(where: {
            $0.type == .cluster &&
            $0.friendIds.sorted().joined(separator: "_") == clusterId
        }) else {
            print("DEBUG: Could not find group for cluster \(clusterId)")
            return
        }
        
        print("DEBUG: Starting cluster expansion for \(clusterId) with \(group.friendIds.count) friends")
        
        animatingClusters.insert(clusterId)
        
        clusterAnimationManager.animateClusterExpansion(
            clusterId: clusterId,
            friendIds: group.friendIds,
            clusterCenter: center,
            targetPositions: group.relativePositions,
            configuration: nil
        ) {
            print("DEBUG: Cluster expansion animation completed for \(clusterId)")
            
            DispatchQueue.main.async {
                self.animatingClusters.remove(clusterId)
                self.expandedClusters.insert(clusterId)
            }
        }
    }
    
    private func startClusterContraction(clusterId: String, center: CLLocationCoordinate2D) {
        guard let group = locationGroups.first(where: {
            $0.type == .cluster &&
            $0.friendIds.sorted().joined(separator: "_") == clusterId
        }) else {
            print("DEBUG: Could not find group for cluster \(clusterId)")
            return
        }
        
        print("DEBUG: Starting cluster contraction for \(clusterId)")
        
        animatingClusters.insert(clusterId)
        
        clusterAnimationManager.animateClusterContraction(
            clusterId: clusterId,
            friendIds: group.friendIds,
            startPositions: group.relativePositions,
            targetCenter: center,
            configuration: nil
        ) {
            print("DEBUG: Cluster contraction animation completed for \(clusterId)")
            
            DispatchQueue.main.async {
                self.animatingClusters.remove(clusterId)
                self.expandedClusters.remove(clusterId)
            }
        }
    }
    
    private func handleAvatarUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let userId = userInfo["userId"] as? String,
              let avatarUrl = userInfo["avatarUrl"] as? String else {
            return
        }
        
        if userId == Auth.auth().currentUser?.uid {
            print("DEBUG: Updating current user avatar: \(avatarUrl)")
            viewModel.currentUser.avatarUrl = avatarUrl
            viewModel.currentUser.profileImageUrl = avatarUrl
        }
        
        if let friendIndex = viewModel.friends.firstIndex(where: { $0.id == userId }) {
            print("DEBUG: Updating friend avatar for \(viewModel.friends[friendIndex].fullName): \(avatarUrl)")
            viewModel.friends[friendIndex].avatarUrl = avatarUrl
            viewModel.friends[friendIndex].profileImageUrl = avatarUrl
        }
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

// MARK: - Smart Components

struct SmartMapStyleButton: View {
    @ObservedObject var viewModel: LocationViewModel
    @State private var isChangingStyle = false
    
    var body: some View {
        Button(action: {
            guard !isChangingStyle else { return }
            
            isChangingStyle = true
            withAnimation(.smooth) {
                viewModel.toggleMapStyle()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                isChangingStyle = false
            }
        }) {
            Image(systemName: viewModel.currentMapStyle.iconName)
                .font(.system(size: 20))
                .foregroundColor(.primary)
                .frame(width: 40, height: 40)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(radius: 4)
        }
        .disabled(isChangingStyle)
        .opacity(isChangingStyle ? 0.6 : 1.0)
    }
}

struct SmartLocationButton: View {
    @ObservedObject var viewModel: LocationViewModel
    let isUserInteracting: Bool
    @State private var isFocusing = false
    
    var body: some View {
        Button(action: {
            guard !isUserInteracting && !isFocusing else {
                print("DEBUG: Location focus blocked - user interacting or already focusing")
                return
            }
            
            isFocusing = true
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                viewModel.focusOnUserLocation()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isFocusing = false
            }
        }) {
            Image(systemName: viewModel.isTrackingLocation ? "location.fill" : "location")
                .font(.system(size: 20))
                .foregroundColor(viewModel.isTrackingLocation ? .blue : .gray)
                .frame(width: 50, height: 50)
                .background(Color.white)
                .clipShape(Circle())
                .shadow(radius: 4)
                .scaleEffect(isFocusing ? 0.9 : 1.0)
        }
        .disabled(!viewModel.isTrackingLocation || isUserInteracting || isFocusing)
        .opacity((!viewModel.isTrackingLocation || isUserInteracting || isFocusing) ? 0.6 : 1.0)
    }
}

// MARK: - Keep all existing components

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

struct ClusterExpansionIndicator: View {
    let animatingClusters: [String]
    let viewModel: LocationViewModel
    
    var body: some View {
        if !animatingClusters.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
                
                Text("Expanding \(animatingClusters.count) cluster\(animatingClusters.count > 1 ? "s" : "")")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button("Collapse All") {
                    for clusterId in animatingClusters {
                        let _ = viewModel.toggleClusterExpansion(clusterId: clusterId)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.9))
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            )
            .padding(.horizontal)
        }
    }
}

#Preview {
    MapView()
        .environmentObject(AuthViewModel())
}
