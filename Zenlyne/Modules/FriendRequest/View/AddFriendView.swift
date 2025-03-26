//
//  AddFriendView.swift
//  Zenlyne
//
//  Created by admin on 25/3/25.
//


import SwiftUI

struct AddFriendView: View {
    @State private var friendEmail = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @StateObject private var friendRequestVM = FriendRequestViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Thêm Bạn")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Nhập địa chỉ email của người bạn muốn kết bạn")
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            InputView(
                text: $friendEmail,
                title: "Email của bạn bè",
                placeholder: "email@example.com"
            )
            .autocapitalization(.none)
            .padding(.horizontal)
            
            Button(action: sendFriendRequest) {
                Text("Gửi Lời Mời")
                    .foregroundColor(.white)
                    .frame(width: UIScreen.main.bounds.width - 32, height: 48)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .disabled(friendEmail.isEmpty || !friendEmail.contains("@"))
            
            Spacer()
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Thông Báo"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private func sendFriendRequest() {
        friendRequestVM.sendFriendRequest(toEmail: friendEmail) { success, message in
            alertMessage = message
            showAlert = true
            
            if success {
                friendEmail = ""
            }
        }
    }
}

struct AddFriendView_Previews: PreviewProvider {
    static var previews: some View {
        AddFriendView()
    }
}
