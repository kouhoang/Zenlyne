//
//  MessageFriendRowView.swift
//  Zenlyne
//
//  Created by admin on 2/6/25.
//


import SwiftUI

struct MessageFriendRowView: View {
    let user: User
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                
                if let profileImage = user.profileImageUrl {
                    AsyncImage(url: URL(string: profileImage)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Text(user.initials)
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
                } else {
                    Text(user.initials)
                        .font(.title3)
                        .foregroundColor(.white)
                }
                
                Circle()
                    .fill(user.isOnline ? Color.green : Color.red)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(Color.black, lineWidth: 2)
                    )
                    .position(x: 40, y: 40)
            }
            .frame(width: 50)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(user.fullName)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Group {
                    if user.isOnline {
                        Text("Đang hoạt động")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    } else {
                        Text(lastSeenText(for: user))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                .frame(height: 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.system(size: 14))
                .frame(width: 20)
        }
        .padding(.vertical, 8)
        .frame(height: 70)
    }
    
    private func lastSeenText(for user: User) -> String {
        if let lastSeen = user.lastSeen {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Hoạt động \(formatter.localizedString(for: lastSeen, relativeTo: Date()))"
        } else {
            return "Không hoạt động"
        }
    }
}
