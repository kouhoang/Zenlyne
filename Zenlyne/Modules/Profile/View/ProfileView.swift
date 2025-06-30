//
//  ProfileView.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore

struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = ProfileViewModel()
    @State private var selectedItem: PhotosPickerItem?
    @State private var showingPhotoPicker = false
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
        Task {
            await AccountDeletionService.shared.deleteAccount { result in
                switch result {
                case .success:
                    authViewModel.signOut()
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Sendable Data Structures
struct FriendRemovalUpdate: Sendable {
    let userIdToRemove: String
    
    func toDictionary() -> [String: Any] {
        return [
            "friendIds": FieldValue.arrayRemove([userIdToRemove])
        ]
    }
}

// MARK: - Account Deletion Service
actor AccountDeletionService {
    static let shared = AccountDeletionService()
    
    func deleteAccount(completion: @escaping (Result<Void, Error>) -> Void) async {
        guard let user = Auth.auth().currentUser else {
            await MainActor.run {
                completion(.failure(ProfileError.authenticationFailed("No user found")))
            }
            return
        }
        
        let db = Firestore.firestore()
        
        do {
            // 1. Delete user data from Firestore
            try await db.collection("users").document(user.uid).delete()
            
            // 2. Remove from friends' lists
            let friendsSnapshot = try await db.collection("users")
                .whereField("friendIds", arrayContains: user.uid)
                .getDocuments()
            
            // Create sendable update data before using
            let friendRemovalUpdate = FriendRemovalUpdate(userIdToRemove: user.uid)
            
            for document in friendsSnapshot.documents {
                try await db.collection("users").document(document.documentID)
                    .updateData(friendRemovalUpdate.toDictionary())
            }
            
            // 3. Delete authentication account
            try await user.delete()
            
            await MainActor.run {
                completion(.success(()))
            }
            
        } catch {
            await MainActor.run {
                completion(.failure(error))
            }
        }
    }
}
