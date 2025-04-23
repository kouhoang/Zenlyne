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
import CoreLocation

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
        
        // First check if we need to update by getting the last location
        fetchUserLastLocation(userId: userId) { [weak self] lastLocation in
            guard let self = self else { return }
            
            // If no previous location or location has changed more than 10 meters, update
            if lastLocation == nil || self.calculateDistance(from: lastLocation!, to: location) > 10 {
                // Add timestamp to save the last time the location was updated
                var locationData = location.toDictionary()
                locationData["updatedAt"] = ServerValue.timestamp()
                
                // Set expiration time to 72 hours
                let expiresInSeconds: TimeInterval = 72 * 60 * 60
                locationData["expiresAt"] = Date().timeIntervalSince1970 + expiresInSeconds
                
                locationRef.setValue(locationData) { error, _ in
                    if let error = error {
                        print("DEBUG: Error saving location: \(error.localizedDescription)")
                    } else {
                        print("DEBUG: Location updated for user: \(userId)")
                    }
                }
                
                // Update last appearance time
                let lastSeenRef = database.child("users").child(userId).child("lastSeen")
                lastSeenRef.setValue(ServerValue.timestamp())
            } else {
                print("DEBUG: Location hasn't changed enough to update (< 10m)")
                // Just update the expiration time
                locationRef.child("expiresAt").setValue(Date().timeIntervalSince1970 + (72 * 60 * 60))
            }
        }
    }
    
    // Helper method to calculate distance between two locations
    private func calculateDistance(from location1: UserLocation, to location2: UserLocation) -> Double {
        let loc1 = CLLocation(latitude: location1.latitude, longitude: location1.longitude)
        let loc2 = CLLocation(latitude: location2.latitude, longitude: location2.longitude)
        return loc1.distance(from: loc2) // Distance in meters
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
            if let expiresAt = value["expiresAt"] as? TimeInterval {
                if Date().timeIntervalSince1970 > expiresAt {
                    // Position has expired
                    print("DEBUG: Location for user \(userId) has expired")
                    completion(nil)
                    return
                }
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
        
        print("DEBUG: Starting to observe locations for \(userIds.count) friends")
        
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
                if let expiresAt = value["expiresAt"] as? TimeInterval {
                    if Date().timeIntervalSince1970 > expiresAt {
                        // Location is expired, no need to update
                        print("DEBUG: Location for user \(userId) has expired")
                        return
                    }
                }
                
                print("DEBUG: Received location update for user: \(userId)")
                
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
                        // Check if location is not expired
                        if let expiresAt = value["expiresAt"] as? TimeInterval {
                            if Date().timeIntervalSince1970 <= expiresAt {
                                validLocations[userId] = location
                            }
                        } else {
                            // If no expiration, use default 72 hours
                            if location.timestamp + (72 * 60 * 60) > Date().timeIntervalSince1970 {
                                validLocations[userId] = location
                            }
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
        print("DEBUG: Stopped observing friend locations")
    }
    
    // MARK: - Online Status Management
    
    // Set online/offline status for users
    func setUserOnlineStatus(userId: String, isOnline: Bool) {
        let onlineRef = database.child("users").child(userId).child("isOnline")
        onlineRef.setValue(isOnline)
        
        // Update last seen timestamp when going offline
        if !isOnline {
            let lastSeenRef = database.child("users").child(userId).child("lastSeen")
            lastSeenRef.setValue(ServerValue.timestamp())
        }
        
        // Set offline status when connection is lost
        if isOnline {
            let onDisconnectRef = database.child("users").child(userId)
            onDisconnectRef.onDisconnectUpdateChildValues([
                "isOnline": false,
                "lastSeen": ServerValue.timestamp()
            ])
            
            print("DEBUG: Set user \(userId) online status to \(isOnline) with onDisconnect")
        } else {
            print("DEBUG: Set user \(userId) online status to \(isOnline)")
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
        print("DEBUG: Started observing online status for user \(userId)")
    }
    
    // Stop tracking user online status
    func stopObservingUserOnlineStatus(userId: String) {
        if let handle = onlineStatusObservers[userId] {
            database.removeObserver(withHandle: handle)
            onlineStatusObservers.removeValue(forKey: userId)
            print("DEBUG: Stopped observing online status for user \(userId)")
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
                
                // Update online status and location info
                if let self = self {
                    self.fetchOnlineStatus(forUsers: friends) { updatedFriends in
                        print("DEBUG: Đã cập nhật trạng thái online cho \(updatedFriends.count) bạn bè")
                        
                        // Also fetch last locations for all friends
                        self.fetchLastLocationsForFriends(updatedFriends) { friendsWithLocations in
                            print("DEBUG: Đã cập nhật vị trí cho \(friendsWithLocations.count) bạn bè")
                            completion(friendsWithLocations)
                        }
                    }
                } else {
                    completion(friends)
                }
            }
        }
    }
    
    
    // Fetch last known locations for a list of friends
    private func fetchLastLocationsForFriends(_ friends: [User], completion: @escaping ([User]) -> Void) {
        let group = DispatchGroup()
        var updatedFriends = friends
        
        for (index, friend) in friends.enumerated() {
            group.enter()
            
            fetchUserLastLocation(userId: friend.id) { location in
                if let location = location {
                    updatedFriends[index].lastLocation = location
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(updatedFriends)
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
                if let expiresAt = value["expiresAt"] as? TimeInterval {
                    if Date().timeIntervalSince1970 > expiresAt {
                        // Position has expired
                        return
                    }
                } else {
                    // No explicit expiration time, use default 72 hours
                    if timestamp + (72 * 60 * 60) < Date().timeIntervalSince1970 {
                        // Position has expired
                        return
                    }
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
