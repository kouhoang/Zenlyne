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
    @State private var processingRequestId: String? = nil
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack {
                    if viewModel.isLoading && viewModel.friendRequests.isEmpty {
                        // Show loading only when initially loading
                        ProgressView("Đang tải...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .foregroundColor(.white)
                            .scaleEffect(1.5)
                            .padding()
                    } else if viewModel.friendRequests.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            
                            Text("Không có lời mời kết bạn")
                                .font(.headline)
                                .foregroundColor(.white)
                            
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
                                    isProcessing: processingRequestId == request.id,
                                    onAccept: {
                                        handleAcceptRequest(request)
                                    },
                                    onDecline: {
                                        handleDeclineRequest(request)
                                    }
                                )
                                .listRowBackground(Color.black)
                                .listRowInsets(EdgeInsets())
                            }
                        }
                        .listStyle(PlainListStyle())
                        .background(Color.black)
                        .scrollContentBackground(.hidden)
                        .refreshable {
                            // Only refresh if not currently processing a request
                            if processingRequestId == nil {
                                await refreshFriendRequests()
                            }
                        }
                    }
                    
                    // Error message display
                    if !viewModel.errorMessage.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.red)
                            Text(viewModel.errorMessage)
                                .font(.footnote)
                                .foregroundColor(.red)
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                }
            }
            .navigationBarTitle("Lời mời kết bạn", displayMode: .inline)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !viewModel.friendRequests.isEmpty {
                        Text("\(viewModel.friendRequests.count) lời mời")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .disabled(processingRequestId != nil)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                loadFriendRequests()
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK")) {
                        // Clear error message after showing alert
                        if alertTitle == "Lỗi" {
                            viewModel.errorMessage = ""
                        }
                    }
                )
            }
            .onChange(of: viewModel.errorMessage) { errorMessage in
                // Show alert for error messages
                if !errorMessage.isEmpty {
                    showErrorAlert(message: errorMessage)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Private Methods
    
    private func loadFriendRequests() {
        viewModel.fetchFriendRequests {
            // Handle completion if needed
            DispatchQueue.main.async {
                // Any additional UI updates after loading
            }
        }
    }
    
    private func refreshFriendRequests() async {
        await withCheckedContinuation { continuation in
            viewModel.fetchFriendRequests {
                continuation.resume()
            }
        }
    }
    
    private func handleAcceptRequest(_ request: FriendRequest) {
        guard processingRequestId == nil else { return }
        
        processingRequestId = request.id
        
        viewModel.acceptFriendRequest(requestId: request.id) { [weak viewModel] success, message in
            DispatchQueue.main.async {
                self.processingRequestId = nil
                
                if success {
                    // Show success message briefly
                    self.showSuccessAlert(message: message)
                    
                    // Post notification for other views to refresh
                    NotificationCenter.default.post(
                        name: NSNotification.Name("FriendRequestAccepted"),
                        object: nil,
                        userInfo: ["friendId": request.senderId]
                    )
                } else {
                    self.showErrorAlert(message: message)
                }
            }
        }
    }
    
    private func handleDeclineRequest(_ request: FriendRequest) {
        guard processingRequestId == nil else { return }
        
        processingRequestId = request.id
        
        viewModel.declineFriendRequest(requestId: request.id) { success, message in
            DispatchQueue.main.async {
                self.processingRequestId = nil
                
                if success {
                    // For decline, we might not want to show success alert
                    // Just log or handle silently
                    print("Đã từ chối lời mời kết bạn thành công")
                } else {
                    self.showErrorAlert(message: message)
                }
            }
        }
    }
    
    private func showSuccessAlert(message: String) {
        alertTitle = "Thành công"
        alertMessage = message
        showAlert = true
    }
    
    private func showErrorAlert(message: String) {
        alertTitle = "Lỗi"
        alertMessage = message
        showAlert = true
    }
}

struct FriendRequestRow: View {
    let request: FriendRequest
    let isProcessing: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    @State private var senderName = ""
    @State private var senderImage: String?
    @State private var isLoadingSenderInfo = true
    
    var body: some View {
        HStack {
            // Avatar with loading state
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                
                if isLoadingSenderInfo {
                    ProgressView()
                        .scaleEffect(0.7)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if let senderImage = senderImage {
                    AsyncImage(url: URL(string: senderImage)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Text(getInitials(from: senderName))
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
                } else {
                    Text(getInitials(from: senderName))
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(senderName.isEmpty ? request.senderEmail : senderName)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("Muốn kết bạn với bạn")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                // Show email if different from name
                if !senderName.isEmpty && senderName != request.senderEmail {
                    Text(request.senderEmail)
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.8))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 12) {
                // Decline button
                Button(action: {
                    print("DEBUG: Decline button tapped for request: \(request.id)")
                    onDecline()
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(width: 36, height: 36)
                        
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                        } else {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.gray)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isProcessing)
                
                // Accept button
                Button(action: {
                    print("DEBUG: Accept button tapped for request: \(request.id)")
                    onAccept()
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.4, green: 0.9, blue: 0.8),
                                        Color(red: 0.6, green: 0.4, blue: 0.9),
                                        Color(red: 1.0, green: 0.7, blue: 0.4)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .opacity(isProcessing ? 0.6 : 1.0)
                            .frame(width: 36, height: 36)
                        
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        } else {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.black)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isProcessing)
            }
        }
        .padding(.vertical, 4)
        .opacity(isProcessing ? 0.7 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isProcessing)
        .onAppear {
            loadSenderInfo()
        }

    }
    
    private func loadSenderInfo() {
        let db = Firestore.firestore()
        
        db.collection("users").document(request.senderId).getDocument { snapshot, error in
            DispatchQueue.main.async {
                self.isLoadingSenderInfo = false
                
                guard let data = snapshot?.data() else {
                    // Fallback to email if user data not found
                    self.senderName = self.request.senderEmail
                    return
                }
                
                if let name = data["fullName"] as? String, !name.isEmpty {
                    self.senderName = name
                } else {
                    self.senderName = self.request.senderEmail
                }
                
                if let imageUrl = data["profileImageUrl"] as? String, !imageUrl.isEmpty {
                    self.senderImage = imageUrl
                }
            }
        }
    }
    
    private func getInitials(from name: String) -> String {
        if name.isEmpty {
            return "?"
        }
        
        let formatter = PersonNameComponentsFormatter()
        if let components = formatter.personNameComponents(from: name) {
            formatter.style = .abbreviated
            let initials = formatter.string(from: components)
            return initials.isEmpty ? String(name.prefix(1)).uppercased() : initials
        }
        
        // Fallback: get first character
        return String(name.prefix(1)).uppercased()
    }
}

// MARK: - Preview
struct FriendRequestsView_Previews: PreviewProvider {
    static var previews: some View {
        FriendRequestsView()
            .environmentObject(AuthViewModel())
            .preferredColorScheme(.dark)
    }
}
