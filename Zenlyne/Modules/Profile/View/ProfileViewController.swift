//
//  ProfileViewController.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore

struct ProfileViewController: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = ProfileViewModel()
    @State private var selectedItem: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showDeleteConfirmation = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Profile Section with Background Image
                    VStack(alignment: .leading) {
                        Text("Hồ sơ")
                            .font(.headline)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                            .padding(.top, 20)
                            .padding(.bottom, 5)
                        
                        VStack(spacing: 20) {
                            VStack {
                                ZStack {
                                    // Only the avatar circle is interactive for changing photo
                                    Button(action: {
                                        showingPhotoPicker = true
                                    }) {
                                        ZStack {
                                            if let profileImage = viewModel.profileImage {
                                                Image(uiImage: profileImage)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 100, height: 100)
                                                    .clipShape(Circle())
                                                    .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                                            } else {
                                                Circle()
                                                    .fill(Color(.systemGray4))
                                                    .frame(width: 100, height: 100)
                                                    .overlay(
                                                        Text(getInitials(from: viewModel.userFullName))
                                                            .font(.system(size: 36, weight: .bold))
                                                            .foregroundColor(.white)
                                                    )
                                            }
                                            
                                            if viewModel.isLoading {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                    .frame(width: 100, height: 100)
                                                    .background(Color.black.opacity(0.3))
                                                    .clipShape(Circle())
                                            }
                                            
                                            // Camera icon overlay on the bottom right
                                            Circle()
                                                .fill(Color.blue)
                                                .frame(width: 32, height: 32)
                                                .overlay(
                                                    Image(systemName: "camera.fill")
                                                        .font(.system(size: 16))
                                                        .foregroundColor(.white)
                                                )
                                                .offset(x: 32, y: 32)
                                        }
                                    }
                                }
                                .padding(.top, 10)
                            }
                            .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedItem, matching: .images)
                            .onChange(of: selectedItem) { newItem in
                                Task {
                                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                                       let image = UIImage(data: data) {
                                        await MainActor.run {
                                            viewModel.profileImage = image
                                            viewModel.uploadProfileImage(image) { _ in }
                                        }
                                    }
                                }
                            }
                            
                            // Full Name section
                            if viewModel.isEditingName {
                                HStack {
                                    TextField("Tên", text: $viewModel.newFullName)
                                        .font(.headline)
                                        .autocapitalization(.words)
                                        .disableAutocorrection(true)
                                        .foregroundColor(.black)
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 10) {
                                        Button(action: {
                                            viewModel.cancelNameEdit()
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .frame(width: 44, height: 44)
                                        }
                                        
                                        Button(action: {
                                            viewModel.updateUserName { success in
                                                if success {
                                                    // No need to show alert since we show success banner
                                                }
                                            }
                                        }) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .frame(width: 44, height: 44)
                                        }
                                    }
                                }
                            } else {
                                HStack {
                                    // Name display - just text
                                    Text(viewModel.userFullName)
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                    
                                    Spacer()
                                    
                                    // ONLY pencil icon has action
                                    Button(action: {
                                        viewModel.isEditingName = true
                                        viewModel.newFullName = viewModel.userFullName
                                    }) {
                                        Image(systemName: "pencil.circle")
                                            .foregroundColor(.blue)
                                            .frame(width: 44, height: 44)
                                    }
                                }
                                .background(Color.clear)
                            }
                            
                            // Email
                            HStack {
                                Text(viewModel.userEmail)
                                    .font(.subheadline)
                                    .foregroundColor(.black.opacity(0.8))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            // Background image with overlay
                            ZStack {
                                Image("pink-yellow-plain")
                                    .resizable()
                                    .scaledToFill()
                                    .clipped()
                                
                                Color.black.opacity(0.1)
                            }
                        )
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                    
                    // Account settings section
                    VStack(alignment: .leading) {
                        Text("Cài đặt tài khoản")
                            .font(.headline)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                            .padding(.top, 20)
                            .padding(.bottom, 5)
                        
                        VStack(spacing: 0) {
                            // Change Password
                            if viewModel.isEditingPassword {
                                VStack(spacing: 15) {
                                    SecureField("Mật khẩu hiện tại", text: $viewModel.currentPassword)
                                        .textContentType(.password)
                                        .padding(.vertical, 8)
                                    
                                    SecureField("Mật khẩu mới", text: $viewModel.newPassword)
                                        .textContentType(.newPassword)
                                        .padding(.vertical, 8)
                                    
                                    SecureField("Xác nhận lại mật khẩu mới", text: $viewModel.confirmPassword)
                                        .textContentType(.newPassword)
                                        .padding(.vertical, 8)
                                    
                                    HStack {
                                        Spacer()
                                        
                                        Button(action: {
                                            viewModel.cancelPasswordEdit()
                                        }) {
                                            Text("Huỷ")
                                                .foregroundColor(.red)
                                        }
                                        .padding(.trailing, 10)
                                        
                                        Button(action: {
                                            viewModel.updatePassword { success in
                                                if success {
                                                    // Success message is already shown in banner
                                                    // from the viewModel
                                                }
                                            }
                                        }) {
                                            Text("Cập nhật mật khẩu")
                                                .foregroundColor(.blue)
                                        }
                                        .disabled(viewModel.currentPassword.isEmpty ||
                                                  viewModel.newPassword.isEmpty ||
                                                  viewModel.confirmPassword.isEmpty ||
                                                  viewModel.newPassword.count < 6 ||
                                                  viewModel.newPassword != viewModel.confirmPassword)
                                    }
                                }
                                .padding()
                                .background(Color.black)
                            } else {
                                Button(action: {
                                    viewModel.isEditingPassword = true
                                }) {
                                    HStack {
                                        IconContainer(systemName: "lock.fill")
                                        
                                        Text("Thay đổi mật khẩu")
                                            .foregroundColor(.white)
                                        Spacer()
                                    }
                                    .padding()
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            Divider()
                                .background(Color.gray.opacity(0.3))
                            
                            // Privacy Settings
                            NavigationLink(destination: PrivacySettingsView()) {
                                HStack {
                                    IconContainer(systemName: "hand.raised.fill")
                                    
                                    Text("Cài đặt Quyền riêng tư")
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                .padding()
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Divider()
                                .background(Color.gray.opacity(0.3))
                            
                            // Notification Settings
                            NavigationLink(destination: NotificationSettingsView()) {
                                HStack {
                                    IconContainer(systemName: "bell.fill")
                                    
                                    Text("Cài đặt thông báo")
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                .padding()
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .background(Color.black)
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                    
                    // Application info section
                    VStack(alignment: .leading) {
                        Text("Thông tin ứng dụng")
                            .font(.headline)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                            .padding(.top, 20)
                            .padding(.bottom, 5)
                        
                        VStack(spacing: 0) {
                            HStack {
                                IconContainer(systemName: "info.circle.fill")
                                
                                Text("Về Zenlyne")
                                    .foregroundColor(.white)
                                Spacer()
                                Text("Version 1.0.0")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                            .padding()
                            
                            Divider()
                                .background(Color.gray.opacity(0.3))
                            
                            NavigationLink(destination: HelpSupportView()) {
                                HStack {
                                    IconContainer(systemName: "questionmark.circle.fill")
                                    
                                    Text("Trợ giúp và Hỗ trợ")
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                .padding()
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Divider()
                                .background(Color.gray.opacity(0.3))
                            
                            Link(destination: URL(string: "https://zenlyne.app/terms")!) {
                                HStack {
                                    IconContainer(systemName: "doc.text.fill")
                                    
                                    Text("Điều khoản dịch vụ")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Image(systemName: "arrow.up.forward.app")
                                        .foregroundColor(.gray)
                                }
                                .padding()
                            }
                            
                            Divider()
                                .background(Color.gray.opacity(0.3))
                            
                            Link(destination: URL(string: "https://zenlyne.app/privacy")!) {
                                HStack {
                                    IconContainer(systemName: "shield.fill")
                                    
                                    Text("Chính sách bảo mật")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Image(systemName: "arrow.up.forward.app")
                                        .foregroundColor(.gray)
                                }
                                .padding()
                            }
                        }
                        .background(Color.black)
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                    
                    // Account actions section
                    VStack(alignment: .leading) {
                        Text("Hoạt động tài khoản")
                            .font(.headline)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                            .padding(.top, 20)
                            .padding(.bottom, 5)
                        
                        VStack(spacing: 0) {
                            Button(action: {
                                authViewModel.signOut()
                            }) {
                                HStack {
                                    IconContainer(systemName: "arrow.left.circle.fill")
                                    
                                    Text("Đăng xuất")
                                        .foregroundColor(.red)
                                    Spacer()
                                }
                                .padding()
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Divider()
                                .background(Color.gray.opacity(0.3))
                            
                            Button(action: {
                                showDeleteConfirmation = true
                            }) {
                                HStack {
                                    IconContainer(systemName: "xmark.circle.fill")
                                    
                                    Text("Xoá tài khoản")
                                        .foregroundColor(.red)
                                    Spacer()
                                }
                                .padding()
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .background(Color.black)
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Hồ sơ")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.black)
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .actionSheet(isPresented: $showDeleteConfirmation) {
                ActionSheet(
                    title: Text("Xóa tài khoản"),
                    message: Text("Bạn có chắc chắn muốn xóa tài khoản của mình không? Hành động này không thể hoàn tác và tất cả dữ liệu của bạn sẽ bị xóa vĩnh viễn."),
                    buttons: [
                        .destructive(Text("Xoá tài khoản")) {
                            // Implement account deletion functionality
                            deleteAccount()
                        },
                        .cancel()
                    ]
                )
            }
            .overlay(
                Group {
                    if !viewModel.errorMessage.isEmpty {
                        ErrorBanner(message: viewModel.errorMessage) {
                            viewModel.errorMessage = ""
                        }
                    } else if !viewModel.successMessage.isEmpty {
                        SuccessBanner(message: viewModel.successMessage) {
                            viewModel.successMessage = ""
                        }
                    }
                }
            )
        }
        .onAppear {
            viewModel.loadUserData()
        }
    }
    
    private func getInitials(from name: String) -> String {
        let formatter = PersonNameComponentsFormatter()
        if let components = formatter.personNameComponents(from: name) {
            formatter.style = .abbreviated
            return formatter.string(from: components)
        }
        
        // Fallback if formatter fails
        let words = name.split(separator: " ")
        if words.count > 1 {
            return String(words[0].prefix(1)) + String(words.last!.prefix(1))
        } else if !words.isEmpty {
            return String(words[0].prefix(1))
        } else {
            return "?"
        }
    }
    
    private func deleteAccount() {
        guard let user = Auth.auth().currentUser else { return }
        
        // 1. Get a reference to database
        let db = Firestore.firestore()
        
        // 2. Delete user data from Firestore
        db.collection("users").document(user.uid).delete { error in
            if let error = error {
                viewModel.errorMessage = "Error deleting user data: \(error.localizedDescription)"
                return
            }
            
            // 3. Delete friend relationships
            // Get friends who have this user as a friend
            db.collection("users").whereField("friendIds", arrayContains: user.uid)
                .getDocuments { snapshot, error in
                    if let documents = snapshot?.documents {
                        // Remove this user from each friend's friendIds array
                        for document in documents {
                            let friendId = document.documentID
                            db.collection("users").document(friendId).updateData([
                                "friendIds": FieldValue.arrayRemove([user.uid])
                            ])
                        }
                    }
                    
                    // 4. Delete user authentication account
                    user.delete { error in
                        if let error = error {
                            viewModel.errorMessage = "Error deleting account: \(error.localizedDescription)"
                            return
                        }
                        
                        // 5. Sign out and return to login screen
                        authViewModel.signOut()
                    }
                }
        }
    }
}

// MARK: - Helper Views

struct OTPModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .frame(height: 45)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .padding(.horizontal)
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                
                Text(message)
                    .foregroundColor(.white)
                    .font(.subheadline)
                
                Spacer()
                
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(Color.red)
            .cornerRadius(8)
            .padding()
            
            Spacer()
        }
    }
}

struct SuccessBanner: View {
    let message: String
    let dismiss: () -> Void
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.white)
                
                Text(message)
                    .foregroundColor(.white)
                    .font(.subheadline)
                
                Spacer()
                
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(Color.green)
            .cornerRadius(8)
            .padding()
            
            Spacer()
        }
    }
}

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
                
                Button("Manage Location History") {
                    // Implement location history management
                }
            }
        }
        .navigationTitle("Cài đặt quyền riêng tư")
        .background(.black.opacity(0.7))
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

#Preview {
    ProfileViewController()
        .environmentObject(AuthViewModel())
}
