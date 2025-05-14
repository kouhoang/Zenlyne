//
//  AuthViewModel.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import Foundation
import Firebase
import FirebaseAuth
import FirebaseFirestore

protocol AuthentiicationFormProtocol {
    var formIsValid: Bool { get }
}

class AuthViewModel: ObservableObject {
    @Published var userSessions: FirebaseAuth.User?
    @Published var currentUser: User?
    @Published var isSignedOut = false
    @Published var resetPasswordSuccess = false
    @Published var resetPasswordError: String?
    
    init() {
        self.userSessions = Auth.auth().currentUser
        
        if self.userSessions != nil {
            Task {
                await fetchUser()  // load user information from Firebase when having sessions
            }
        }
    }
    
    func signIn(withEmail email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            self.userSessions = result.user
            await fetchUser()
            self.isSignedOut = false  // Reset sign out state on successful login
            
            // Set user as online after login
            let db = Firestore.firestore()
            db.collection("users").document(result.user.uid).updateData([
                "isOnline": true,
                "lastSeen": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    print("DEBUG: Error setting user online after login: \(error.localizedDescription)")
                }
            }
            
        } catch {
            print("DEBUG: Failed to login with error \(error.localizedDescription)")
            throw error
        }
    }

    func createUser(withEmail email: String, password: String, fullName: String) async throws {
        do {
            // create new user by Firebase Auth
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            // update user information into main thread
            self.userSessions = result.user
            // create User with necessary information
            let user = User(id: result.user.uid, fullName: fullName, email: email)
            // save user information into Firestore
            let userData: [String: Any] = [
                "id": user.id,
                "fullName": user.fullName,
                "email": user.email,
                "friendIds": []
            ]
            try await Firestore.firestore().collection("users").document(user.id).setData(userData)
            
            // Also update the display name in Firebase Auth
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = fullName
            try await changeRequest.commitChanges()
            
            await fetchUser()
        } catch {
            print("DEBUG: Failed to create user with error \(error.localizedDescription)")
            throw error
        }
    }
    
    func resetPassword(email: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            self.resetPasswordSuccess = true
            self.resetPasswordError = nil
        } catch {
            print("DEBUG: Failed to send password reset email with error \(error.localizedDescription)")
            self.resetPasswordSuccess = false
            self.resetPasswordError = error.localizedDescription
            throw error
        }
    }
    
    func signOut() {
        do {
            // Set user as offline before signing out
            if let currentUserId = Auth.auth().currentUser?.uid {
                let db = Firestore.firestore()
                
                // Update Firestore synchronously before signing out
                let semaphore = DispatchSemaphore(value: 0)
                
                db.collection("users").document(currentUserId).updateData([
                    "isOnline": false,
                    "lastSeen": FieldValue.serverTimestamp()
                ]) { error in
                    if let error = error {
                        print("DEBUG: Error setting user offline on logout: \(error.localizedDescription)")
                    } else {
                        print("DEBUG: Successfully set user offline on logout")
                    }
                    semaphore.signal()
                }
                
                // Wait briefly for the offline status to be set
                _ = semaphore.wait(timeout: .now() + 1.0)
            }
            
            try Auth.auth().signOut() // sign out user on backend
            self.userSessions = nil // This will trigger navigation back to login
            self.currentUser = nil // wipe out current user data model
            self.isSignedOut = true
        }
        catch {
            print("DEBUG: Failed to sign out with error \(error.localizedDescription)")
        }
    }
    
    func updateUserName(newName: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw AuthError.userNotFound
        }
        
        do {
            // 1. Update Auth profile
            let changeRequest = currentUser.createProfileChangeRequest()
            changeRequest.displayName = newName
            try await changeRequest.commitChanges()
            
            // 2. Update Firestore
            try await Firestore.firestore().collection("users").document(currentUser.uid).updateData([
                "fullName": newName
            ])
            
            // 3. Update local user
            await fetchUser()
        } catch {
            print("DEBUG: Failed to update user name with error \(error.localizedDescription)")
            throw error
        }
    }
    
    func updateUserPassword(currentPassword: String, newPassword: String) async throws {
        guard let currentUser = Auth.auth().currentUser,
              let email = currentUser.email else {
            throw AuthError.userNotFound
        }
        
        do {
            // 1. Reauthenticate user
            let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
            _ = try await currentUser.reauthenticate(with: credential)
            
            // 2. Update password
            try await currentUser.updatePassword(to: newPassword)
        } catch {
            print("DEBUG: Failed to update password with error \(error.localizedDescription)")
            throw error
        }
    }
    
    func fetchUser() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("DEBUG: No current user found")
            return
        }
        
        do {
            print("DEBUG: Fetching user with ID: \(uid)")
            
            let usersSnapshot = try await Firestore.firestore().collection("users").document(uid).getDocument()
            
            if usersSnapshot.exists {
                print("DEBUG: Document found in 'users' collection")
                if let userData = usersSnapshot.data(),
                   let fullName = userData["fullName"] as? String,
                   let email = userData["email"] as? String {
                    self.currentUser = User(id: uid, fullName: fullName, email: email)
                    
                    // Add profile image if available
                    if let profileImageUrl = userData["profileImageUrl"] as? String {
                        self.currentUser?.profileImageUrl = profileImageUrl
                    }
                    
                    print("DEBUG: Successfully decoded user data")
                }
            } else {
                print("DEBUG: Document not found in 'users' collection, trying 'user' collection")
                let userSnapshot = try await Firestore.firestore().collection("user").document(uid).getDocument()
                
                if userSnapshot.exists {
                    print("DEBUG: Document found in 'user' collection")
                    if let userData = userSnapshot.data(),
                       let email = userData["email"] as? String,
                       let fullName = userData["fullName"] as? String {
                        let newUser = User(id: uid, fullName: fullName, email: email)
                        
                        // Migrate data to 'users' collection
                        try await Firestore.firestore().collection("users").document(uid).setData([
                            "id": newUser.id,
                            "fullName": newUser.fullName,
                            "email": newUser.email
                        ])
                        self.currentUser = newUser
                        print("DEBUG: Migrated user data from 'user' to 'users' collection")
                    }
                } else {
                    print("DEBUG: No user document found in either collection")
                    if let user = Auth.auth().currentUser {
                        let newUser = User(id: user.uid,
                                          fullName: user.displayName ?? "User",
                                          email: user.email ?? "")
                        
                        try await Firestore.firestore().collection("users").document(uid).setData([
                            "id": newUser.id,
                            "fullName": newUser.fullName,
                            "email": newUser.email
                        ])
                        self.currentUser = newUser
                        print("DEBUG: Created new user document based on Auth info")
                    }
                }
            }
            
            if let user = self.currentUser {
                print("DEBUG: Current user is \(user.fullName) with email: \(user.email)")
            }
        } catch {
            print("DEBUG: Error fetching user: \(error.localizedDescription)")
            print("DEBUG: Error details: \(error)")
        }
    }
    
    func updateUserProfileImage(imageUrl: String) {
        guard let uid = self.userSessions?.uid else { return }
        
        let userRef = Firestore.firestore().collection("users").document(uid)
        userRef.updateData(["profileImageUrl": imageUrl]) { error in
            if let error = error {
                print("DEBUG: Failed to update user data with error: \(error.localizedDescription)")
                
                if let currentUser = self.currentUser {
                    let userData: [String: Any] = [
                        "id": currentUser.id,
                        "fullName": currentUser.fullName,
                        "email": currentUser.email,
                        "profileImageUrl": imageUrl
                    ]
                    
                    userRef.setData(userData, merge: true) { error in
                        if let error = error {
                            print("DEBUG: Failed to set user data with error: \(error.localizedDescription)")
                        } else {
                            print("DEBUG: Successfully set user data with image URL")
                            Task { @MainActor in
                                await self.fetchUser()
                            }
                        }
                    }
                }
                return
            }
            
            print("DEBUG: Successfully updated user data with image URL")
            Task { @MainActor in
                await self.fetchUser()
            }
        }
    }
    
    func ensureUserDocumentExists() async {
        guard let currentUser = Auth.auth().currentUser else {
            print("DEBUG: No user is currently logged in")
            return
        }
        
        let db = Firestore.firestore()
        let docRef = db.collection("users").document(currentUser.uid)
        
        do {
            let docSnapshot = try await docRef.getDocument()
            
            if !docSnapshot.exists {
                print("DEBUG: Creating missing user document for \(currentUser.email ?? "unknown email")")
                
                // Create basic user document
                let userData: [String: Any] = [
                    "id": currentUser.uid,
                    "fullName": currentUser.displayName ?? "User",
                    "email": currentUser.email ?? "",
                    "friendIds": []
                ]
                
                try await docRef.setData(userData)
                print("DEBUG: Successfully created user document")
                
                // Refresh current user information
                await fetchUser()
            } else {
                print("DEBUG: User document exists")
            }
        } catch {
            print("DEBUG: Error checking/creating user document: \(error.localizedDescription)")
        }
    }
}

enum AuthError: Error {
    case userNotFound
    case emailInUse
    case weakPassword
    case invalidEmail
    case wrongPassword
    case unknownError
}
