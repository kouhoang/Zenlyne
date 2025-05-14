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
                self.errorMessage = "Error loading user data: \(error.localizedDescription)"
                return
            }
            
            if let document = snapshot, document.exists, let data = document.data() {
                DispatchQueue.main.async {
                    self.userFullName = data["fullName"] as? String ?? ""
                    self.newFullName = self.userFullName
                    
                    // Load profile image if available
                    if let profileImageUrl = data["profileImageUrl"] as? String, let url = URL(string: profileImageUrl) {
                        self.loadProfileImage(from: url)
                    }
                }
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
    
    func uploadProfileImage(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(false)
            return
        }
        
        isLoading = true
        guard let imageData = image.jpegData(compressionQuality: 0.5) else {
            isLoading = false
            errorMessage = "Failed to process image"
            completion(false)
            return
        }
        
        let filename = "\(currentUser.uid).jpg"
        let storageRef = Storage.storage().reference().child("profile_images").child(filename)
        
        storageRef.putData(imageData, metadata: nil) { [weak self] metadata, error in
            guard let self = self else { return }
            
            if let error = error {
                self.isLoading = false
                self.errorMessage = "Upload failed: \(error.localizedDescription)"
                completion(false)
                return
            }
            
            storageRef.downloadURL { [weak self] url, error in
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Failed to get image URL: \(error.localizedDescription)"
                    completion(false)
                    return
                }
                
                guard let imageUrl = url?.absoluteString else {
                    self.errorMessage = "Invalid image URL"
                    completion(false)
                    return
                }
                
                // Update user profile in Firestore
                self.updateUserProfileImage(imageUrl: imageUrl) { success in
                    if success {
                        self.successMessage = "Profile picture updated"
                    }
                    completion(success)
                }
            }
        }
    }
    
    func updateUserProfileImage(imageUrl: String, completion: @escaping (Bool) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(false)
            return
        }
        
        let userRef = db.collection("users").document(currentUser.uid)
        userRef.updateData(["profileImageUrl": imageUrl]) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                self.errorMessage = "Failed to update profile: \(error.localizedDescription)"
                completion(false)
                return
            }
            
            completion(true)
        }
    }
    
    // MARK: - Update User Profile
    
    func updateUserName(completion: @escaping (Bool) -> Void) {
        guard !newFullName.isEmpty else {
            errorMessage = "Name cannot be empty"
            completion(false)
            return
        }
        
        guard let currentUser = Auth.auth().currentUser else {
            completion(false)
            return
        }
        
        isLoading = true
        
        // Update display name in Firebase Auth
        let profileChangeRequest = currentUser.createProfileChangeRequest()
        profileChangeRequest.displayName = newFullName
        
        profileChangeRequest.commitChanges { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                self.isLoading = false
                self.errorMessage = "Failed to update auth profile: \(error.localizedDescription)"
                completion(false)
                return
            }
            
            // Update name in Firestore
            let userRef = self.db.collection("users").document(currentUser.uid)
            userRef.updateData(["fullName": self.newFullName]) { [weak self] error in
                guard let self = self else { return }
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
    
    func updatePassword(completion: @escaping (Bool) -> Void) {
        guard newPassword.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
            completion(false)
            return
        }
        
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords do not match"
            completion(false)
            return
        }
        
        guard let currentUser = Auth.auth().currentUser else {
            completion(false)
            return
        }
        
        isLoading = true
        
        // Reauthenticate user with current password
        let credential = EmailAuthProvider.credential(withEmail: userEmail, password: currentPassword)
        
        currentUser.reauthenticate(with: credential) { [weak self] _, error in
            guard let self = self else { return }
            
            if let error = error {
                self.isLoading = false
                self.errorMessage = "Current password is incorrect: \(error.localizedDescription)"
                completion(false)
                return
            }
            
            // Update password
            currentUser.updatePassword(to: self.newPassword) { [weak self] error in
                guard let self = self else { return }
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
