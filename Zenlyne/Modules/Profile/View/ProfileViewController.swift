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
            List {
                // Profile Section
                Section {
                    VStack(spacing: 20) {
                        // Profile Image - Only the circle is a button
                        VStack {
                            ZStack {
                                // The avatar circle inside a button
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
                                .onTapGesture {
                                    showingPhotoPicker = true
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
                        
                        // Full Name - This is now outside the button
                        if viewModel.isEditingName {
                            HStack {
                                TextField("Full Name", text: $viewModel.newFullName)
                                    .font(.headline)
                                    .autocapitalization(.words)
                                    .disableAutocorrection(true)
                                
                                Spacer()
                                
                                HStack(spacing: 10) {
                                    Button(action: {
                                        viewModel.cancelNameEdit()
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                    
                                    Button(action: {
                                        viewModel.updateUserName { _ in }
                                    }) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                        } else {
                            HStack {
                                Text(viewModel.userFullName)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                
                                Spacer()
                                
                                Button(action: {
                                    viewModel.isEditingName = true
                                    viewModel.newFullName = viewModel.userFullName
                                }) {
                                    Image(systemName: "pencil.circle")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        
                        // Email
                        HStack {
                            Text(viewModel.userEmail)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                
                // Account settings section
                Section(header: Text("Account Settings")) {
                    // Change Password
                    if viewModel.isEditingPassword {
                        VStack(spacing: 15) {
                            SecureField("Current Password", text: $viewModel.currentPassword)
                                .textContentType(.password)
                                .padding(.vertical, 8)
                            
                            SecureField("New Password", text: $viewModel.newPassword)
                                .textContentType(.newPassword)
                                .padding(.vertical, 8)
                            
                            SecureField("Confirm New Password", text: $viewModel.confirmPassword)
                                .textContentType(.newPassword)
                                .padding(.vertical, 8)
                            
                            HStack {
                                Spacer()
                                
                                Button(action: {
                                    viewModel.cancelPasswordEdit()
                                }) {
                                    Text("Cancel")
                                        .foregroundColor(.red)
                                }
                                .padding(.trailing, 10)
                                
                                Button(action: {
                                    viewModel.updatePassword { success in
                                        if success {
                                            alertTitle = "Success"
                                            alertMessage = "Password updated successfully."
                                            showAlert = true
                                        }
                                    }
                                }) {
                                    Text("Update Password")
                                        .foregroundColor(.blue)
                                }
                                .disabled(viewModel.currentPassword.isEmpty ||
                                          viewModel.newPassword.isEmpty ||
                                          viewModel.confirmPassword.isEmpty)
                            }
                        }
                    } else {
                        Button(action: {
                            viewModel.isEditingPassword = true
                        }) {
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.blue)
                                Text("Change Password")
                            }
                        }
                    }
                    
                    // Privacy Settings
                    NavigationLink(destination: PrivacySettingsView()) {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                                .foregroundColor(.blue)
                            Text("Privacy Settings")
                        }
                    }
                    
                    // Notification Settings
                    NavigationLink(destination: NotificationSettingsView()) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.blue)
                            Text("Notification Settings")
                        }
                    }
                }
                
                // Application info section
                Section(header: Text("App Information")) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("About Zenlyne")
                        Spacer()
                        Text("Version 1.0.0")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    
                    NavigationLink(destination: HelpSupportView()) {
                        HStack {
                            Image(systemName: "questionmark.circle.fill")
                                .foregroundColor(.blue)
                            Text("Help & Support")
                        }
                    }
                    
                    Link(destination: URL(string: "https://zenlyne.app/terms")!) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.blue)
                            Text("Terms of Service")
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Link(destination: URL(string: "https://zenlyne.app/privacy")!) {
                        HStack {
                            Image(systemName: "shield.fill")
                                .foregroundColor(.blue)
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // Account actions section
                Section {
                    Button(action: {
                        authViewModel.signOut()
                    }) {
                        HStack {
                            Image(systemName: "arrow.left.circle.fill")
                                .foregroundColor(.red)
                            Text("Sign Out")
                                .foregroundColor(.red)
                        }
                    }
                    
                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("Delete Account")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .actionSheet(isPresented: $showDeleteConfirmation) {
                ActionSheet(
                    title: Text("Delete Account"),
                    message: Text("Are you sure you want to delete your account? This action cannot be undone and all your data will be permanently removed."),
                    buttons: [
                        .destructive(Text("Delete Account")) {
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
            Section(header: Text("Location Sharing")) {
                Toggle("Share My Location", isOn: .constant(true))
                    .tint(.blue)
                
                Toggle("Show My Online Status", isOn: .constant(true))
                    .tint(.blue)
                
                Toggle("Show Last Seen Time", isOn: .constant(true))
                    .tint(.blue)
            }
            
            Section(header: Text("Who Can See My Location")) {
                NavigationLink(destination: Text("Location Permission Settings")) {
                    Text("Friends Only")
                }
            }
            
            Section(header: Text("Data Privacy")) {
                Button("Download My Data") {
                    // Implement data download
                }
                
                Button("Manage Location History") {
                    // Implement location history management
                }
            }
        }
        .navigationTitle("Privacy Settings")
    }
}

struct NotificationSettingsView: View {
    var body: some View {
        List {
            Section(header: Text("Push Notifications")) {
                Toggle("Friend Requests", isOn: .constant(true))
                    .tint(.blue)
                
                Toggle("Friend Location Updates", isOn: .constant(true))
                    .tint(.blue)
                
                Toggle("Messages", isOn: .constant(true))
                    .tint(.blue)
                
                Toggle("Friend Activity", isOn: .constant(true))
                    .tint(.blue)
            }
            
            Section(header: Text("Email Notifications")) {
                Toggle("Account Updates", isOn: .constant(true))
                    .tint(.blue)
                
                Toggle("Security Alerts", isOn: .constant(true))
                    .tint(.blue)
                
                Toggle("Newsletter", isOn: .constant(false))
                    .tint(.blue)
            }
        }
        .navigationTitle("Notifications")
    }
}

struct HelpSupportView: View {
    var body: some View {
        List {
            Section(header: Text("Support")) {
                NavigationLink(destination: FAQView()) {
                    Text("Frequently Asked Questions")
                }
                
                NavigationLink(destination: Text("Tutorial Content")) {
                    Text("How to Use Zenlyne")
                }
                
                Button(action: {
                    // Implement contact us action
                    if let url = URL(string: "mailto:support@zenlyne.app") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("Contact Support")
                }
            }
            
            Section(header: Text("Troubleshooting")) {
                Button(action: {
                    // Implement refresh data action
                }) {
                    Text("Refresh Location Data")
                }
                
                Button(action: {
                    // Implement clear cache action
                }) {
                    Text("Clear App Cache")
                }
            }
            
            Section(header: Text("About")) {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0 (Build 101)")
                        .foregroundColor(.gray)
                }
                
                HStack {
                    Text("Device ID")
                    Spacer()
                    Text(UIDevice.current.identifierForVendor?.uuidString.prefix(8) ?? "Unknown")
                        .foregroundColor(.gray)
                }
            }
        }
        .navigationTitle("Help & Support")
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
                        .foregroundColor(.blue)
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
