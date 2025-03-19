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
            throw error  // Add this line to propagate the error
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
            try await Firestore.firestore().collection("user").document(user.id).setData(encodedUser)
            await fetchUser()
        } catch {
            print("DEBUG: Faild to create user with error \(error.localizedDescription)")
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
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        guard let snapshot = try? await Firestore.firestore().collection("user").document(uid).getDocument() else { return }
        self.currentUser = try? snapshot.data(as: User.self)
        
        print("DEBUG: Current user is \(self.currentUser)")
    }
}
