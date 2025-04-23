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
    private var locationObservers: [Any] = []
    private var onlineStatusObservers: [String: DatabaseHandle] = [:]
    private var locationListeners: [String: ListenerRegistration] = [:]
    
    // MARK: - User Location Management
    
    // Save current user location to Realtime Database
    func saveUserLocation(userId: String, location: UserLocation) {
        print("DEBUG: Attempting to save location for user \(userId): \(location.latitude), \(location.longitude)")
        
        let db = Firestore.firestore()
        let locationData: [String: Any] = [
            "latitude": location.latitude,
            "longitude": location.longitude,
            "timestamp": location.timestamp,
            "updatedAt": FieldValue.serverTimestamp(),
            "expiresAt": Date().timeIntervalSince1970 + (72 * 60 * 60) // 72 hours
        ]
        
        db.collection("users").document(userId).updateData([
            "lastLocation": locationData,
            "isOnline": true,
            "lastSeen": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("DEBUG: Error saving location to Firestore: \(error.localizedDescription)")
            } else {
                print("DEBUG: Successfully saved location for user \(userId)")
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
        let db = Firestore.firestore()
        
        db.collection("users").document(userId).getDocument { snapshot, error in
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
            
            // Check expiration time
            if let expiresAt = locationData["expiresAt"] as? TimeInterval {
                if Date().timeIntervalSince1970 > expiresAt {
                    print("DEBUG: Location for user \(userId) has expired")
                    completion(nil)
                    return
                }
            }
            
            // Get location information
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
            
            completion(userLocation)
        }
    }
    
    // Sửa phương thức observeFriendLocations
    func observeFriendLocations(userIds: [String], completion: @escaping ([String: UserLocation]) -> Void) {
        print("DEBUG: Starting to observe locations for \(userIds.count) friends")
        
        // Dừng tất cả listener hiện tại
        stopObservingFriendLocations()
        
        let db = Firestore.firestore()
        
        for userId in userIds {
            let userDocRef = db.collection("users").document(userId)
            let listener = userDocRef.addSnapshotListener { snapshot, error in
                if let error = error {
                    print("DEBUG: Error listening to user document: \(error.localizedDescription)")
                    return
                }
                
                print("DEBUG: Received update for user: \(userId)")
                
                // Lấy tất cả vị trí của bạn bè
                self.fetchAllFriendLocations(userIds: userIds) { locations in
                    print("DEBUG: Updated friend locations: \(locations.count)")
                    completion(locations)
                }
            }
            
            locationListeners[userId] = listener
        }
        
        // Lấy vị trí ban đầu
        fetchAllFriendLocations(userIds: userIds, completion: completion)
    }

    // Cập nhật stopObservingFriendLocations
    func stopObservingFriendLocations() {
        for (_, listener) in locationListeners {
            listener.remove()
        }
        locationListeners.removeAll()
        print("DEBUG: Stopped all friend location listeners")
    }
    
    // MARK: - Online Status Management
    
    // Set online/offline status for users
    func setUserOnlineStatus(userId: String, isOnline: Bool) {
        let db = Firestore.firestore()
        
        var updateData: [String: Any] = ["isOnline": isOnline]
        
        // Update lastSeen when user is offline
        if !isOnline {
            updateData["lastSeen"] = FieldValue.serverTimestamp()
        }
        
        db.collection("users").document(userId).updateData(updateData) { error in
            if let error = error {
                print("DEBUG: Error updating online status: \(error.localizedDescription)")
            } else {
                print("DEBUG: Successfully updated online status for user \(userId) to \(isOnline)")
            }
        }
    }
    
    // Track a user's online status
    func observeUserOnlineStatus(userId: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        
        db.collection("users").document(userId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("DEBUG: Error listening to user document: \(error.localizedDescription)")
                    return
                }
                
                guard let document = snapshot, document.exists,
                      let data = document.data() else {
                    return
                }
                
                let isOnline = data["isOnline"] as? Bool ?? false
                completion(isOnline)
            }
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
        print("DEBUG: Fetching friends for user: \(userId)")
        
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(userId)
        
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
            
            // Lấy thông tin chi tiết cho mỗi bạn bè
            var friends: [User] = []
            let group = DispatchGroup()
            
            for friendId in friendIds {
                group.enter()
                
                db.collection("users").document(friendId).getDocument { document, error in
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
                        
                        // Lấy các thông tin bổ sung
                        friend.profileImageUrl = data["profileImageUrl"] as? String
                        friend.isOnline = data["isOnline"] as? Bool ?? false
                        
                        // Lấy thông tin lastSeen
                        if let lastSeenTimestamp = data["lastSeen"] as? Timestamp {
                            friend.lastSeen = lastSeenTimestamp.dateValue()
                        }
                        
                        // Lấy thông tin vị trí
                        if let locationData = data["lastLocation"] as? [String: Any],
                           let latitude = locationData["latitude"] as? Double,
                           let longitude = locationData["longitude"] as? Double,
                           let timestamp = locationData["timestamp"] as? TimeInterval {
                            
                            friend.lastLocation = UserLocation(
                                latitude: latitude,
                                longitude: longitude,
                                timestamp: timestamp
                            )
                            
                            print("DEBUG: Friend \(fullName) has location: \(latitude), \(longitude)")
                        } else {
                            print("DEBUG: Friend \(fullName) has no location data")
                        }
                        
                        friends.append(friend)
                        print("DEBUG: Added friend: \(fullName) (ID: \(friendId))")
                    }
                }
            }
            
//            group.notify(queue: .main) {
//                print("DEBUG: Finished loading \(friends.count) friends")
//                completion(friends)
//                
//                // Bắt đầu quan sát vị trí và trạng thái online
//                if !friends.isEmpty {
//                    let friendIds = friends.map { $0.id }
//                    self.startObservingFriendLocations(userIds: friendIds) { locations in
//                        for (friendId, location) in locations {
//                            print("DEBUG: Friend \(friendId) location updated: \(location.latitude), \(location.longitude)")
//                        }
//                    }
//                }
//            }
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
        let db = Firestore.firestore()
        var friendLocations = [String: UserLocation]()
        let group = DispatchGroup()
        let currentTime = Date().timeIntervalSince1970
        
        print("DEBUG: Fetching locations for \(userIds.count) friends")
        
        for userId in userIds {
            group.enter()
            
            db.collection("users").document(userId).getDocument { snapshot, error in
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
                
                // Kiểm tra thời gian hết hạn
                if let expiresAt = locationData["expiresAt"] as? TimeInterval {
                    if currentTime > expiresAt {
                        print("DEBUG: Location for user \(userId) has expired")
                        return
                    }
                }
                
                // Kiểm tra dữ liệu vị trí
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
                print("DEBUG: Found valid location for user \(userId): \(latitude), \(longitude)")
            }
        }
        
        group.notify(queue: .main) {
            print("DEBUG: Completed fetching locations, found \(friendLocations.count) valid locations")
            completion(friendLocations)
        }
    }
    
    func debugDatabaseLocations(forUsers userIds: [String]) {
        for userId in userIds {
            let locationRef = database.child("locations").child(userId)
            locationRef.observeSingleEvent(of: .value) { snapshot in
                print("DEBUG: Database location for \(userId):")
                if snapshot.exists() {
                    if let value = snapshot.value as? [String: Any] {
                        print("DEBUG:   Data: \(value)")
                        if let expiresAt = value["expiresAt"] as? TimeInterval {
                            let expiryDate = Date(timeIntervalSince1970: expiresAt)
                            let formatter = DateFormatter()
                            formatter.dateStyle = .medium
                            formatter.timeStyle = .medium
                            print("DEBUG:   Expires: \(formatter.string(from: expiryDate))")
                        }
                    } else {
                        print("DEBUG:   Invalid data format")
                    }
                } else {
                    print("DEBUG:   No location data found")
                }
            }
        }
    }
    
    func cleanupExpiredLocations() {
        let db = Firestore.firestore()
        let currentTime = Date().timeIntervalSince1970
        
        // Get all suer
        db.collection("users").getDocuments { snapshot, error in
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
                            
                            db.collection("users").document(userId).updateData([
                                "lastLocation": FieldValue.delete()
                            ]) { error in
                                if let error = error {
                                    print("DEBUG: Error removing expired location: \(error.localizedDescription)")
                                } else {
                                    print("DEBUG: Successfully removed expired location for user \(userId)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    func testSaveLocationToFirestore(userId: String) {
        let db = Firestore.firestore()
        let testLocation: [String: Any] = [
            "latitude": 10.762622,
            "longitude": 105.660172,
            "timestamp": Date().timeIntervalSince1970,
            "updatedAt": FieldValue.serverTimestamp(),
            "expiresAt": Date().timeIntervalSince1970 + (72 * 60 * 60)
        ]
        
        db.collection("users").document(userId).updateData([
            "lastLocation": testLocation
        ]) { error in
            if let error = error {
                print("DEBUG: Test location save FAILED: \(error.localizedDescription)")
                
                db.collection("users").document(userId).setData([
                    "lastLocation": testLocation,
                    "isOnline": true,
                    "lastSeen": FieldValue.serverTimestamp()
                ]) { error in
                    if let error = error {
                        print("DEBUG: Test location set FAILED: \(error.localizedDescription)")
                    } else {
                        print("DEBUG: Test location set SUCCESSFUL")
                    }
                }
            } else {
                print("DEBUG: Test location save SUCCESSFUL")
            }
        }
    }
    
    func createMockLocationsForTesting(currentUserId: String) {
        let db = Firestore.firestore()
        
        // Lấy danh sách bạn bè
        db.collection("users").document(currentUserId).getDocument { snapshot, error in
            guard let document = snapshot, document.exists,
                  let data = document.data(),
                  let friendIds = data["friendIds"] as? [String] else {
                print("DEBUG TEST: No friends found for mock data")
                return
            }
            
            print("DEBUG TEST: Creating mock locations for \(friendIds.count) friends")
            
            // Vị trí hiện tại của người dùng
            var userLocation: CLLocationCoordinate2D? = nil
            if let locationData = data["lastLocation"] as? [String: Any],
               let latitude = locationData["latitude"] as? Double,
               let longitude = locationData["longitude"] as? Double {
                userLocation = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                print("DEBUG TEST: User location: \(latitude), \(longitude)")
            } else {
                // Vị trí mặc định (Hồ Chí Minh)
                userLocation = CLLocationCoordinate2D(latitude: 10.762622, longitude: 106.660172)
                print("DEBUG TEST: Using default user location")
            }
            
            // Tạo vị trí giả cho bạn bè xung quanh vị trí người dùng
            for (index, friendId) in friendIds.enumerated() {
                guard let userLoc = userLocation else { continue }
                
                // Tạo vị trí ngẫu nhiên quanh người dùng
                let offsetLat = Double(index + 1) * 0.001 * (index % 2 == 0 ? 1 : -1)
                let offsetLon = Double(index + 1) * 0.001 * (index % 3 == 0 ? 1 : -1)
                
                let friendLat = userLoc.latitude + offsetLat
                let friendLon = userLoc.longitude + offsetLon
                
                let mockLocationData: [String: Any] = [
                    "latitude": friendLat,
                    "longitude": friendLon,
                    "timestamp": Date().timeIntervalSince1970,
                    "expiresAt": Date().timeIntervalSince1970 + (72 * 60 * 60)
                ]
                
                // Cập nhật vị trí giả cho bạn bè
                db.collection("users").document(friendId).updateData([
                    "lastLocation": mockLocationData,
                    "isOnline": index % 2 == 0  // Một nửa online, một nửa offline
                ]) { error in
                    if let error = error {
                        print("DEBUG TEST: Error creating mock location for friend \(friendId): \(error.localizedDescription)")
                    } else {
                        print("DEBUG TEST: Created mock location for friend \(friendId): \(friendLat), \(friendLon)")
                    }
                }
            }
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
