//
//  FriendsListView.swift
//  Zenlyne
//
//  Created by admin on 8/4/25.
//

import SwiftUI

struct FriendsListView: View {
    @ObservedObject var viewModel: LocationViewModel
    @State private var showInviteFriendSheet = false
    
    var body: some View {
        VStack {
            // Header
            HStack {
                Text("Bạn bè")
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    showInviteFriendSheet = true
                }) {
                    Image(systemName: "person.badge.plus")
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
                        showInviteFriendSheet = true
                    }) {
                        Text("Mời bạn bè")
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
                }
            }
        }
        .sheet(isPresented: $showInviteFriendSheet) {
            // Sheet chứa view mời bạn bè
            InviteFriendView()
        }
        .onAppear {
            // Đảm bảo danh sách bạn bè được refresh khi view xuất hiện
            viewModel.startTrackingLocation()
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
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    if let profileImage = friend.profileImageUrl {
                        // Nếu có hình đại diện, sẽ load từ URL (cần thêm extension Image)
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
    }
}

struct InviteFriendView: View {
    @State private var email = ""
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @Environment(\.dismiss) private var dismiss
    
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
        }
    }
    
    func sendInvite() {
        // Đây chỉ là placeholder, bạn cần xây dựng chức năng gửi lời mời thực tế
        isLoading = true
        
        // Giả lập việc gửi lời mời
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isLoading = false
            alertMessage = "Đã gửi lời mời đến \(email)"
            showAlert = true
            email = ""
        }
    }
}

struct FriendsListView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = LocationViewModel()
        FriendsListView(viewModel: viewModel)
    }
}
