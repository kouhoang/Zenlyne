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
    @State private var selectedRequest: FriendRequest? = nil
    @State private var showAddFriendSheet = false
    @State private var showingActionSheet = false
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    headerSection
                    
                    if viewModel.isLoading && viewModel.friendRequests.isEmpty {
                        loadingSection
                    } else if viewModel.friendRequests.isEmpty {
                        emptyStateSection
                    } else {
                        requestsListSection
                    }
                    
                    errorSection
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
                    HStack(spacing: 16) {
                        Button(action: {
                            showAddFriendSheet = true
                        }) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .foregroundColor(.blue)
                        }
                        
                        Button("Đóng") {
                            dismiss()
                        }
                        .foregroundColor(.white)
                        .disabled(processingRequestId != nil)
                    }
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                viewModel.fetchFriendRequests()
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK")) {
                        if alertTitle == "Lỗi" {
                            viewModel.errorMessage = ""
                        }
                    }
                )
            }
            .actionSheet(isPresented: $showingActionSheet) {
                ActionSheet(
                    title: Text("Xác nhận hành động"),
                    message: Text("Bạn có chắc chắn muốn thực hiện hành động này?"),
                    buttons: [
                        .default(Text("Chấp nhận")) {
                            if let request = selectedRequest {
                                handleAcceptRequest(request)
                            }
                        },
                        .destructive(Text("Từ chối")) {
                            if let request = selectedRequest {
                                handleDeclineRequest(request)
                            }
                        },
                        .cancel()
                    ]
                )
            }
            .onReceive(viewModel.$errorMessage) { errorMessage in
                if !errorMessage.isEmpty {
                    showErrorAlert(message: errorMessage)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("Lời mời kết bạn")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
                
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            if !viewModel.friendRequests.isEmpty {
                HStack {
                    Text("Những người muốn kết bạn với bạn")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.fetchFriendRequests()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                            Text("Làm mới")
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                    }
                    .disabled(viewModel.isLoading)
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
        }
        .padding(.bottom, 8)
    }
    
    private var loadingSection: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            
            Text("Đang tải lời mời kết bạn...")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
    
    private var emptyStateSection: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 80))
                    .foregroundColor(.gray.opacity(0.6))
                
                VStack(spacing: 8) {
                    Text("Không có lời mời kết bạn")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text("Khi có người gửi lời mời kết bạn,\nbạn sẽ thấy họ ở đây")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }
            
            VStack(spacing: 12) {
                Button(action: {
                    showAddFriendSheet = true
                }) {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 16))
                        Text("Thêm bạn bè")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue)
                    )
                }
                .padding(.horizontal, 40)
                
                Text("Hoặc chia sẻ thông tin liên hệ của bạn")
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }
    
    private var requestsListSection: some View {
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
                    },
                    onTap: {
                        selectedRequest = request
                        showingActionSheet = true
                    }
                )
                .listRowBackground(Color.black)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(PlainListStyle())
        .background(Color.black)
        .scrollContentBackground(.hidden)
        .refreshable {
            if processingRequestId == nil {
                await refreshFriendRequests()
            }
        }
    }
    
    private var errorSection: some View {
        Group {
            if !viewModel.errorMessage.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    
                    Text(viewModel.errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Button("Đóng") {
                        viewModel.errorMessage = ""
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.horizontal)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func refreshFriendRequests() async {
        await withCheckedContinuation { continuation in
            viewModel.fetchFriendRequests()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                continuation.resume()
            }
        }
    }
    
    private func handleAcceptRequest(_ request: FriendRequest) {
        guard processingRequestId == nil else { return }
        
        processingRequestId = request.id
        viewModel.acceptFriendRequest(request)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.processingRequestId = nil
            
            // Post notification for other views to refresh
            NotificationCenter.default.post(
                name: NSNotification.Name("FriendRequestAccepted"),
                object: nil,
                userInfo: ["friendId": request.senderId]
            )
        }
    }
    
    private func handleDeclineRequest(_ request: FriendRequest) {
        guard processingRequestId == nil else { return }
        
        processingRequestId = request.id
        viewModel.declineFriendRequest(request)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.processingRequestId = nil
        }
    }
    
    private func showErrorAlert(message: String) {
        alertTitle = "Lỗi"
        alertMessage = message
        showAlert = true
    }
}

// MARK: - FriendRequestRow Component
struct FriendRequestRow: View {
    let request: FriendRequest
    let isProcessing: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onTap: () -> Void
    
    @State private var senderName = ""
    @State private var senderImage: String?
    @State private var isLoadingSenderInfo = true
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar with loading state
                avatarSection
                
                // User info
                userInfoSection
                
                Spacer()
                
                // Action buttons
                actionButtonsSection
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6).opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            )
            .opacity(isProcessing ? 0.7 : 1.0)
            .scaleEffect(isProcessing ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isProcessing)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadSenderInfo()
        }
    }
    
    private var avatarSection: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 56, height: 56)
            
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
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .frame(width: 52, height: 52)
                .clipShape(Circle())
            } else {
                Text(getInitials(from: senderName))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            
            // Online status indicator (if available)
            Circle()
                .fill(Color.green)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.black, lineWidth: 2)
                )
                .offset(x: 20, y: 20)
        }
    }
    
    private var userInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(senderName.isEmpty ? request.senderEmail : senderName)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(1)
            
            Text("Muốn kết bạn với bạn")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            if !senderName.isEmpty && senderName != request.senderEmail {
                Text(request.senderEmail)
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.8))
                    .lineLimit(1)
            }
            
            // Time stamp
            Text(timeAgoString(from: request.timestamp))
                .font(.caption2)
                .foregroundColor(.gray.opacity(0.6))
        }
    }
    
    private var actionButtonsSection: some View {
        HStack(spacing: 8) {
            // Decline button
            Button(action: onDecline) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 40, height: 40)
                    
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
            Button(action: onAccept) {
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
                        .frame(width: 40, height: 40)
                    
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
    
    // MARK: - Helper Methods
    
    private func loadSenderInfo() {
        let db = Firestore.firestore()
        
        db.collection("users").document(request.senderId).getDocument { snapshot, error in
            DispatchQueue.main.async {
                self.isLoadingSenderInfo = false
                
                guard let data = snapshot?.data() else {
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
        
        return String(name.prefix(1)).uppercased()
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct FriendRequestsView_Previews: PreviewProvider {
    static var previews: some View {
        FriendRequestsView()
            .environmentObject(AuthViewModel())
            .preferredColorScheme(.dark)
    }
}
