//
//  FriendsListView.swift
//  Zenlyne
//
//  Created by admin on 8/4/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct FriendsListView: View {
    @ObservedObject var viewModel: LocationViewModel
    @StateObject private var friendViewModel = FriendRequestViewModel()
    @State private var showAddFriendSheet = false
    @State private var showFriendRequestsSheet = false
    @State private var pendingRequestsCount = 0
    @State private var isRefreshing = false
    @State private var errorMessage: String? = nil
    @State private var searchText = ""
    @State private var isSearching = false
    @EnvironmentObject var authViewModel: AuthViewModel
    
    // Filtered friends based on search text and sorted by online status
    var filteredFriends: [User] {
        let baseFilteredFriends: [User]
        
        if searchText.isEmpty {
            baseFilteredFriends = viewModel.friends
        } else {
            baseFilteredFriends = viewModel.friends.filter { friend in
                friend.fullName.localizedCaseInsensitiveContains(searchText) ||
                friend.email.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Sort by online status: online friends first, then offline friends
        return baseFilteredFriends.sorted { friend1, friend2 in
            // If one is online and the other is not, prioritize the online one
            if friend1.isOnline && !friend2.isOnline {
                return true
            } else if !friend1.isOnline && friend2.isOnline {
                return false
            } else {
                // If both have the same online status, sort by name
                return friend1.fullName.localizedCaseInsensitiveCompare(friend2.fullName) == .orderedAscending
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with function buttons
            HStack {
                Text("Bạn bè")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Search button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isSearching.toggle()
                            if !isSearching {
                                searchText = ""
                            }
                        }
                    }) {
                        IconContainer(systemName: "magnifyingglass")
                    }
                    
                    // Friend requests button with badge
                    Button(action: {
                        showFriendRequestsSheet = true
                    }) {
                        ZStack {
                            IconContainer(systemName: "person.badge.plus")
                            
                            if pendingRequestsCount > 0 {
                                Text("\(pendingRequestsCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 16, height: 16)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                    .offset(x: 12, y: -12)
                            }
                        }
                    }
                    
                    // Add friend button
                    Button(action: {
                        showAddFriendSheet = true
                    }) {
                        IconContainer(systemName: "person.crop.circle.badge.plus")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 10)
            
            // Search bar
            if isSearching {
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .font(.system(size: 16))
                        
                        TextField("Tìm kiếm bạn bè...", text: $searchText)
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 16))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.pink, Color.yellow]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .cornerRadius(8)
                    
                    Button("Hủy") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isSearching = false
                            searchText = ""
                        }
                    }
                    .foregroundColor(.white)
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Main content
            ZStack(alignment: .top) {
                if isRefreshing {
                    ProgressView("Đang tải danh sách bạn bè...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                        .padding()
                }
                else if let error = errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding()
                }
                else if viewModel.friends.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("Bạn chưa có bạn bè nào")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("Mời bạn bè tham gia Zenlyne để xem vị trí của họ")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button(action: {
                            showAddFriendSheet = true
                        }) {
                            Text("Thêm bạn bè")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 20)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        .padding(.top, 10)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                } else if filteredFriends.isEmpty && !searchText.isEmpty {
                    // No search results
                    VStack(spacing: 20) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("Không tìm thấy kết quả")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("Không có bạn bè nào phù hợp với từ khóa \"\(searchText)\"")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(filteredFriends) { friend in
                            EnhancedFriendRow(
                                friend: friend,
                                hasLocation: viewModel.friendLocations[friend.id] != nil,
                                isOnline: friend.isOnline,
                                lastSeen: friend.lastSeen,
                                timeSinceLastUpdate: viewModel.timeSinceLastUpdate(friendId: friend.id),
                                onTap: {
                                    // Focus camera on friend when tapping on row
                                    viewModel.focusOnFriendLocation(friendId: friend.id)
                                    // Close FriendsList view and return to Map screen
                                    NotificationCenter.default.post(
                                        name: NSNotification.Name("FriendSelected"),
                                        object: nil,
                                        userInfo: ["friendId": friend.id]
                                    )
                                }
                            )
                            .listRowBackground(Color.black)
                        }
                        .onDelete(perform: removeFriend)
                    }
                    .listStyle(PlainListStyle())
                    .background(Color.black)
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        // Refresh list on pull down
                        await refreshFriendsListAsync()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showAddFriendSheet, onDismiss: {
            refreshFriendsList()
        }) {
            AddFriendView()
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showFriendRequestsSheet, onDismiss: {
            refreshFriendsList()
            loadPendingRequestsCount()
        }) {
            FriendRequestsView()
                .environmentObject(authViewModel)
        }
        .onAppear {
            setupCurrentUser()
            refreshFriendsList()
            loadPendingRequestsCount()
            setupNotificationObserver()
        }
        .onDisappear {
            removeNotificationObserver()
        }
    }
    
    // Set observer for notification
    private func setupCurrentUser() {
        if let currentUser = Auth.auth().currentUser {
            print("DEBUG: Auth user ID: \(currentUser.uid)")
            
            if let user = authViewModel.currentUser {
                print("DEBUG: Đặt currentUser từ AuthViewModel: \(user.id)")
                viewModel.currentUser = user
            } else {
                print("DEBUG: Không có currentUser trong AuthViewModel, tải từ Firestore")
                let db = Firestore.firestore()
                db.collection("users").document(currentUser.uid).getDocument { snapshot, error in
                    if let error = error {
                        print("DEBUG: Lỗi khi tải user: \(error.localizedDescription)")
                        return
                    }
                    
                    if let data = snapshot?.data(),
                       let email = data["email"] as? String,
                       let fullName = data["fullName"] as? String {
                        let user = User(id: currentUser.uid, fullName: fullName, email: email)
                        viewModel.currentUser = user
                        print("DEBUG: Đã tải và cập nhật user: \(user.id)")
                    }
                }
            }
        } else {
            print("DEBUG: Không có người dùng nào đăng nhập")
        }
    }
    
    // Set observer for notification
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RefreshFriendsList"),
            object: nil,
            queue: .main) { _ in
                print("DEBUG: Nhận thông báo làm mới danh sách bạn bè")
                refreshFriendsList()
            }
    }
    
    // Destroy observer when view disappears
    private func removeNotificationObserver() {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("RefreshFriendsList"), object: nil)
    }
    
    // Load friends list (async version for refreshable)
    private func refreshFriendsListAsync() async {
        await withCheckedContinuation { continuation in
            refreshFriendsList {
                continuation.resume()
            }
        }
    }
    
    // Load friend list
    private func refreshFriendsList(completion: (() -> Void)? = nil) {
        guard let currentUser = Auth.auth().currentUser else {
            print("DEBUG: Không có người dùng nào đăng nhập")
            errorMessage = "Bạn cần đăng nhập để xem danh sách bạn bè"
            completion?()
            return
        }
        
        // Set loading status
        isRefreshing = true
        errorMessage = nil
        
        print("DEBUG: Đang làm mới danh sách bạn bè cho user: \(currentUser.uid)")
        
        // When running directly in FriendsListView, we will get the friends list from Firebase
        friendViewModel.fetchFriends(forUserId: currentUser.uid) { friends in
            DispatchQueue.main.async {
                // Set loaded status
                self.isRefreshing = false
                
                print("DEBUG: Đã tải \(friends.count) bạn bè từ friendViewModel")
                
                // Update friends list in viewModel
                self.viewModel.friends = friends
                
                // Track your friends' location and online status
                if !friends.isEmpty {
                    let friendIds = friends.map { $0.id }
                    print("DEBUG: Bắt đầu theo dõi vị trí và trạng thái cho \(friendIds.count) bạn bè")
                    self.viewModel.startObservingFriendLocations(friendIds: friendIds)
                    self.viewModel.startObservingFriendOnlineStatus(friendIds: friendIds)
                }
                
                completion?()
            }
        }
    }
    
    // Load the number of pending friend requests
    private func loadPendingRequestsCount() {
        guard Auth.auth().currentUser != nil else {
            pendingRequestsCount = 0
            return
        }
        
        friendViewModel.getPendingFriendRequestsCount { count in
            DispatchQueue.main.async {
                self.pendingRequestsCount = count
                print("DEBUG: Có \(count) lời mời kết bạn đang chờ")
            }
        }
    }
    
    // Delete friend
    private func removeFriend(at offsets: IndexSet) {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        offsets.forEach { index in
            let friend = filteredFriends[index] // Use filtered friends
            print("DEBUG: Đang xóa bạn: \(friend.fullName) (ID: \(friend.id))")
            
            let firebaseService = FirebaseService()
            firebaseService.removeFriend(currentUserId: currentUser.uid, friendId: friend.id) { success in
                if success {
                    print("DEBUG: Xóa bạn thành công, làm mới danh sách")
                    // Update friend list after deleting
                    DispatchQueue.main.async {
                        refreshFriendsList()
                    }
                } else {
                    print("DEBUG: Xóa bạn thất bại")
                    DispatchQueue.main.async {
                        self.errorMessage = "Không thể xóa bạn bè. Vui lòng thử lại sau."
                    }
                }
            }
        }
    }
}

struct FriendsListView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = LocationViewModel()
        FriendsListView(viewModel: viewModel)
            .environmentObject(AuthViewModel())
            .preferredColorScheme(.dark)
    }
}
