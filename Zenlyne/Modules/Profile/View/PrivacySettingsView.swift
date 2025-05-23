//
//  PrivacySettingsView.swift
//  Zenlyne
//
//  Created by admin on 23/5/25.
//

import SwiftUI
import UIKit

// MARK: - Settings Views

struct PrivacySettingsView: View {
   var body: some View {
       List {
           Section(header: Text("Chia sẻ vị trí")) {
               Toggle("Chia sẻ vị trí của tôi", isOn: .constant(true))
                   .tint(.blue)
               
               Toggle("Hiện thị trạng thái trực tuyến", isOn: .constant(true))
                   .tint(.blue)
               
               Toggle("Hiển thị thời gian nhìn thấy lần cuối", isOn: .constant(true))
                   .tint(.blue)
           }
           
           Section(header: Text("Ai có thể thấy vị trí của tôi?")) {
               NavigationLink(destination: Text("Cài đặt quyền vị trí")) {
                   Text("Chỉ bạn bè")
               }
           }
           
           Section(header: Text("Quyền riêng tư dữ liệu")) {
               Button("Tải xuống dữ liệu của tôi") {
                   // Implement data download
               }
               
               Button("Quản lý lịch sử vị trí") {
                   // Implement location history management
               }
           }
       }
       .navigationTitle("Cài đặt quyền riêng tư")
       .background(Color.black)
       .scrollContentBackground(.hidden)
   }
}

struct NotificationSettingsView: View {
   var body: some View {
       List {
           Section(header: Text("Thông báo đẩy")) {
               Toggle("Yêu cầu kết bạn", isOn: .constant(true))
                   .tint(.blue)
               
               Toggle("Cập nhật vị trí bạn bè", isOn: .constant(true))
                   .tint(.blue)
               
               Toggle("Tin nhắn", isOn: .constant(true))
                   .tint(.blue)
               
               Toggle("Hoạt động của bạn bè", isOn: .constant(true))
                   .tint(.blue)
           }
           
           Section(header: Text("Thông báo qua Email")) {
               Toggle("Cập nhật tài khoản", isOn: .constant(true))
                   .tint(.blue)
               
               Toggle("Cảnh báo bảo mật", isOn: .constant(true))
                   .tint(.blue)
               
               Toggle("Newsletter", isOn: .constant(false))
                   .tint(.blue)
           }
       }
       .navigationTitle("Thông báo")
       .background(Color.black)
       .scrollContentBackground(.hidden)
   }
}

struct HelpSupportView: View {
   var body: some View {
       List {
           Section(header: Text("Hỗ trợ")) {
               NavigationLink(destination: FAQView()) {
                   Text("Những câu hỏi thường gặp")
               }
               
               NavigationLink(destination: Text("Nội dung hướng dẫn")) {
                   Text("Làm sao để sử dụng Zenlyne")
               }
               
               Button(action: {
                   // Implement contact us action
                   if let url = URL(string: "mailto:support@zenlyne.app") {
                       UIApplication.shared.open(url)
                   }
               }) {
                   Text("Liên hệ hỗ trợ")
               }
           }
           
           Section(header: Text("Xử lý sự cố")) {
               Button(action: {
                   // Implement refresh data action
               }) {
                   Text("Làm mới dữ liệu vị trí")
               }
               
               Button(action: {
                   // Implement clear cache action
               }) {
                   Text("Xoá Cache")
               }
           }
           
           Section(header: Text("Về")) {
               HStack {
                   Text("Version")
                   Spacer()
                   Text("1.0.0 (Build 101)")
                       .foregroundColor(.gray)
               }
               
               HStack {
                   Text("ID thiết bị")
                   Spacer()
                   Text(UIDevice.current.identifierForVendor?.uuidString.prefix(8) ?? "Không rõ")
                       .foregroundColor(.gray)
               }
           }
       }
       .navigationTitle("Trợ giúp và Hỗ trợ")
       .background(Color.black.opacity(0.3))
       .scrollContentBackground(.hidden)
   }
}

struct FAQView: View {
   var body: some View {
       List {
           FAQItem(question: "How does location sharing work?",
                  answer: "Zenlyne shares your location with your friends when the app is open. You can control who sees your location in Privacy Settings.")
           
           FAQItem(question: "Can I see my friends' locations when they're offline?",
                  answer: "You can see your friends' last known location for up to 24 hours after they go offline, unless they've disabled this feature.")
           
           FAQItem(question: "How accurate is the location data?",
                  answer: "Location accuracy depends on your device's GPS and network connectivity. In most cases, it's accurate within 10-50 meters.")
           
           FAQItem(question: "How do I add friends?",
                  answer: "Tap the '+' button on the friends list screen and enter your friend's email address to send them a friend request.")
           
           FAQItem(question: "Is my data secure?",
                  answer: "We use industry-standard encryption to protect your data. Your location is only shared with friends you've approved.")
       }
       .navigationTitle("FAQ")
       .background(Color.black.opacity(0.7))
       .scrollContentBackground(.hidden)
   }
}

struct FAQItem: View {
    let question: String
    let answer: String
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: {
                withAnimation {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text(question)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.black)
                }
            }
            
            if isExpanded {
                Text(answer)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.top, 5)
            }
        }
        .padding(.vertical, 5)
    }
}
