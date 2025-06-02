//
//  NearbyFriendsView.swift
//  Zenlyne
//
//  Created by admin on 2/4/25.
//

//import SwiftUI
//
//struct NearbyFriendsView: View {
//    let friends: [FriendWithDistance]
//    
//    var body: some View {
//        NavigationView {
//            List {
//                if friends.isEmpty {
//                    Text("Không có bạn bè nào ở gần đây")
//                        .foregroundColor(.gray)
//                        .padding()
//                } else {
//                    ForEach(friends) { friend in
//                        HStack {
//                            if let profileImageUrl = friend.profileImageUrl,
//                               let url = URL(string: profileImageUrl) {
//                                AsyncImage(url: url) { image in
//                                    image
//                                        .resizable()
//                                        .scaledToFill()
//                                } placeholder: {
//                                    Image(systemName: "person.circle.fill")
//                                        .font(.system(size: 40))
//                                        .foregroundColor(.gray)
//                                }
//                                .frame(width: 50, height: 50)
//                                .clipShape(Circle())
//                            } else {
//                                Image(systemName: "person.circle.fill")
//                                    .font(.system(size: 40))
//                                    .foregroundColor(.gray)
//                            }
//                            
//                            VStack(alignment: .leading) {
//                                Text(friend.name)
//                                    .font(.headline)
//                                Text(friend.email)
//                                    .font(.subheadline)
//                                    .foregroundColor(.gray)
//                            }
//                            
//                            Spacer()
//                            
//                            if let distance = friend.distance {
//                                Text(String(format: "%.1f km", distance))
//                                    .font(.system(size: 14, weight: .medium))
//                                    .foregroundColor(.blue)
//                            } else {
//                                Text("Không rõ")
//                                    .font(.system(size: 14))
//                                    .foregroundColor(.gray)
//                            }
//                        }
//                        .padding(.vertical, 4)
//                    }
//                }
//            }
//            .navigationTitle("Bạn bè gần đây")
//        }
//    }
//}
