//
//  FriendRequestsView.swift
//  Zenlyne
//
//  Created by admin on 25/3/25.
//

import SwiftUI
import Kingfisher

struct FriendRequestsView: View {
    @StateObject private var friendRequestVM = FriendRequestViewModel()
    @StateObject private var locationViewModel = LocationViewModel()
    
    var body: some View {
        NavigationView {
            List {
                // Friend Requests Section
                Section(header: Text("Lời mời kết bạn")) {
                    if friendRequestVM.friendRequests.isEmpty {
                        Text("Không có lời mời kết bạn")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(friendRequestVM.friendRequests) { request in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(request.senderEmail)
                                        .font(.headline)
                                    Text("Muốn kết bạn với bạn")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 10) {
                                    Button(action: {
                                        acceptFriendRequest(requestId: request.id)
                                    }) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .imageScale(.large)
                                    }
                                    
                                    Button(action: {
                                        declineFriendRequest(requestId: request.id)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                            .imageScale(.large)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Friends Section
                Section(header: Text("Danh Sách Bạn Bè")) {
                    if friendRequestVM.friends.isEmpty {
                        Text("Bạn chưa có bạn bè")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(friendRequestVM.friends) { friend in
                            HStack {
                                // Profile Image or Initials
                                if let imageUrl = friend.profileImageUrl, let url = URL(string: imageUrl) {
                                    KFImage(url)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 50, height: 50)
                                        .clipShape(Circle())
                                } else {
                                    Text(getInitials(from: friend.name))
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .frame(width: 50, height: 50)
                                        .background(Color.gray)
                                        .clipShape(Circle())
                                }
                                
                                VStack(alignment: .leading) {
                                    Text(friend.name)
                                        .font(.headline)
                                    Text(friend.email)
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                // Distance
                                if let distance = friend.distance {
                                    Text(String(format: "%.1f km", distance))
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                } else {
                                    Text("Khoảng cách không xác định")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bạn Bè")
            .onAppear {
                friendRequestVM.fetchFriendRequests {}
                
                // Fetch friends with current user's location
                friendRequestVM.fetchFriends(
                    currentUserLocation: locationViewModel.userLocation
                ) {}
            }
        }
    }
    
    private func getInitials(from name: String) -> String {
        return name.components(separatedBy: " ")
            .compactMap { $0.first }
            .map { String($0) }
            .prefix(2)
            .joined()
            .uppercased()
    }
    
    private func acceptFriendRequest(requestId: String) {
        friendRequestVM.acceptFriendRequest(requestId: requestId) { success, message in
            // Handle message if needed
        }
    }
    
    private func declineFriendRequest(requestId: String) {
        friendRequestVM.declineFriendRequest(requestId: requestId) { success, message in
            // Handle message if needed
        }
    }
}

struct FriendRequestsView_Previews: PreviewProvider {
    static var previews: some View {
        FriendRequestsView()
    }
}
