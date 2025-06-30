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
import Combine

protocol AuthentiicationFormProtocol {
    var formIsValid: Bool { get }
}

@MainActor
class AuthViewModel: ObservableObject {
    // MARK: - Published Properties (Giữ nguyên để tương thích)
    @Published var userSessions: FirebaseAuth.User?
    @Published var currentUser: User?
    @Published var isSignedOut = false
    @Published var resetPasswordSuccess = false
    @Published var resetPasswordError: String?
    
    // MARK: - Combine Publishers
    @Published private var authState: AuthState = .idle
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Auth State Listener Handle
    private var authStateListenerHandle: AuthStateDidChangeListenerHandle?
    
    // MARK: - Computed Properties
    var authStatePublisher: Published<AuthState>.Publisher { $authState }
    
    var isAuthenticated: Bool {
        return userSessions != nil && currentUser != nil
    }
    
    var isLoading: Bool {
        if case .loading = authState {
            return true
        }
        return false
    }
    
    // MARK: - Services
    private let firebaseService: FirebaseServiceProtocol
    
    // MARK: - Initialization
    init(firebaseService: FirebaseServiceProtocol = FirebaseService()) {
        self.firebaseService = firebaseService
        self.userSessions = Auth.auth().currentUser
        
        setupAuthStateListener()
        
        if self.userSessions != nil {
            Task {
                await fetchUser()
            }
        }
    }
    
