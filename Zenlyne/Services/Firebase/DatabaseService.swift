//
//  DatabaseService.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

// Handle querying and updating data on Firebase

import Foundation
import FirebaseDatabase
import FirebaseFirestore
import Combine

protocol FirebaseServiceProtocol {
    func saveUserLocation(userId: String, location: UserLocation)
    func fetchUserLastLocation(userId: String, completion: @escaping (UserLocation?) -> Void)
    func observeFriendLocations(userIds: [String], completion: @escaping ([String: UserLocation]) -> Void)
    func stopObservingFriendLocations()
    func fetchFriends(forUserId userId: String, completion: @escaping ([User]) -> Void)
    func setUserOnlineStatus(userId: String, isOnline: Bool)
    func observeUserOnlineStatus(userId: String, completion: @escaping (Bool) -> Void)
    func stopObservingUserOnlineStatus(userId: String)
}

class FirebaseService: FirebaseServiceProtocol {
    private let database = Database.database().reference()
    private let firestore = Firestore.firestore()
    private var locationObservers = [DatabaseHandle]()
    private var onlineStatusObservers: [String: DatabaseHandle] = [:]
    
    // MARK: - User Location Management
    
    // Save current user location to Realtime Database
    func saveUserLocation(userId: String, location: UserLocation) {
        let locationRef = database.child("locations").child(userId)
        
        // Add timestamp to save the last time the location was updated
        var locationData = location.toDictionary()
        locationData["updatedAt"] = ServerValue.timestamp()
        let expiresInSecond: TimeInterval = 72 * 60 * 60
        locationData["expiresAt"] = Date().timeIntervalSince1970 + expiresInSecond
        
        locationRef.setValue(locationData)
        
        // Update last appearance time
        let lastSeenRef = database.child("users").child(userId).child("lastSeen")
        lastSeenRef.setValue(ServerValue.timestamp())
    }
    
    // Get the user's last location
    func fetchUserLastLocation(userId: String, completion: @escaping (UserLocation?) -> Void) {
        let locationRef = database.child("locations").child(userId)
        
        locationRef.observeSingleEvent(of: .value) { snapshot in
            guard let value = snapshot.value as? [String: Any],
                  let latitude = value["latitude"] as? Double,
                  let longitude = value["longitude"] as? Double,
                  let timestamp = value["timestamp"] as? TimeInterval else {
                completion(nil)
                return
            }
            
            // Check if the position has expired
            if let expiresAt = value["expiresAt"] as? TimeInterval,
               Date(timeIntervalSince1970: expiresAt / 1000) < Date() {
                // Position has expired
                completion(nil)
                return
            }
            
            let userLocation = UserLocation(
                latitude: latitude,
                longitude: longitude,
                timestamp: timestamp
            )
            
            completion(userLocation)
        }
    }
    
    // Track your friends' locations in real time
    func observeFriendLocations(userIds: [String], completion: @escaping ([String: UserLocation]) -> Void) {
        // Stop all running observers
        stopObservingFriendLocations()
        
        // Create new observer for each friend
        for userId in userIds {
            let locationRef = database.child("locations").child(userId)
            let handle = locationRef.observe(.value) { [weak self] snapshot in
                guard snapshot.exists(),
                      let value = snapshot.value as? [String: Any],
                      let latitude = value["latitude"] as? Double,
                      let longitude = value["longitude"] as? Double,
                      let timestamp = value["timestamp"] as? TimeInterval else {
                    return
                }
                
                // Check if the position has expired
                if let expiresAt = value["expiresAt"] as? TimeInterval,
                   Date(timeIntervalSince1970: expiresAt / 1000) < Date() {
                    // Location is expired, no need to update
                    return
                }
                
                let location = UserLocation(
                    latitude: latitude,
                    longitude: longitude,
                    timestamp: timestamp
                )
                
                // Get location of all friends to update UI
                self?.fetchAllFriendLocations(userIds: userIds) { locations in
                    // Check and filter expired positions
                    var validLocations = [String: UserLocation]()
                    for (userId, location) in locations {
                        if location.timestamp + (72 * 60 * 60) > Date().timeIntervalSince1970 {
                            validLocations[userId] = location
                        }
                    }
                    completion(validLocations)
                }
            }
            
            locationObservers.append(handle)
        }
        
        // Get current location of all friends
        fetchAllFriendLocations(userIds: userIds, completion: completion)
    }
    
    // Stop tracking your friends location
    func stopObservingFriendLocations() {
        for handle in locationObservers {
            database.removeObserver(withHandle: handle)
        }
        locationObservers.removeAll()
    }
    
    // MARK: - Online Status Management
    
    // Set online/offline status for users
    func setUserOnlineStatus(userId: String, isOnline: Bool) {
        let onlineRef = database.child("users").child(userId).child("isOnline")
        onlineRef.setValue(isOnline)
        
        // Set offline status when connection is lost
        if isOnline {
            let onDisconnectRef = database.child("users").child(userId)
            onDisconnectRef.onDisconnectUpdateChildValues([
                "isOnline": false,
                "lastSeen": ServerValue.timestamp()
            ])
        }
    }
    
    // Track a user's online status
    func observeUserOnlineStatus(userId: String, completion: @escaping (Bool) -> Void) {
        // Remove old observer if any
        stopObservingUserOnlineStatus(userId: userId)
        
        let onlineRef = database.child("users").child(userId).child("isOnline")
        let handle = onlineRef.observe(.value) { snapshot in
            let isOnline = snapshot.value as? Bool ?? false
            completion(isOnline)
        }
        
        onlineStatusObservers[userId] = handle
    }
    
