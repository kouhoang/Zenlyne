//
//  AvatarManager.swift
//  Zenlyne
//
//  Created by admin on 22/5/25.
//

import Foundation
import SwiftUI
import FirebaseAuth

class AvatarManager: ObservableObject {
    static let shared = AvatarManager()
    
    @Published var userAvatars: [String: String] = [:]
    @Published var currentUserAvatarUrl: String?
    
    private let firebaseService = FirebaseService()
    private var avatarObservers: [String: Any] = [:]
    
    private init() {
        setupNotificationObservers()
        loadCurrentUserAvatar()
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        // Listen for avatar updates
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AvatarUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let userInfo = notification.userInfo,
               let userId = userInfo["userId"] as? String,
               let avatarUrl = userInfo["avatarUrl"] as? String {
                self?.userAvatars[userId] = avatarUrl
                
                // Update current user avatar if it's them
                if userId == Auth.auth().currentUser?.uid {
                    self?.currentUserAvatarUrl = avatarUrl
                }
            }
        }
        
        // Listen for auth state changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("UserLoggedIn"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadCurrentUserAvatar()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("UserLoggedOut"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearAllAvatars()
        }
    }
    
    // MARK: - Current User Avatar
    
    private func loadCurrentUserAvatar() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        firebaseService.getUserAvatar(userId: currentUserId) { [weak self] avatarUrl in
            DispatchQueue.main.async {
                self?.currentUserAvatarUrl = avatarUrl
                if let avatarUrl = avatarUrl {
                    self?.userAvatars[currentUserId] = avatarUrl
                }
            }
        }
    }
    
    // MARK: - Avatar Management
    
    func getAvatarUrl(for userId: String) -> String? {
        return userAvatars[userId]
    }
    
    func updateAvatar(for userId: String, avatarUrl: String) {
        userAvatars[userId] = avatarUrl
        
        if userId == Auth.auth().currentUser?.uid {
            currentUserAvatarUrl = avatarUrl
        }
        
        // Post notification for UI updates
        NotificationCenter.default.post(
            name: NSNotification.Name("AvatarUpdated"),
            object: nil,
            userInfo: [
                "userId": userId,
                "avatarUrl": avatarUrl
            ]
        )
    }
    
    func loadFriendsAvatars(friendIds: [String]) {
        firebaseService.batchUpdateFriendsAvatars(friendIds: friendIds) { [weak self] avatarUrls in
            DispatchQueue.main.async {
                for (friendId, avatarUrl) in avatarUrls {
                    self?.userAvatars[friendId] = avatarUrl
                }
            }
        }
    }
    
    func observeUserAvatar(userId: String) {
        // Don't create duplicate observers
        guard avatarObservers[userId] == nil else { return }
        
        let listener = firebaseService.observeUserAvatar(userId: userId) { [weak self] avatarUrl in
            DispatchQueue.main.async {
                if let avatarUrl = avatarUrl {
                    self?.userAvatars[userId] = avatarUrl
                } else {
                    self?.userAvatars.removeValue(forKey: userId)
                }
                
                // Update current user if it's them
                if userId == Auth.auth().currentUser?.uid {
                    self?.currentUserAvatarUrl = avatarUrl
                }
            }
        }
        
        avatarObservers[userId] = listener
    }
    
    func stopObservingUserAvatar(userId: String) {
        if avatarObservers[userId] != nil {
            // Remove the listener (implementation depends on Firebase SDK)
            avatarObservers.removeValue(forKey: userId)
        }
    }
    
    private func clearAllAvatars() {
        userAvatars.removeAll()
        currentUserAvatarUrl = nil
        
        // Stop all observers
        for (_, _) in avatarObservers {
            // Remove listeners
        }
        avatarObservers.removeAll()
    }
    
    // MARK: - Helper Methods
    
    func preloadAvatarsForUsers(_ users: [User]) {
        let userIds = users.map { $0.id }
        loadFriendsAvatars(friendIds: userIds)
        
        // Start observing each user's avatar
        for userId in userIds {
            observeUserAvatar(userId: userId)
        }
    }
}
