//
//  ConversationRowView.swift
//  Zenlyne
//
//  Created by admin on 2/6/25.
//


import SwiftUI

struct ConversationRowView: View {
    let chat: Chat
    let user: User?
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                
                if let profileImage = user?.profileImageUrl {
                    AsyncImage(url: URL(string: profileImage)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Text(user?.initials ?? "?")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
                } else {
                    Text(user?.initials ?? "?")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                
                if let user = user {
                    Circle()
                        .fill(user.isOnline ? Color.green : Color.red)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.black, lineWidth: 2)
                        )
                        .position(x: 40, y: 40)
                }
            }
            .frame(width: 50)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(user?.fullName ?? "Người dùng")
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Group {
                    if let user = user {
                        if user.isOnline {
                            Text("Đang hoạt động")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        } else if let lastSeen = user.lastSeen {
                            let formatter = RelativeDateTimeFormatter()
                            Text("Hoạt động \(formatter.localizedString(for: lastSeen, relativeTo: Date()))")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(height: 18)
                
                Group {
                    if let lastMessage = chat.lastMessage {
                        Text(lastMessage.content.count > 30 ?
                             String(lastMessage.content.prefix(30)) + "..." :
                             lastMessage.content)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    } else {
                        Text("Bắt đầu trò chuyện")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .italic()
                    }
                }
                .frame(height: 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatTime(chat.lastMessage?.timestamp))
                    .font(.caption)
                    .foregroundColor(.gray)
                
                if chat.unreadCount > 0 {
                    Text("\(chat.unreadCount)")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
            }
            .frame(width: 60)
        }
        .padding(.vertical, 8)
        .frame(height: 70)
    }
    
    private func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "" }
        
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.locale = Locale(identifier: "vi_VN")
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Hôm qua"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "vi_VN")
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "vi_VN")
            formatter.dateFormat = "dd/MM"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "vi_VN")
            formatter.dateFormat = "dd/MM/yy" 
            return formatter.string(from: date)
        }
    }

}
