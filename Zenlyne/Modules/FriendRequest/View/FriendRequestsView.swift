//
//  FriendRequestsView.swift
//  Zenlyne
//
//  Created by admin on 25/3/25.
//

import SwiftUI

struct FriendRequestsView: View {
    @StateObject private var friendRequestVM = FriendRequestViewModel()
    
    var body: some View {
        NavigationView {
            List {
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
            .navigationTitle("Lời Mời Kết Bạn")
            .onAppear {
                friendRequestVM.fetchFriendRequests {}
            }
        }
    }
    
    private func acceptFriendRequest(requestId: String) {
        friendRequestVM.acceptFriendRequest(requestId: requestId) { success, message in
            // Xử lý thông báo nếu cần
        }
    }
    
    private func declineFriendRequest(requestId: String) {
        friendRequestVM.declineFriendRequest(requestId: requestId) { success, message in
            // Xử lý thông báo nếu cần
        }
    }
}

struct FriendRequestsView_Previews: PreviewProvider {
    static var previews: some View {
        FriendRequestsView()
    }
}
