//
//  FriendsListView.swift
//  Zenlyne
//
//  Created by admin on 8/4/25.
//

import SwiftUI
import FirebaseAuth
import Combine
import FirebaseFirestoreInternal

struct FriendsListView: View {
    @ObservedObject var locationViewModel: LocationViewModel
    @StateObject private var friendViewModel = FriendViewModel()
    @StateObject private var requestViewModel = FriendRequestViewModel()
    @State private var showAddFriendSheet = false
    @State private var showFriendRequestsSheet = false
    @State private var isSearching = false
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Header với các nút chức năng
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
                                friendViewModel.searchText = ""
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
                            
                            if requestViewModel.pendingRequestsCount > 0 {
                                Text("\(requestViewModel.pendingRequestsCount)")
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
                        
                        TextField("Tìm kiếm bạn bè...", text: $friendViewModel.searchText)
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        if !friendViewModel.searchText.isEmpty {
                            Button(action: {
                                friendViewModel.searchText = ""
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
                            friendViewModel.searchText = ""
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
                if friendViewModel.isLoading {
                    ProgressView("Đang tải danh sách bạn bè...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                        .padding()
                }
                else if !friendViewModel.errorMessage.isEmpty {
                    Text(friendViewModel.errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding()
                }
                else if friendViewModel.friends.isEmpty {
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
                } else if friendViewModel.filteredFriends.isEmpty && !friendViewModel.searchText.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("Không tìm thấy kết quả")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("Không có bạn bè nào phù hợp với từ khóa \"\(friendViewModel.searchText)\"")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(friendViewModel.filteredFriends) { friend in
                            EnhancedFriendRow(
                                friend: friend,
                                hasLocation: locationViewModel.friendLocations[friend.id] != nil,
                                isOnline: friend.isOnline,
                                lastSeen: friend.lastSeen,
                                timeSinceLastUpdate: locationViewModel.timeSinceLastUpdate(friendId: friend.id),
                                onTap: {
                                    locationViewModel.focusOnFriendLocation(friendId: friend.id)
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
                        await refreshFriendsListAsync()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showAddFriendSheet, onDismiss: {
            friendViewModel.fetchFriends()
        }) {
            AddFriendView()
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showFriendRequestsSheet, onDismiss: {
            friendViewModel.fetchFriends()
            requestViewModel.loadPendingRequestsCount()
        }) {
            FriendRequestsView()
                .environmentObject(authViewModel)
        }
        .onAppear {
            setupCurrentUser()
            friendViewModel.fetchFriends()
            requestViewModel.loadPendingRequestsCount()
            setupNotificationObserver()
        }
        .onDisappear {
            removeNotificationObserver()
        }
    }
    
    // MARK: - Private Methods (giữ nguyên logic để tương thích)
    
    private func setupCurrentUser() {
        if let currentUser = Auth.auth().currentUser {
            if let user = authViewModel.currentUser {
                locationViewModel.currentUser = user
            } else {
                let db = Firestore.firestore()
                db.collection("users").document(currentUser.uid).getDocument { snapshot, error in
                    if let data = snapshot?.data(),
                       let email = data["email"] as? String,
                       let fullName = data["fullName"] as? String {
                        let user = User(id: currentUser.uid, fullName: fullName, email: email)
                        locationViewModel.currentUser = user
                    }
                }
            }
        }
    }
    
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RefreshFriendsList"),
            object: nil,
            queue: .main) { _ in
                friendViewModel.fetchFriends()
            }
    }
    
    private func removeNotificationObserver() {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("RefreshFriendsList"), object: nil)
    }
    
    private func refreshFriendsListAsync() async {
        await withCheckedContinuation { continuation in
            friendViewModel.fetchFriends()
            continuation.resume()
        }
    }
    
    private func removeFriend(at offsets: IndexSet) {
        offsets.forEach { index in
            let friend = friendViewModel.filteredFriends[index]
            friendViewModel.removeFriend(friend)
        }
    }
}


struct FriendsListView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = LocationViewModel()
        FriendsListView(locationViewModel: viewModel)
            .environmentObject(AuthViewModel())
            .preferredColorScheme(.dark)
    }
}
