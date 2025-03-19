//
//  LoginViewModel.swift
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

@MainActor
class AuthViewModel: ObservableObject {
    @Published var userSessions: FirebaseAuth.User?
    @Published var currentUser: User?
    
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
            // create User with nessessary information
            let user = User(id: result.user.uid, fullName: fullName, email: email)
            // encode User object before saving into Firestore
            let encodedUser = try Firestore.Encoder().encode(user)
            // save user information into Firestore
            // QUAN TRỌNG: Đổi "user" thành "users" để đồng nhất với hàm fetchUser
            try await Firestore.firestore().collection("users").document(user.id).setData(encodedUser)
            await fetchUser()
        } catch {
            print("DEBUG: Failed to create user with error \(error.localizedDescription)")
            throw error
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut() // sign out user on backend
            self.userSessions = nil // sign out user session and takes us back to login screen
            self.currentUser = nil // wipe out current user data model
        }
        catch {
            print("DEBUG: Failed to sign out with error \(error.localizedDescription)")
        }
    }
    
    func deleteAccount() {
        
    }
    
    func fetchUser() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("DEBUG: No current user found")
            return
        }
        
        do {
            // Thêm print để debug
            print("DEBUG: Fetching user with ID: \(uid)")
            
            // Chỉ truy cập vào collection "users"
            let usersSnapshot = try await Firestore.firestore().collection("users").document(uid).getDocument()
            
            if usersSnapshot.exists {
                print("DEBUG: Document found in 'users' collection")
                self.currentUser = try usersSnapshot.data(as: User.self)
                print("DEBUG: Successfully decoded user data")
            } else {
                // Nếu không tìm thấy trong "users", thử tìm trong "user"
                print("DEBUG: Document not found in 'users' collection, trying 'user' collection")
                let userSnapshot = try await Firestore.firestore().collection("user").document(uid).getDocument()
                
                if userSnapshot.exists {
                    print("DEBUG: Document found in 'user' collection")
                    self.currentUser = try userSnapshot.data(as: User.self)
                    
                    // Di chuyển dữ liệu từ "user" sang "users" collection
                    let userData = userSnapshot.data() ?? [:]
                    try await Firestore.firestore().collection("users").document(uid).setData(userData)
                    print("DEBUG: Migrated user data from 'user' to 'users' collection")
                } else {
                    print("DEBUG: No user document found in either collection")
                    // Tạo một bản ghi mới nếu cần thiết
                    if let user = Auth.auth().currentUser {
                        let newUser = User(id: user.uid,
                                          fullName: user.displayName ?? "User",
                                          email: user.email ?? "")
                        let encodedUser = try Firestore.Encoder().encode(newUser)
                        try await Firestore.firestore().collection("users").document(uid).setData(encodedUser)
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
        
        // Cập nhật database
        let userRef = Firestore.firestore().collection("users").document(uid)
        userRef.updateData(["profileImageUrl": imageUrl]) { error in
            if let error = error {
                print("DEBUG: Failed to update user data with error: \(error.localizedDescription)")
                
                // Nếu có lỗi khi update, có thể document chưa tồn tại, thử setData thay vì updateData
                if let currentUser = self.currentUser {
                    var userData: [String: Any] = [
                        "id": currentUser.id,
                        "fullName": currentUser.fullName,
                        "email": currentUser.email,
                        "profileImageUrl": imageUrl
                    ]
                    
                    userRef.setData(userData) { error in
                        if let error = error {
                            print("DEBUG: Failed to set user data with error: \(error.localizedDescription)")
                        } else {
                            print("DEBUG: Successfully set user data with image URL")
                            // Cập nhật local model
                            Task { @MainActor in
                                await self.fetchUser()
                            }
                        }
                    }
                }
                return
            }
            
            print("DEBUG: Successfully updated user data with image URL")
            // Cập nhật local model
            Task { @MainActor in
                await self.fetchUser()
            }
        }
    }
}
