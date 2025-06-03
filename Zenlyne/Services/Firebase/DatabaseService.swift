//
//  FirebaseService.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import Foundation
import FirebaseDatabase
import FirebaseFirestore
import Combine
import CoreLocation

// MARK: - Protocol
protocol FirebaseServiceProtocol {
    func saveUserLocation(userId: String, location: UserLocation)
    func fetchUserLastLocation(userId: String, completion: @escaping (UserLocation?) -> Void)
    func observeFriendLocations(userIds: [String], completion: @escaping ([String: UserLocation]) -> Void)
    func stopObservingFriendLocations()
    func fetchFriends(forUserId userId: String, completion: @escaping ([User]) -> Void)
    func setUserOnlineStatus(userId: String, isOnline: Bool)
    func observeUserOnlineStatus(userId: String, completion: @escaping (Bool) -> Void)
    func stopObservingUserOnlineStatus(userId: String)
    func getPendingFriendRequestsCount(for userId: String, completion: @escaping (Int) -> Void)
    func removeFriend(currentUserId: String, friendId: String, completion: @escaping (Bool) -> Void)
    
    // Combine methods
    func userLocationPublisher(userId: String) -> AnyPublisher<UserLocation?, Never>
    func friendLocationsPublisher(userIds: [String]) -> AnyPublisher<[String: UserLocation], Never>
    func userOnlineStatusPublisher(userId: String) -> AnyPublisher<Bool, Never>
    func friendsPublisher(forUserId userId: String) -> AnyPublisher<[User], Never>
}

class FirebaseService: FirebaseServiceProtocol {
    private let database = Database.database().reference()
    private let firestore = Firestore.firestore()
    private var locationObservers: [Any] = []
    private var onlineStatusObservers: [String: DatabaseHandle] = [:]
    private var locationListeners: [String: ListenerRegistration] = [:]
    private var onlineStatusListeners: [String: ListenerRegistration] = [:]
    
    // Constants for expiration
    private let locationExpirationTime: TimeInterval = 72 * 60 * 60 // 72 hours
    
    // Combine subjects for reactive streams
    private var locationSubjects: [String: CurrentValueSubject<UserLocation?, Never>] = [:]
    private var onlineStatusSubjects: [String: CurrentValueSubject<Bool, Never>] = [:]
    private var friendLocationsSubject = CurrentValueSubject<[String: UserLocation], Never>([:])
    private var friendsSubjects: [String: CurrentValueSubject<[User], Never>] = [:]
    
