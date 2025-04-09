//
//  FriendsListView.swift
//  Zenlyne
//
//  Created by admin on 8/4/25.
//

import SwiftUI
import FirebaseAuth

struct FriendsListView: View {
    @ObservedObject var viewModel: LocationViewModel
    @StateObject private var friendViewModel = FriendRequestViewModel()
    @State private var showAddFriendSheet = false
    @State private var showFriendRequestsSheet = false
    @State private var pendingRequestsCount = 0
    
    var body: some View {
        VStack {
            HStack {
                Text("Bạn bè")
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Badge shows the friend requests
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
                
                // Add new friedn button
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
            
            // Friend List
            if viewModel.friends.isEmpty {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(viewModel.friends) { friend in
                        FriendRow(
                            friend: friend,
                            hasLocation: viewModel.friendLocations[friend.id] != nil,
                            onTap: {
                                // Focus camera on friend when tapping on their row
                                viewModel.focusOnFriendLocation(friendId: friend.id)
                            }
                        )
                    }
                    .onDelete(perform: removeFriend)
                }
                .refreshable {
                    // Refresh friends list when pulled down
                    viewModel.startTrackingLocation()
                }
            }
        }
        .sheet(isPresented: $showAddFriendSheet) {
            AddFriendView()
        }
        .sheet(isPresented: $showFriendRequestsSheet) {
            FriendRequestsView()
        }
        .onAppear {
            viewModel.startTrackingLocation()
            loadPendingRequestsCount()
        }
    }
    
    // Load unread friend request count
    private func loadPendingRequestsCount() {
        friendViewModel.getPendingFriendRequestsCount { count in
            DispatchQueue.main.async {
                pendingRequestsCount = count
            }
        }
    }
    
    // Delete friend
    private func removeFriend(at offsets: IndexSet) {
        guard let user = Auth.auth().currentUser else { return }
        
        offsets.forEach { index in
            let friend = viewModel.friends[index]
            let firebaseService = FirebaseService()
            
            firebaseService.removeFriend(currentUserId: user.uid, friendId: friend.id) { success in
                if success {
                    // Cập nhật danh sách bạn bè sau khi xóa
                    viewModel.startTrackingLocation()
                }
            }
        }
    }
}

struct FriendRow: View {
    let friend: User
    let hasLocation: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    if let profileImage = friend.profileImageUrl {
                        // If have avater, will load from URL
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
                    
                    // Online indicator
                    if friend.isOnline {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                            .position(x: 40, y: 40)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.fullName)
                        .font(.headline)
                    
                    if friend.isOnline {
                        Text("Online now")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    } else if let lastSeen = friend.lastSeen {
                        Text("Last seen \(lastSeen, formatter: RelativeDateTimeFormatter())")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // Location icon
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
                // Friend delete feature in context menu
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

// Invite friend view by email (not Firebase)
struct InviteFriendView: View {
    @State private var email = ""
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Mời bạn bè của bạn")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top)
                
                Text("Nhập email của bạn bè để gửi lời mời")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                TextField("Email bạn bè", text: $email)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                
                Button(action: sendInvite) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Gửi lời mời")
                    }
                }
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.horizontal)
                .disabled(email.isEmpty || isLoading)
                .opacity(email.isEmpty ? 0.6 : 1.0)
                
                Spacer()
            }
            .padding()
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("Thông báo"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .navigationBarItems(trailing: Button("Đóng") {
                dismiss()
            })
            .onTapGesture {
                hideKeyboard()
            }
        }
    }
    
    func sendInvite() {
        isLoading = true
        
        guard let user = authViewModel.currentUser else {
            isLoading = false
            alertMessage = "Không thể xác định người dùng hiện tại"
            showAlert = true
            return
        }
        
        let firebaseService = FirebaseService()
        firebaseService.inviteFriendByEmail(email: email, from: user) { success, message in
            DispatchQueue.main.async {
                isLoading = false
                alertMessage = message
                showAlert = true
                
                if success {
                    email = ""
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
    }
}
