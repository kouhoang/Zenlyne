//
//  ChatAvatarView.swift
//  Zenlyne
//
//  Created by admin on 2/6/25.
//


import SwiftUI

struct ChatAvatarView: View {
    let user: User?
    let size: CGFloat
    
    init(user: User?, size: CGFloat = 32) {
        self.user = user
        self.size = size
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: size, height: size)
            
            if let profileImage = user?.profileImageUrl {
                AsyncImage(url: URL(string: profileImage)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Text(user?.initials ?? "?")
                        .font(.system(size: size * 0.4))
                        .foregroundColor(.white)
                }
                .frame(width: size - 4, height: size - 4)
                .clipShape(Circle())
            } else {
                Text(user?.initials ?? "?")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(.white)
            }
        }
    }
}
