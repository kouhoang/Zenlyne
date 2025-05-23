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
           Section(header: Text("Chia sẻ vị trí").foregroundColor(.gray)) {
               Toggle("Chia sẻ vị trí của tôi", isOn: .constant(true))
                   .tint(.blue)
                   .foregroundColor(.white)
                   .listRowBackground(Color.black)
               
               Toggle("Hiện thị trạng thái trực tuyến", isOn: .constant(true))
                   .tint(.blue)
                   .foregroundColor(.white)
                   .listRowBackground(Color.black)
               
               Toggle("Hiển thị thời gian nhìn thấy lần cuối", isOn: .constant(true))
                   .tint(.blue)
                   .foregroundColor(.white)
                   .listRowBackground(Color.black)
           }
           
           Section(header: Text("Ai có thể thấy vị trí của tôi?").foregroundColor(.gray)) {
               NavigationLink(destination: Text("Cài đặt quyền vị trí")) {
                   Text("Chỉ bạn bè")
                       .foregroundColor(.white)
               }
               .listRowBackground(Color.black)
           }
           
           Section(header: Text("Quyền riêng tư dữ liệu").foregroundColor(.gray)) {
               Button("Tải xuống dữ liệu của tôi") {
                   // Implement data download
               }
               .foregroundColor(.white)
               .listRowBackground(Color.black)
               
               Button("Quản lý lịch sử vị trí") {
                   // Implement location history management
               }
               .foregroundColor(.white)
               .listRowBackground(Color.black)
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
           Section(header: Text("Thông báo đẩy").foregroundColor(.gray)) {
               Toggle("Yêu cầu kết bạn", isOn: .constant(true))
                   .tint(.blue)
                   .foregroundColor(.white)
                   .listRowBackground(Color.black)
               
               Toggle("Cập nhật vị trí bạn bè", isOn: .constant(true))
                   .tint(.blue)
                   .foregroundColor(.white)
                   .listRowBackground(Color.black)
               
               Toggle("Tin nhắn", isOn: .constant(true))
                   .tint(.blue)
                   .foregroundColor(.white)
                   .listRowBackground(Color.black)
               
               Toggle("Hoạt động của bạn bè", isOn: .constant(true))
                   .tint(.blue)
                   .foregroundColor(.white)
                   .listRowBackground(Color.black)
           }
           
           Section(header: Text("Thông báo qua Email").foregroundColor(.gray)) {
               Toggle("Cập nhật tài khoản", isOn: .constant(true))
                   .tint(.blue)
                   .foregroundColor(.white)
                   .listRowBackground(Color.black)
               
               Toggle("Cảnh báo bảo mật", isOn: .constant(true))
                   .tint(.blue)
                   .foregroundColor(.white)
                   .listRowBackground(Color.black)
               
               Toggle("Newsletter", isOn: .constant(false))
                   .tint(.blue)
                   .foregroundColor(.white)
                   .listRowBackground(Color.black)
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
           Section(header: Text("Hỗ trợ").foregroundColor(.gray)) {
               NavigationLink(destination: FAQView()) {
                   Text("Những câu hỏi thường gặp")
                       .foregroundColor(.white)
               }
               .listRowBackground(Color.black)
               
               NavigationLink(destination: Text("Nội dung hướng dẫn")) {
                   Text("Làm sao để sử dụng Zenlyne")
                       .foregroundColor(.white)
               }
               .listRowBackground(Color.black)
               
               Button(action: {
                   // Implement contact us action
                   if let url = URL(string: "mailto:support@zenlyne.app") {
                       UIApplication.shared.open(url)
                   }
               }) {
                   Text("Liên hệ hỗ trợ")
                       .foregroundColor(.white)
               }
               .listRowBackground(Color.black)
           }
           
           Section(header: Text("Xử lý sự cố").foregroundColor(.white)) {
               Button(action: {
                   // Implement refresh data action
               }) {
                   Text("Làm mới dữ liệu vị trí")
                       .foregroundColor(.blue)
               }
               .listRowBackground(Color.black)
               
               Button(action: {
                   // Implement clear cache action
               }) {
                   Text("Xoá Cache")
                       .foregroundColor(.blue)
               }
               .listRowBackground(Color.black)
           }
           
           Section(header: Text("Về").foregroundColor(.white)) {
               HStack {
                   Text("Version")
                       .foregroundColor(.white)
                   Spacer()
                   Text("1.0.0 (Build 101)")
                       .foregroundColor(.gray)
               }
               .listRowBackground(Color.black)
               
               HStack {
                   Text("ID thiết bị")
                       .foregroundColor(.white)
                   Spacer()
                   Text(UIDevice.current.identifierForVendor?.uuidString.prefix(8) ?? "Không rõ")
                       .foregroundColor(.gray)
               }
               .listRowBackground(Color.black)
           }
       }
       .navigationTitle("Trợ giúp và Hỗ trợ")
       .background(Color.black)
       .scrollContentBackground(.hidden)
   }
}

struct FAQView: View {
   var body: some View {
       List {
           FAQItem(question: "How does location sharing work?",
                  answer: "Zenlyne shares your location with your friends when the app is open. You can control who sees your location in Privacy Settings.")
           .listRowBackground(Color.black)
           
           FAQItem(question: "Can I see my friends' locations when they're offline?",
                  answer: "You can see your friends' last known location for up to 24 hours after they go offline, unless they've disabled this feature.")
           .listRowBackground(Color.black)
           
           FAQItem(question: "How accurate is the location data?",
                  answer: "Location accuracy depends on your device's GPS and network connectivity. In most cases, it's accurate within 10-50 meters.")
           .listRowBackground(Color.black)
           
           FAQItem(question: "How do I add friends?",
                  answer: "Tap the '+' button on the friends list screen and enter your friend's email address to send them a friend request.")
           .listRowBackground(Color.black)
           
           FAQItem(question: "Is my data secure?",
                  answer: "We use industry-standard encryption to protect your data. Your location is only shared with friends you've approved.")
           .listRowBackground(Color.black)
       }
       .navigationTitle("FAQ")
       .background(Color.black)
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
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.white)
                }
            }
            
            if isExpanded {
                Text(answer)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.top, 5)
            }
        }
        .padding(.vertical, 5)
    }
}
