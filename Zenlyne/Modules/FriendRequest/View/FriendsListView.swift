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
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with function button
            HStack {
                Text("Bạn bè")
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Badge shows number of friend requests
                Button(action: {
                    showFriendRequestsSheet = true
                }) {
                    ZStack {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 22))
                            .foregroundColor(.blue)
                        
                        if pendingRequestsCount > 0 {
                            Text("\(pendingRequestsCount)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(Color.red)
                                .clipShape(Circle())
                                .offset(x: 10, y: -10)
                        }
                    }
                }
                .padding(.trailing, 10)
                
                // Add friend button
                Button(action: {
                    showAddFriendSheet = true
                }) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 22))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 10)
            
            // Main content
            ZStack(alignment: .top) {
                if isRefreshing {
                    ProgressView("Đang tải danh sách bạn bè...")
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
                } else {
                    List {
                        ForEach(viewModel.friends) { friend in
                            EnhancedFriendRow(
                                friend: friend,
                                hasLocation: viewModel.friendLocations[friend.id] != nil,
                                isOnline: friend.isOnline,
                                lastSeen: friend.lastSeen,
                                timeSinceLastUpdate: viewModel.timeSinceLastUpdate(friendId: friend.id),
                                onTap: {
                                    // Focus camera vào bạn bè khi tap vào hàng
                                    viewModel.focusOnFriendLocation(friendId: friend.id)
                                    // Đóng view FriendsList và quay lại màn hình Map
                                    NotificationCenter.default.post(
                                        name: NSNotification.Name("FriendSelected"),
                                        object: nil,
                                        userInfo: ["friendId": friend.id]
                                    )
                                }
                            )
                        }
                        .onDelete(perform: removeFriend)
                    }
                    .listStyle(PlainListStyle())
                    .refreshable {
                        // Refresh list on pull down
                        await refreshFriendsListAsync()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
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
        
        // Đặt trạng thái đang tải
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
        guard let currentUser = Auth.auth().currentUser else {
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
            let friend = viewModel.friends[index]
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

struct EnhancedFriendRow: View {
    let friend: User
    let hasLocation: Bool
    let isOnline: Bool
    let lastSeen: Date?
    let timeSinceLastUpdate: String?
    let onTap: () -> Void
    private let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                // Avatar with online/offline status
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    if let profileImage = friend.profileImageUrl {
                        AsyncImage(url: URL(string: profileImage)) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Text(friend.initials)
                                .font(.title3)
                                .foregroundColor(.blue)
                        }
                        .frame(width: 46, height: 46)
                        .clipShape(Circle())
                    } else {
                        Text(friend.initials)
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                    
                    // Online status indicator - green or red dot
                    Circle()
                        .fill(isOnline ? Color.green : Color.red)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .position(x: 40, y: 40)
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(friend.fullName)
                        .font(.headline)
                    
                    // Show online/offline time
                    if isOnline {
                        Text("Đang hoạt động")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    } else if let lastSeen = lastSeen {
                        Text("Hoạt động \(formatter.localizedString(for: lastSeen, relativeTo: Date()))")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    // Show latest location updates
                    if let timeSinceLastUpdate = timeSinceLastUpdate {
                        Text("Vị trí cập nhật \(timeSinceLastUpdate)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // Icon shows position status
                if hasLocation {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 18))
                } else {
                    Image(systemName: "location.slash")
                        .foregroundColor(.gray)
                        .font(.system(size: 18))
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(role: .destructive, action: {
                // Delete friend feature in context menu
                if let currentUser = Auth.auth().currentUser {
                    let firebaseService = FirebaseService()
                    firebaseService.removeFriend(currentUserId: currentUser.uid, friendId: friend.id) { _ in }
                }
            }) {
                Label("Xóa bạn bè", systemImage: "person.badge.minus")
            }
        }
    }
}

struct FriendsListView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = LocationViewModel()
        FriendsListView(viewModel: viewModel)
            .environmentObject(AuthViewModel())
    }
}
