//
//  FriendProfileView.swift
//  Zenlyne
//
//  Created by admin on 2/6/25.
//


import SwiftUI

struct FriendProfileView: View {
    let user: User
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.gray)
                        .padding()
                }
                
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 120)
                        
                        if let profileImage = user.profileImageUrl {
                            AsyncImage(url: URL(string: profileImage)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Text(user.initials)
                                    .font(.title)
                                    .foregroundColor(.white)
                            }
                            .frame(width: 116, height: 116)
                            .clipShape(Circle())
                        } else {
                            Text(user.initials)
                                .font(.title)
                                .foregroundColor(.white)
                        }
                        
                        if user.isOnline {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(Color.black, lineWidth: 2)
                                )
                                .position(x: 100, y: 100)
                        }
                    }
                    .padding(.top, 40)
                    
                    Text(user.fullName)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    if user.isOnline {
                        Text("Đang hoạt động")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    } else if let lastSeen = user.lastSeen {
                        let formatter = RelativeDateTimeFormatter()
                        Text("Hoạt động \(formatter.localizedString(for: lastSeen, relativeTo: Date()))")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    Text(user.email)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Thông tin bạn bè")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
    }
}