    // Stop tracking user online status
    func stopObservingUserOnlineStatus(userId: String) {
        if let handle = onlineStatusObservers[userId] {
            database.removeObserver(withHandle: handle)
            onlineStatusObservers.removeValue(forKey: userId)
        }
    }
    
    // MARK: - Friend Management
    
    // Get user's friends list
    func fetchFriends(forUserId userId: String, completion: @escaping ([User]) -> Void) {
        print("DEBUG: Đang tải danh sách bạn bè cho userId: \(userId)")
        
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(userId)
        
        userRef.getDocument { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("DEBUG: Lỗi khi tải tài liệu người dùng: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let document = snapshot, document.exists else {
                print("DEBUG: Tài liệu người dùng không tồn tại")
                completion([])
                return
            }
            
            guard let data = document.data() else {
                print("DEBUG: Tài liệu người dùng không có dữ liệu")
                completion([])
                return
            }
            
            // Get friend ID's list
            let friendIds = data["friendIds"] as? [String] ?? []
            print("DEBUG: Tìm thấy \(friendIds.count) friendIds: \(friendIds)")
            
            if friendIds.isEmpty {
                print("DEBUG: Danh sách friendIds trống, trả về danh sách bạn bè trống")
                completion([])
                return
            }
            
            // Get detailed information of each friend
            var friends: [User] = []
            let group = DispatchGroup()
            
            for friendId in friendIds {
                group.enter()
                
                db.collection("users").document(friendId).getDocument { document, error in
                    defer { group.leave() }
                    
                    if let error = error {
                        print("DEBUG: Lỗi khi tải thông tin bạn bè \(friendId): \(error.localizedDescription)")
                        return
                    }
                    
                    guard let document = document, document.exists, let data = document.data() else {
                        print("DEBUG: Không tìm thấy thông tin bạn bè \(friendId)")
                        return
                    }
                    
                    // Tạo đối tượng User từ dữ liệu
                    if let email = data["email"] as? String,
                       let fullName = data["fullName"] as? String {
                        var user = User(id: friendId, fullName: fullName, email: email)
                        user.profileImageUrl = data["profileImageUrl"] as? String
                        
                        print("DEBUG: Đã tải thành công thông tin bạn bè: \(fullName)")
                        friends.append(user)
                    } else {
                        print("DEBUG: Thiếu thông tin cần thiết cho bạn bè \(friendId)")
                    }
                }
            }
            
            group.notify(queue: .main) { [weak self] in
                print("DEBUG: Đã tải xong danh sách \(friends.count) bạn bè")
                
                // Update online status
                if let self = self {
                    self.fetchOnlineStatus(forUsers: friends) { updatedFriends in
                        print("DEBUG: Đã cập nhật trạng thái online cho \(updatedFriends.count) bạn bè")
                        completion(updatedFriends)
                    }
                } else {
                    completion(friends)
                }
            }
        }
    }
    
    // Update friends' online state
    private func fetchOnlineStatus(forUsers users: [User], completion: @escaping ([User]) -> Void) {
        let group = DispatchGroup()
        var updatedUsers = users
        
        for (index, user) in users.enumerated() {
            group.enter()
            
            let statusRef = database.child("users").child(user.id)
            statusRef.observeSingleEvent(of: .value) { snapshot in
                defer { group.leave() }
                
                guard let value = snapshot.value as? [String: Any] else { return }
                
                if let isOnline = value["isOnline"] as? Bool {
                    updatedUsers[index].isOnline = isOnline
                }
                
                if let lastSeenTimestamp = value["lastSeen"] as? Double {
                    updatedUsers[index].lastSeen = Date(timeIntervalSince1970: lastSeenTimestamp / 1000)
                }
            }
        }
        
        group.notify(queue: .main) {
            completion(updatedUsers)
        }
    }
    
    // MARK: - Internal Helper Methods
    
    // Internal method to get location of all friends
    private func fetchAllFriendLocations(userIds: [String], completion: @escaping ([String: UserLocation]) -> Void) {
        var friendLocations = [String: UserLocation]()
        let group = DispatchGroup()
        
        for userId in userIds {
            group.enter()
            let locationRef = database.child("locations").child(userId)
            
            locationRef.observeSingleEvent(of: .value) { snapshot in
                defer { group.leave() }
                
                guard let value = snapshot.value as? [String: Any],
                      let latitude = value["latitude"] as? Double,
                      let longitude = value["longitude"] as? Double,
                      let timestamp = value["timestamp"] as? TimeInterval else {
                    return
                }
                
                // Check if the position has expired
                if let expiresAt = value["expiresAt"] as? TimeInterval,
                   Date(timeIntervalSince1970: expiresAt / 1000) < Date() {
                    //Check if the position has expired
                    return
                }
                
                let location = UserLocation(
                    latitude: latitude,
                    longitude: longitude,
                    timestamp: timestamp
                )
                
                friendLocations[userId] = location
            }
        }
        
        group.notify(queue: .main) {
            completion(friendLocations)
        }
    }
}

// Helper extension
extension UserLocation {
    init?(latitude: Double, longitude: Double, timestamp: TimeInterval) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }
}