    // MARK: - Combine Publishers
    func userLocationPublisher(userId: String) -> AnyPublisher<UserLocation?, Never> {
        if locationSubjects[userId] == nil {
            locationSubjects[userId] = CurrentValueSubject<UserLocation?, Never>(nil)
            observeUserLocation(userId: userId)
        }
        
        return locationSubjects[userId]!
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    func friendLocationsPublisher(userIds: [String]) -> AnyPublisher<[String: UserLocation], Never> {
        observeFriendLocations(userIds: userIds) { _ in }
        
        return friendLocationsSubject
            .map { [weak self] locations in
                // Filter out expired locations
                guard let self = self else { return locations }
                return self.filterValidLocations(locations)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    func userOnlineStatusPublisher(userId: String) -> AnyPublisher<Bool, Never> {
        if onlineStatusSubjects[userId] == nil {
            onlineStatusSubjects[userId] = CurrentValueSubject<Bool, Never>(false)
            observeUserOnlineStatus(userId: userId) { _ in }
        }
        
        return onlineStatusSubjects[userId]!
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    func friendsPublisher(forUserId userId: String) -> AnyPublisher<[User], Never> {
        if friendsSubjects[userId] == nil {
            friendsSubjects[userId] = CurrentValueSubject<[User], Never>([])
            
            // Start observing friends list changes
            observeFriendsList(userId: userId)
        }
        
        return friendsSubjects[userId]!
            .removeDuplicates { $0.map(\.id) == $1.map(\.id) }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Helper Methods
    
    private func filterValidLocations(_ locations: [String: UserLocation]) -> [String: UserLocation] {
        let currentTime = Date().timeIntervalSince1970
        
        return locations.filter { _, location in
            (currentTime - location.timestamp) < locationExpirationTime
        }
    }
    
    private func isLocationValid(_ location: UserLocation) -> Bool {
        let currentTime = Date().timeIntervalSince1970
        return (currentTime - location.timestamp) < locationExpirationTime
    }
    
    // MARK: - Observe Friends List Changes
    
    private func observeFriendsList(userId: String) {
        let userRef = firestore.collection("users").document(userId)
        
        let listener = userRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("DEBUG: Error observing friends list: \(error.localizedDescription)")
                return
            }
            
            guard let document = snapshot, document.exists,
                  let data = document.data(),
                  let friendIds = data["friendIds"] as? [String] else {
                print("DEBUG: No friends found for user \(userId)")
                self.friendsSubjects[userId]?.send([])
                return
            }
            
            print("DEBUG: Friends list changed, loading \(friendIds.count) friends")
            self.fetchFriendsDetails(friendIds: friendIds) { friends in
                self.friendsSubjects[userId]?.send(friends)
            }
        }
        
        // Store listener for cleanup
        locationListeners["friends_\(userId)"] = listener
    }
    
    private func fetchFriendsDetails(friendIds: [String], completion: @escaping ([User]) -> Void) {
        guard !friendIds.isEmpty else {
            completion([])
            return
        }
        
        var friends: [User] = []
        let group = DispatchGroup()
        
        for friendId in friendIds {
            group.enter()
            
            firestore.collection("users").document(friendId).getDocument { document, error in
                defer { group.leave() }
                
                if let error = error {
                    print("DEBUG: Error fetching friend \(friendId): \(error.localizedDescription)")
                    return
                }
                
                guard let document = document, document.exists,
                      let data = document.data() else {
                    print("DEBUG: Friend document not found: \(friendId)")
                    return
                }
                
                if let fullName = data["fullName"] as? String,
                   let email = data["email"] as? String {
                    var friend = User(id: friendId, fullName: fullName, email: email)
                    
                    friend.profileImageUrl = data["profileImageUrl"] as? String
                    friend.avatarUrl = data["avatarUrl"] as? String
                    friend.isOnline = data["isOnline"] as? Bool ?? false
                    
                    if let lastSeenTimestamp = data["lastSeen"] as? Timestamp {
                        friend.lastSeen = lastSeenTimestamp.dateValue()
                    }
                    
                    // Check for valid location data
                    if let locationData = data["lastLocation"] as? [String: Any],
                       let latitude = locationData["latitude"] as? Double,
                       let longitude = locationData["longitude"] as? Double,
                       let timestamp = locationData["timestamp"] as? TimeInterval {
                        
                        let location = UserLocation(
                            latitude: latitude,
                            longitude: longitude,
                            timestamp: timestamp
                        )
                        
                        // Only include location if it's not expired
                        if self.isLocationValid(location) {
                            friend.lastLocation = location
                            print("DEBUG: Friend \(fullName) has valid location: \(latitude), \(longitude)")
                        } else {
                            print("DEBUG: Friend \(fullName) location expired")
                        }
                    } else {
                        print("DEBUG: Friend \(fullName) has no location data")
                    }
                    
                    friends.append(friend)
                    print("DEBUG: Added friend: \(fullName) (ID: \(friendId))")
                }
            }
        }
        
        group.notify(queue: .main) {
            completion(friends)
        }
    }
    
    // MARK: - Original Methods
    
    func saveUserLocation(userId: String, location: UserLocation) {
        print("DEBUG: Attempting to save location for user \(userId): \(location.latitude), \(location.longitude)")
        
        let currentTime = Date().timeIntervalSince1970
        let expirationTime = currentTime + locationExpirationTime
        
        let locationData: [String: Any] = [
            "latitude": location.latitude,
            "longitude": location.longitude,
            "timestamp": location.timestamp,
            "updatedAt": FieldValue.serverTimestamp(),
            "expiresAt": expirationTime
        ]
        
        firestore.collection("users").document(userId).updateData([
            "lastLocation": locationData,
            "isOnline": true,
            "lastSeen": FieldValue.serverTimestamp()
        ]) { [weak self] error in
            if let error = error {
                print("DEBUG: Error saving location: \(error.localizedDescription)")
            } else {
                print("DEBUG: Successfully saved location for user \(userId)")
                self?.locationSubjects[userId]?.send(location)
            }
        }
    }
    
    func fetchUserLastLocation(userId: String, completion: @escaping (UserLocation?) -> Void) {
        firestore.collection("users").document(userId).getDocument { [weak self] snapshot, error in
            if let error = error {
                print("DEBUG: Error fetching user document: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let document = snapshot, document.exists,
                  let data = document.data(),
                  let locationData = data["lastLocation"] as? [String: Any] else {
                print("DEBUG: No location data found for user \(userId)")
                completion(nil)
                return
            }
            
            guard let latitude = locationData["latitude"] as? Double,
                  let longitude = locationData["longitude"] as? Double,
                  let timestamp = locationData["timestamp"] as? TimeInterval else {
                print("DEBUG: Invalid location data format")
                completion(nil)
                return
            }
            
            let userLocation = UserLocation(
                latitude: latitude,
                longitude: longitude,
                timestamp: timestamp
            )
            
            // Check if location is still valid
            if let self = self, self.isLocationValid(userLocation) {
                completion(userLocation)
            } else {
                print("DEBUG: Location for user \(userId) has expired")
                completion(nil)
            }
        }
    }
    
    func observeFriendLocations(userIds: [String], completion: @escaping ([String: UserLocation]) -> Void) {
        print("DEBUG: Starting to observe locations for \(userIds.count) friends")
        
        stopObservingFriendLocations()
        
        for userId in userIds {
            let userDocRef = firestore.collection("users").document(userId)
            let listener = userDocRef.addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("DEBUG: Error listening to user document: \(error.localizedDescription)")
                    return
                }
                
                print("DEBUG: Received update for user: \(userId)")
                
                self?.fetchAllFriendLocations(userIds: userIds) { locations in
                    let validLocations = self?.filterValidLocations(locations) ?? [:]
                    print("DEBUG: Updated friend locations: \(validLocations.count)")
                    completion(validLocations)
                    self?.friendLocationsSubject.send(validLocations)
                }
            }
            
            locationListeners[userId] = listener
        }
        
        fetchAllFriendLocations(userIds: userIds) { [weak self] locations in
            let validLocations = self?.filterValidLocations(locations) ?? [:]
            completion(validLocations)
            self?.friendLocationsSubject.send(validLocations)
        }
    }
    
    func stopObservingFriendLocations() {
        for (_, listener) in locationListeners {
            listener.remove()
        }
        locationListeners.removeAll()
        print("DEBUG: Stopped all friend location listeners")
    }
    
    func setUserOnlineStatus(userId: String, isOnline: Bool) {
        var updateData: [String: Any] = ["isOnline": isOnline]
        
        if !isOnline {
            updateData["lastSeen"] = FieldValue.serverTimestamp()
        }
        
        firestore.collection("users").document(userId).updateData(updateData) { [weak self] error in
            if let error = error {
                print("DEBUG: Error updating online status: \(error.localizedDescription)")
            } else {
                print("DEBUG: Successfully updated online status for user \(userId) to \(isOnline)")
                self?.onlineStatusSubjects[userId]?.send(isOnline)
            }
        }
    }
    
    func observeUserOnlineStatus(userId: String, completion: @escaping (Bool) -> Void) {
        if let handle = onlineStatusObservers[userId] {
            database.removeObserver(withHandle: handle)
            onlineStatusObservers.removeValue(forKey: userId)
        }
        
        if let listener = onlineStatusListeners[userId] {
            listener.remove()
            onlineStatusListeners.removeValue(forKey: userId)
        }
        
        let listener = firestore.collection("users").document(userId)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("DEBUG: Error observing user online status: \(error.localizedDescription)")
                    return
                }
                
                guard let document = snapshot, document.exists,
                      let data = document.data() else {
                    return
                }
                
                let isOnline = data["isOnline"] as? Bool ?? false
                completion(isOnline)
                
                if self?.onlineStatusSubjects[userId] == nil {
                    self?.onlineStatusSubjects[userId] = CurrentValueSubject<Bool, Never>(isOnline)
                } else {
                    self?.onlineStatusSubjects[userId]?.send(isOnline)
                }
            }
        
        onlineStatusListeners[userId] = listener
    }
    
    func stopObservingUserOnlineStatus(userId: String) {
        if let handle = onlineStatusObservers[userId] {
            database.removeObserver(withHandle: handle)
            onlineStatusObservers.removeValue(forKey: userId)
        }
        
        if let listener = onlineStatusListeners[userId] {
            listener.remove()
            onlineStatusListeners.removeValue(forKey: userId)
        }
        
        onlineStatusSubjects.removeValue(forKey: userId)
        print("DEBUG: Stopped observing online status for user \(userId)")
    }
    
    func fetchFriends(forUserId userId: String, completion: @escaping ([User]) -> Void) {
        print("DEBUG: Fetching friends for user: \(userId)")
        
        let userRef = firestore.collection("users").document(userId)
        
        userRef.getDocument { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("DEBUG: Error fetching user document: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let document = snapshot, document.exists,
                  let data = document.data(),
                  let friendIds = data["friendIds"] as? [String] else {
                print("DEBUG: No friends found for user \(userId)")
                completion([])
                return
            }
            
            print("DEBUG: Found \(friendIds.count) friends: \(friendIds)")
            
            if friendIds.isEmpty {
                completion([])
                return
            }
            
            self.fetchFriendsDetails(friendIds: friendIds, completion: completion)
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func observeUserLocation(userId: String) {
        let listener = firestore.collection("users").document(userId)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("DEBUG: Error observing user location: \(error.localizedDescription)")
                    return
                }
                
                guard let document = snapshot, document.exists,
                      let data = document.data(),
                      let locationData = data["lastLocation"] as? [String: Any] else {
                    self?.locationSubjects[userId]?.send(nil)
                    return
                }
                
                guard let latitude = locationData["latitude"] as? Double,
                      let longitude = locationData["longitude"] as? Double,
                      let timestamp = locationData["timestamp"] as? TimeInterval else {
                    self?.locationSubjects[userId]?.send(nil)
                    return
                }
                
                let location = UserLocation(
                    latitude: latitude,
                    longitude: longitude,
                    timestamp: timestamp
                )
                
                // Only send valid (non-expired) locations
                if let self = self, self.isLocationValid(location) {
                    self.locationSubjects[userId]?.send(location)
                } else {
                    self?.locationSubjects[userId]?.send(nil)
                }
            }
        
        locationListeners[userId] = listener
    }
    
    private func fetchAllFriendLocations(userIds: [String], completion: @escaping ([String: UserLocation]) -> Void) {
        var friendLocations = [String: UserLocation]()
        let group = DispatchGroup()
        
        print("DEBUG: Fetching locations for \(userIds.count) friends")
        
        for userId in userIds {
            group.enter()
            
            firestore.collection("users").document(userId).getDocument { snapshot, error in
                defer { group.leave() }
                
                if let error = error {
                    print("DEBUG: Error fetching user \(userId): \(error.localizedDescription)")
                    return
                }
                
                guard let document = snapshot, document.exists else {
                    print("DEBUG: Document for user \(userId) doesn't exist")
                    return
                }
                
                let data = document.data() ?? [:]
                guard let locationData = data["lastLocation"] as? [String: Any] else {
                    print("DEBUG: No location data for user \(userId)")
                    return
                }
                
                guard let latitude = locationData["latitude"] as? Double,
                      let longitude = locationData["longitude"] as? Double,
                      let timestamp = locationData["timestamp"] as? TimeInterval else {
                    print("DEBUG: Invalid location format for user \(userId)")
                    return
                }
                
                let location = UserLocation(
                    latitude: latitude,
                    longitude: longitude,
                    timestamp: timestamp
                )
                
                friendLocations[userId] = location
                print("DEBUG: Found location for user \(userId): \(latitude), \(longitude)")
            }
        }
        
        group.notify(queue: .main) {
            print("DEBUG: Completed fetching locations, found \(friendLocations.count) locations")
            completion(friendLocations)
        }
    }
    
    // MARK: - Remaining Protocol Methods
    
    func getPendingFriendRequestsCount(for userId: String, completion: @escaping (Int) -> Void) {
        firestore.collection("users").document(userId).getDocument { snapshot, error in
            if let error = error {
                print("DEBUG: Error fetching user document: \(error.localizedDescription)")
                completion(0)
                return
            }
            
            guard let document = snapshot, document.exists,
                  let data = document.data(),
                  let friendRequests = data["friendRequests"] as? [String] else {
                completion(0)
                return
            }
            
            completion(friendRequests.count)
        }
    }
    
    func removeFriend(currentUserId: String, friendId: String, completion: @escaping (Bool) -> Void) {
        let batch = firestore.batch()
        
        let currentUserRef = firestore.collection("users").document(currentUserId)
        batch.updateData(["friendIds": FieldValue.arrayRemove([friendId])], forDocument: currentUserRef)
        
        let friendRef = firestore.collection("users").document(friendId)
        batch.updateData(["friendIds": FieldValue.arrayRemove([currentUserId])], forDocument: friendRef)
        
        batch.commit { error in
            if let error = error {
                print("DEBUG: Error removing friend: \(error.localizedDescription)")
                completion(false)
            } else {
                print("DEBUG: Successfully removed friend relationship")
                completion(true)
            }
        }
    }
    
    // MARK: - Avatar Management Methods
    
    func updateUserAvatar(userId: String, avatarUrl: String, completion: @escaping (Bool) -> Void) {
        let userRef = firestore.collection("users").document(userId)
        
        userRef.updateData([
            "avatarUrl": avatarUrl,
            "profileImageUrl": avatarUrl,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("DEBUG: Error updating avatar: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            print("DEBUG: Avatar updated successfully for user \(userId)")
            
            NotificationCenter.default.post(
                name: NSNotification.Name("AvatarUpdated"),
                object: nil,
                userInfo: [
                    "userId": userId,
                    "avatarUrl": avatarUrl
                ]
            )
            
            completion(true)
        }
    }
    
    func getUserAvatar(userId: String, completion: @escaping (String?) -> Void) {
        let userRef = firestore.collection("users").document(userId)
        
        userRef.getDocument { snapshot, error in
            if let error = error {
                print("DEBUG: Error fetching user avatar: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let document = snapshot, document.exists,
                  let data = document.data() else {
                completion(nil)
                return
            }
            
            let avatarUrl = data["avatarUrl"] as? String ?? data["profileImageUrl"] as? String
            completion(avatarUrl)
        }
    }
    
    func observeUserAvatar(userId: String, completion: @escaping (String?) -> Void) -> ListenerRegistration {
        let userRef = firestore.collection("users").document(userId)
        
        return userRef.addSnapshotListener { snapshot, error in
            if let error = error {
                print("DEBUG: Error observing user avatar: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let document = snapshot, document.exists,
                  let data = document.data() else {
                completion(nil)
                return
            }
            
            let avatarUrl = data["avatarUrl"] as? String ?? data["profileImageUrl"] as? String
            completion(avatarUrl)
        }
    }
    
    func batchUpdateFriendsAvatars(friendIds: [String], completion: @escaping ([String: String]) -> Void) {
        guard !friendIds.isEmpty else {
            completion([:])
            return
        }
        
        var avatarUrls: [String: String] = [:]
        let group = DispatchGroup()
        
        for friendId in friendIds {
            group.enter()
            
            getUserAvatar(userId: friendId) { avatarUrl in
                if let avatarUrl = avatarUrl {
                    avatarUrls[friendId] = avatarUrl
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(avatarUrls)
        }
    }
    
    func cleanupExpiredLocations() {
        let currentTime = Date().timeIntervalSince1970
        
        firestore.collection("users").getDocuments { [weak self] snapshot, error in
            if let error = error {
                print("DEBUG: Error fetching users: \(error.localizedDescription)")
                return
            }
            
            for document in snapshot?.documents ?? [] {
                let data = document.data()
                if let locationData = data["lastLocation"] as? [String: Any] {
                    if let expiresAt = locationData["expiresAt"] as? TimeInterval {
                        if currentTime > expiresAt {
                            let userId = document.documentID
                            print("DEBUG: Removing expired location for user \(userId)")
                            
                            self?.firestore.collection("users").document(userId).updateData([
                                "lastLocation": FieldValue.delete()
                            ]) { error in
                                if let error = error {
                                    print("DEBUG: Error removing expired location: \(error.localizedDescription)")
                                } else {
                                    print("DEBUG: Successfully removed expired location for user \(userId)")
                                }
                            }
                        }
                    } else {
                        // If no expiresAt field, check timestamp directly
                        if let timestamp = locationData["timestamp"] as? TimeInterval {
                            if (currentTime - timestamp) > self?.locationExpirationTime ?? 0 {
                                let userId = document.documentID
                                print("DEBUG: Removing old location for user \(userId)")
                                
                                self?.firestore.collection("users").document(userId).updateData([
                                    "lastLocation": FieldValue.delete()
                                ]) { error in
                                    if let error = error {
                                        print("DEBUG: Error removing old location: \(error.localizedDescription)")
                                    } else {
                                        print("DEBUG: Successfully removed old location for user \(userId)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
