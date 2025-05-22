//
//  ProfileViewModel.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import Foundation
import Firebase
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore
import SwiftUI
import Combine

class ProfileViewModel: ObservableObject {
    // User data
    @Published var userFullName: String = ""
    @Published var userEmail: String = ""
    @Published var profileImage: UIImage?
    
    // Edit mode states
    @Published var isEditingName: Bool = false
    @Published var isEditingPassword: Bool = false
    
    // New values
    @Published var newFullName: String = ""
    @Published var currentPassword: String = ""
    @Published var newPassword: String = ""
    @Published var confirmPassword: String = ""
    
    // Loading and error handling
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    @Published var successMessage: String = ""
    
    private var cancellables = Set<AnyCancellable>()
    private let db = Firestore.firestore()
    
    init() {
        loadUserData()
    }
    
    func loadUserData() {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        userEmail = currentUser.email ?? ""
        
        // Load user information from Firestore
        let userRef = db.collection("users").document(currentUser.uid)
        userRef.getDocument { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Error loading user data: \(error.localizedDescription)"
                }
                return
            }
            
            if let document = snapshot, document.exists, let data = document.data() {
                DispatchQueue.main.async {
                    self.userFullName = data["fullName"] as? String ?? ""
                    self.newFullName = self.userFullName
                    
                    // FIXED: Load profile image with priority for avatarUrl
                    let avatarUrl = data["avatarUrl"] as? String ?? data["profileImageUrl"] as? String
                    if let avatarUrl = avatarUrl, let url = URL(string: avatarUrl) {
                        self.loadProfileImage(from: url)
                        
                        // FIXED: Also notify other parts of the app about the avatar
                        NotificationCenter.default.post(
                            name: NSNotification.Name("UserAvatarLoaded"),
                            object: nil,
                            userInfo: [
                                "userId": currentUser.uid,
                                "avatarUrl": avatarUrl
                            ]
                        )
                    }
                }
            } else {
                print("DEBUG: No user document found in Firestore")
            }
        }
    }
    
    private func loadProfileImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            if let error = error {
                print("DEBUG: Failed to fetch image: \(error.localizedDescription)")
                return
            }
            
            guard let data = data, let image = UIImage(data: data) else { return }
            
            DispatchQueue.main.async {
                self?.profileImage = image
            }
        }.resume()
    }
    
    // FIXED: Updated upload method with better error handling and notifications
    func uploadProfileImage(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            DispatchQueue.main.async {
                self.errorMessage = "No authenticated user"
            }
            completion(false)
            return
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = ""
        }
        
        // Upload to Cloudinary
        CloudinaryService.shared.uploadImage(image) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let imageUrl):
                print("DEBUG: Successfully uploaded image to Cloudinary: \(imageUrl)")
                
                // Update user profile in Firestore
                self.updateUserProfileImage(imageUrl: imageUrl) { success in
                    DispatchQueue.main.async {
                        self.isLoading = false
                        
                        if success {
                            self.successMessage = "Avatar được cập nhật thành công"
                            
                            // FIXED: Post notification with proper data
                            NotificationCenter.default.post(
                                name: NSNotification.Name("AvatarUpdated"),
                                object: nil,
                                userInfo: [
                                    "userId": currentUser.uid,
                                    "avatarUrl": imageUrl
                                ]
                            )
                            
                            print("DEBUG: Posted avatar update notification for user: \(currentUser.uid)")
                        } else {
                            self.errorMessage = "Không thể cập nhật avatar trong database"
                        }
                    }
                    completion(success)
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Tải ảnh lên thất bại: \(error.localizedDescription)"
                }
                completion(false)
            }
        }
    }
    
    // FIXED: Updated database update method
    func updateUserProfileImage(imageUrl: String, completion: @escaping (Bool) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(false)
            return
        }
        
        let userRef = db.collection("users").document(currentUser.uid)
        
        // FIXED: Update both avatarUrl and profileImageUrl for backward compatibility
        let updateData: [String: Any] = [
            "avatarUrl": imageUrl,
            "profileImageUrl": imageUrl, // Keep for backward compatibility
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        userRef.updateData(updateData) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                print("DEBUG: Error updating profile image in Firestore: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to update profile: \(error.localizedDescription)"
                }
                completion(false)
                return
            }
            
            print("DEBUG: Successfully updated profile image in Firestore")
            completion(true)
        }
    }
    
    // MARK: - Update User Profile
    
    func updateUserName(completion: @escaping (Bool) -> Void) {
        guard !newFullName.isEmpty else {
            DispatchQueue.main.async {
                self.errorMessage = "Name cannot be empty"
            }
            completion(false)
            return
        }
        
        guard let currentUser = Auth.auth().currentUser else {
            completion(false)
            return
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        // Update display name in Firebase Auth
        let profileChangeRequest = currentUser.createProfileChangeRequest()
        profileChangeRequest.displayName = newFullName
        
        profileChangeRequest.commitChanges { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Failed to update auth profile: \(error.localizedDescription)"
                }
                completion(false)
                return
            }
            
            // Update name in Firestore
            let userRef = self.db.collection("users").document(currentUser.uid)
            userRef.updateData(["fullName": self.newFullName]) { [weak self] error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let error = error {
                        self.errorMessage = "Failed to update database: \(error.localizedDescription)"
                        completion(false)
                        return
                    }
                    
                    // Update was successful
                    self.userFullName = self.newFullName
                    self.isEditingName = false
                    self.successMessage = "Name updated successfully"
                    completion(true)
                }
            }
        }
    }
    
    func updatePassword(completion: @escaping (Bool) -> Void) {
        guard newPassword.count >= 6 else {
            DispatchQueue.main.async {
                self.errorMessage = "Password must be at least 6 characters"
            }
            completion(false)
            return
        }
        
        guard newPassword == confirmPassword else {
            DispatchQueue.main.async {
                self.errorMessage = "Passwords do not match"
            }
            completion(false)
            return
        }
        
        guard let currentUser = Auth.auth().currentUser else {
            completion(false)
            return
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        // Reauthenticate user with current password
        let credential = EmailAuthProvider.credential(withEmail: userEmail, password: currentPassword)
        
        currentUser.reauthenticate(with: credential) { [weak self] _, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Current password is incorrect: \(error.localizedDescription)"
                }
                completion(false)
                return
            }
            
            // Update password
            currentUser.updatePassword(to: self.newPassword) { [weak self] error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let error = error {
                        self.errorMessage = "Failed to update password: \(error.localizedDescription)"
                        completion(false)
                        return
                    }
                    
                    // Reset fields
                    self.isEditingPassword = false
                    self.currentPassword = ""
                    self.newPassword = ""
                    self.confirmPassword = ""
                    
                    self.successMessage = "Password updated successfully"
                    completion(true)
                }
            }
        }
    }
    
    func cancelNameEdit() {
        isEditingName = false
        newFullName = userFullName
    }
    
    func cancelPasswordEdit() {
        isEditingPassword = false
        currentPassword = ""
        newPassword = ""
        confirmPassword = ""
    }
}