    // MARK: - Deinit
    deinit {
        // Remove auth state listener when view model is deallocated
        if let handle = authStateListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    // MARK: - Private Methods
    private func setupAuthStateListener() {
        // Lưu trữ listener handle để có thể remove sau này
        authStateListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.userSessions = user
                if user != nil {
                    await self?.fetchUser()
                } else {
                    self?.currentUser = nil
                    self?.authState = .unauthenticated
                }
            }
        }
    }
    
    // MARK: - Public Methods (Giữ nguyên interface)
    
    func signIn(withEmail email: String, password: String) async throws {
        authState = .loading
        
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            self.userSessions = result.user
            await fetchUser()
            self.isSignedOut = false
            
            // Set user as online after login - Sử dụng async version
            await setUserOnlineStatus(userId: result.user.uid, isOnline: true)
            
            if let user = currentUser {
                authState = .authenticated(user)
            }
            
        } catch {
            print("DEBUG: Failed to login with error \(error.localizedDescription)")
            authState = .error(error.localizedDescription)
            throw error
        }
    }

    func createUser(withEmail email: String, password: String, fullName: String) async throws {
        authState = .loading
        
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            self.userSessions = result.user
            
            let user = User(id: result.user.uid, fullName: fullName, email: email)
            
            // Tạo userData trước khi vào async context để tránh sendable issues
            let userData = UserData(
                id: user.id,
                fullName: user.fullName,
                email: user.email,
                friendIds: []
            )
            
            try await Firestore.firestore().collection("users").document(user.id).setData(userData.toDictionary())
            
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = fullName
            try await changeRequest.commitChanges()
            
            await fetchUser()
            
            if let user = currentUser {
                authState = .authenticated(user)
            }
            
        } catch {
            print("DEBUG: Failed to create user with error \(error.localizedDescription)")
            authState = .error(error.localizedDescription)
            throw error
        }
    }
    
    func resetPassword(email: String) async throws {
        authState = .loading
        
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            self.resetPasswordSuccess = true
            self.resetPasswordError = nil
            authState = .idle
        } catch {
            print("DEBUG: Failed to send password reset email with error \(error.localizedDescription)")
            self.resetPasswordSuccess = false
            self.resetPasswordError = error.localizedDescription
            authState = .error(error.localizedDescription)
            throw error
        }
    }
    
    func signOut() {
        Task {
            do {
                if let currentUserId = Auth.auth().currentUser?.uid {
                    // Sử dụng async version thay vì synchronous version
                    await setUserOnlineStatus(userId: currentUserId, isOnline: false)
                }
                
                try Auth.auth().signOut()
                
                // Đảm bảo UI updates trên main actor
                await MainActor.run {
                    self.userSessions = nil
                    self.currentUser = nil
                    self.isSignedOut = true
                    self.authState = .unauthenticated
                }
                
            } catch {
                print("DEBUG: Failed to sign out with error \(error.localizedDescription)")
                await MainActor.run {
                    self.authState = .error(error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func setUserOnlineStatus(userId: String, isOnline: Bool) async {
        do {
            // Tạo updateData struct để tránh sendable issues
            let updateData = OnlineStatusUpdate(isOnline: isOnline)
            
            try await Firestore.firestore()
                .collection("users")
                .document(userId)
                .updateData(updateData.toDictionary())
            
            print("DEBUG: Successfully set user \(isOnline ? "online" : "offline")")
            
        } catch {
            print("DEBUG: Error setting user online status: \(error.localizedDescription)")
        }
    }
    
    func updateUserName(newName: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw AuthError.userNotFound
        }
        
        authState = .loading
        
        do {
            let changeRequest = currentUser.createProfileChangeRequest()
            changeRequest.displayName = newName
            try await changeRequest.commitChanges()
            
            // Sử dụng sendable struct thay vì dictionary literal
            let nameUpdate = UserNameUpdate(fullName: newName)
            try await Firestore.firestore().collection("users").document(currentUser.uid).updateData(nameUpdate.toDictionary())
            
            await fetchUser()
            
            if let user = self.currentUser {
                authState = .authenticated(user)
            }
            
        } catch {
            print("DEBUG: Failed to update user name with error \(error.localizedDescription)")
            authState = .error(error.localizedDescription)
            throw error
        }
    }
    
    func updateUserPassword(currentPassword: String, newPassword: String) async throws {
        guard let currentUser = Auth.auth().currentUser,
              let email = currentUser.email else {
            throw AuthError.userNotFound
        }
        
        authState = .loading
        
        do {
            let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
            _ = try await currentUser.reauthenticate(with: credential)
            
            try await currentUser.updatePassword(to: newPassword)
            
            authState = .idle
            
        } catch {
            print("DEBUG: Failed to update password with error \(error.localizedDescription)")
            authState = .error(error.localizedDescription)
            throw error
        }
    }
    
    func fetchUser() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("DEBUG: No current user found")
            authState = .unauthenticated
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
                    
                    var user = User(id: uid, fullName: fullName, email: email)
                    
                    // Add profile image if available
                    if let profileImageUrl = userData["profileImageUrl"] as? String {
                        user.profileImageUrl = profileImageUrl
                    }
                    
                    // Add avatar URL if available
                    if let avatarUrl = userData["avatarUrl"] as? String {
                        user.avatarUrl = avatarUrl
                    }
                    
                    self.currentUser = user
                    authState = .authenticated(user)
                    
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
                        let migrationData = UserData(
                            id: newUser.id,
                            fullName: newUser.fullName,
                            email: newUser.email,
                            friendIds: []
                        )
                        
                        try await Firestore.firestore().collection("users").document(uid).setData(migrationData.toDictionary())
                        self.currentUser = newUser
                        authState = .authenticated(newUser)
                        print("DEBUG: Migrated user data from 'user' to 'users' collection")
                    }
                } else {
                    print("DEBUG: No user document found in either collection")
                    if let user = Auth.auth().currentUser {
                        let newUser = User(id: user.uid,
                                          fullName: user.displayName ?? "User",
                                          email: user.email ?? "")
                        
                        let newUserData = UserData(
                            id: newUser.id,
                            fullName: newUser.fullName,
                            email: newUser.email,
                            friendIds: []
                        )
                        
                        try await Firestore.firestore().collection("users").document(uid).setData(newUserData.toDictionary())
                        self.currentUser = newUser
                        authState = .authenticated(newUser)
                        print("DEBUG: Created new user document based on Auth info")
                    }
                }
            }
            
            if let user = self.currentUser {
                print("DEBUG: Current user is \(user.fullName) with email: \(user.email)")
            }
            
        } catch {
            print("DEBUG: Error fetching user: \(error.localizedDescription)")
            authState = .error(error.localizedDescription)
        }
    }
    
    func updateUserProfileImage(imageUrl: String) async {
        guard let uid = self.userSessions?.uid else { return }
        
        let userRef = Firestore.firestore().collection("users").document(uid)
        
        // Tạo update data struct để tránh sendable issues
        let profileUpdate = ProfileImageUpdate(profileImageUrl: imageUrl)
        
        do {
            try await userRef.updateData(profileUpdate.toDictionary())
            print("DEBUG: Successfully updated user data with image URL")
            await fetchUser()
            
        } catch {
            print("DEBUG: Failed to update user data with error: \(error.localizedDescription)")
            
            // Fallback: create document if it doesn't exist
            if let currentUser = self.currentUser {
                let userData = UserData(
                    id: currentUser.id,
                    fullName: currentUser.fullName,
                    email: currentUser.email,
                    profileImageUrl: imageUrl,
                    friendIds: []
                )
                
                do {
                    try await userRef.setData(userData.toDictionary(), merge: true)
                    print("DEBUG: Successfully set user data with image URL")
                    await fetchUser()
                } catch {
                    print("DEBUG: Failed to set user data with error: \(error.localizedDescription)")
                }
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
                
                let userData = UserData(
                    id: currentUser.uid,
                    fullName: currentUser.displayName ?? "User",
                    email: currentUser.email ?? "",
                    friendIds: []
                )
                
                try await docRef.setData(userData.toDictionary())
                print("DEBUG: Successfully created user document")
                
                await fetchUser()
            } else {
                print("DEBUG: User document exists")
            }
        } catch {
            print("DEBUG: Error checking/creating user document: \(error.localizedDescription)")
            authState = .error(error.localizedDescription)
        }
    }
}

