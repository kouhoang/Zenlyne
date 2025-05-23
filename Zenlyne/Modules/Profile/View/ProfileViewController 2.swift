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
                    ProfileHeaderView(
                        viewModel: viewModel,
                        selectedItem: $selectedItem,
                        showingPhotoPicker: $showingPhotoPicker
                    )
                    
                    AccountSettingsSection(viewModel: viewModel)
                    
                    AppInfoSection()
                    
                    AccountActionsSection(showDeleteConfirmation: $showDeleteConfirmation)
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

#Preview {
    ProfileViewController()
        .environmentObject(AuthViewModel())
}
