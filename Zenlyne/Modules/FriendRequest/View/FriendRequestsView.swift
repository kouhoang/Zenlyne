//
//  FriendRequestsView.swift
//  Zenlyne
//
//  Created by admin on 8/4/25.
//

import SwiftUI
import FirebaseFirestore

struct FriendRequestsView: View {
    @StateObject private var viewModel = FriendRequestViewModel()
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack {
                    if viewModel.isLoading {
                        ProgressView("Đang tải...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.5)
                            .padding()
                    } else if viewModel.friendRequests.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            
                            Text("Không có lời mời kết bạn")
                                .font(.headline)
                            
                            Text("Khi có người gửi lời mời kết bạn, bạn sẽ thấy họ ở đây")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding()
                    } else {
                        List {
                            ForEach(viewModel.friendRequests) { request in
                                FriendRequestRow(
                                    request: request,
                                    onAccept: {
                                        acceptFriendRequest(request)
                                    },
                                    onDecline: {
                                        declineFriendRequest(request)
                                    }
                                )
                            }
                        }
                        .refreshable {
                            loadFriendRequests()
                        }
                    }
                    
                    if !viewModel.errorMessage.isEmpty {
                        Text(viewModel.errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .padding()
                    }
                }
            }
            .navigationBarTitle("Lời mời kết bạn", displayMode: .inline)
            .navigationBarItems(trailing: Button("Đóng") {
                dismiss()
            })
            .onAppear {
                loadFriendRequests()
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK")) {
                        if alertTitle == "Thành công" {
                            loadFriendRequests()
                        }
                    }
                )
            }
        }
    }
    
    func loadFriendRequests() {
        viewModel.fetchFriendRequests()
    }
    
    func acceptFriendRequest(_ request: FriendRequest) {
        viewModel.acceptFriendRequest(requestId: request.id) { success, message in
            DispatchQueue.main.async {
                alertTitle = success ? "Thành công" : "Lỗi"
                alertMessage = message
                showAlert = true
            }
        }
    }
    
    func declineFriendRequest(_ request: FriendRequest) {
        viewModel.declineFriendRequest(requestId: request.id) { success, message in
            DispatchQueue.main.async {
                alertTitle = success ? "Thành công" : "Lỗi"
                alertMessage = message
                showAlert = true
            }
        }
    }
}

struct FriendRequestRow: View {
    let request: FriendRequest
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    @State private var senderName = ""
    @State private var senderImage: String?
    
    var body: some View {
        HStack {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                if senderImage == nil {
                    Text(getInitials(from: senderName))
                        .font(.title3)
                        .foregroundColor(.blue)
                } else {
                    AsyncImage(url: URL(string: senderImage!)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Text(getInitials(from: senderName))
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(senderName.isEmpty ? request.senderEmail : senderName)
                    .font(.headline)
                
                Text("Muốn kết bạn với bạn")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            HStack(spacing: 10) {
                // Decline button
                Button(action: onDecline) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                
                // Accept button
                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.green)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            loadSenderInfo()
        }
    }
    
    private func loadSenderInfo() {
        let db = Firestore.firestore()
        db.collection("users").document(request.senderId).getDocument { snapshot, error in
            guard let data = snapshot?.data() else { return }
            
            if let name = data["fullName"] as? String {
                self.senderName = name
            }
            
            if let imageUrl = data["profileImageUrl"] as? String {
                self.senderImage = imageUrl
            }
        }
    }
    
    private func getInitials(from name: String) -> String {
        let formatter = PersonNameComponentsFormatter()
        if let components = formatter.personNameComponents(from: name) {
            formatter.style = .abbreviated
            return formatter.string(from: components)
        }
        return ""
    }
}

struct FriendRequestsView_Previews: PreviewProvider {
    static var previews: some View {
        FriendRequestsView()
            .environmentObject(AuthViewModel())
    }
}