// MARK: - Sendable Data Structures

struct UserData: Sendable {
    let id: String
    let fullName: String
    let email: String
    let profileImageUrl: String?
    let avatarUrl: String?
    let friendIds: [String]
    
    init(id: String, fullName: String, email: String, profileImageUrl: String? = nil, avatarUrl: String? = nil, friendIds: [String] = []) {
        self.id = id
        self.fullName = fullName
        self.email = email
        self.profileImageUrl = profileImageUrl
        self.avatarUrl = avatarUrl
        self.friendIds = friendIds
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "fullName": fullName,
            "email": email,
            "friendIds": friendIds
        ]
        
        if let profileImageUrl = profileImageUrl {
            dict["profileImageUrl"] = profileImageUrl
        }
        
        if let avatarUrl = avatarUrl {
            dict["avatarUrl"] = avatarUrl
        }
        
        return dict
    }
}

struct OnlineStatusUpdate: Sendable {
    let isOnline: Bool
    let timestamp: FieldValue
    
    init(isOnline: Bool) {
        self.isOnline = isOnline
        self.timestamp = FieldValue.serverTimestamp()
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "isOnline": isOnline,
            "lastSeen": timestamp
        ]
    }
}

struct ProfileImageUpdate: Sendable {
    let profileImageUrl: String
    
    func toDictionary() -> [String: Any] {
        return [
            "profileImageUrl": profileImageUrl
        ]
    }
}

struct UserNameUpdate: Sendable {
    let fullName: String
    
    func toDictionary() -> [String: Any] {
        return [
            "fullName": fullName
        ]
    }
}


// MARK: - Combine Convenience Extensions
extension AuthViewModel {
    
    /// Publisher that emits when user authentication status changes
    var isAuthenticatedPublisher: AnyPublisher<Bool, Never> {
        $userSessions
            .map { $0 != nil }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    /// Publisher that emits current user changes
    var currentUserPublisher: AnyPublisher<User?, Never> {
        $currentUser
            .removeDuplicates { $0?.id == $1?.id }
            .eraseToAnyPublisher()
    }
    
    /// Publisher for loading state
    var isLoadingPublisher: AnyPublisher<Bool, Never> {
        $authState
            .map { state in
                if case .loading = state { return true }
                return false
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    /// Publisher for error state
    var errorPublisher: AnyPublisher<String?, Never> {
        $authState
            .map { state in
                if case .error(let message) = state { return message }
                return nil
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
