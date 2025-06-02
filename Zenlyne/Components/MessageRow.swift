//
//  MessageRow.swift
//  Zenlyne
//
//  Created by admin on 2/6/25.
//


import SwiftUI

struct MessageRow: View {
    let message: Message
    let otherUser: User?
    let isFromCurrentUser: Bool
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isFromCurrentUser {
                Spacer()
                currentUserMessageView
            } else {
                ChatAvatarView(user: otherUser, size: 32)
                otherUserMessageView
                Spacer()
            }
        }
    }
    
    private var currentUserMessageView: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Spacer()
                Text(message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray4))
                    .foregroundColor(.black)
                    .cornerRadius(20, corners: [.topLeft, .topRight, .bottomLeft])
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: .trailing)
            }
            
            Text(formatTime(message.timestamp))
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.trailing, 8)
        }
    }
    
    private var otherUserMessageView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.content)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemGray))
                .foregroundColor(.white)
                .cornerRadius(20, corners: [.topLeft, .topRight, .bottomRight])
                .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: .leading)
            
            Text(formatTime(message.timestamp))
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.leading, 8)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
