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
}

class FirebaseService: FirebaseServiceProtocol {
    private let database = Database.database().reference()
    private let firestore = Firestore.firestore()
    private var locationObservers = [DatabaseHandle]()
    
    // Lưu vị trí hiện tại của người dùng vào Realtime Database
    func saveUserLocation(userId: String, location: UserLocation) {
        let locationRef = database.child("locations").child(userId)
        locationRef.setValue(location.toDictionary())
        
        // Cập nhật thời gian last seen
        let lastSeenRef = database.child("users").child(userId).child("lastSeen")
        lastSeenRef.setValue(ServerValue.timestamp())
        
        // Cập nhật status online
        let onlineRef = database.child("users").child(userId).child("isOnline")
        onlineRef.setValue(true)
        
        // Thiết lập trạng thái offline khi mất kết nối
        let onDisconnectRef = database.child("users").child(userId)
        onDisconnectRef.onDisconnectUpdateChildValues(["isOnline": false])
    }
    
    // Lấy vị trí cuối cùng của người dùng
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
            
            let userLocation = UserLocation(
                latitude: latitude,
                longitude: longitude,
                timestamp: timestamp
            )
            
            completion(userLocation)
        }
    }
    
    // Lắng nghe vị trí của bạn bè theo thời gian thực
    func observeFriendLocations(userIds: [String], completion: @escaping ([String: UserLocation]) -> Void) {
        // Dừng tất cả các observer đang chạy
        stopObservingFriendLocations()
        
        // Tạo observer mới cho mỗi người bạn
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
                
                let location = UserLocation(
                    latitude: latitude,
                    longitude: longitude,
                    timestamp: timestamp
                )
                
                // Lấy tất cả vị trí của bạn bè để cập nhật UI
                self?.fetchAllFriendLocations(userIds: userIds, completion: completion)
            }
            
            locationObservers.append(handle)
        }
        
        // Lấy vị trí hiện tại của tất cả bạn bè
        fetchAllFriendLocations(userIds: userIds, completion: completion)
    }
    
    // Dừng lắng nghe vị trí của bạn bè
    func stopObservingFriendLocations() {
        for handle in locationObservers {
            database.removeObserver(withHandle: handle)
        }
        locationObservers.removeAll()
    }
    
    // Lấy danh sách bạn bè của người dùng
    func fetchFriends(forUserId userId: String, completion: @escaping ([User]) -> Void) {
        let userRef = firestore.collection("users").document(userId)
        
        userRef.getDocument { snapshot, error in
            guard let document = snapshot, document.exists,
                  let data = document.data(),
                  let friendIds = data["friendIds"] as? [String] else {
                completion([])
                return
            }
            
            if friendIds.isEmpty {
                completion([])
                return
            }
            
            self.firestore.collection("users")
                .whereField("id", in: friendIds)
                .getDocuments { snapshot, error in
                    guard let documents = snapshot?.documents else {
                        completion([])
                        return
                    }
                    
                    let friends = documents.compactMap { document -> User? in
                        let data = document.data()
                        guard let id = data["id"] as? String,
                              let fullName = data["fullName"] as? String,
                              let email = data["email"] as? String else {
                            return nil
                        }
                        
                        var user = User(id: id, fullName: fullName, email: email)
                        user.profileImageUrl = data["profileImageUrl"] as? String
                        return user
                    }
                    
                    // Lấy trạng thái online và vị trí của từng người bạn
                    self.fetchOnlineStatus(forUsers: friends) { usersWithStatus in
                        completion(usersWithStatus)
                    }
                }
        }
    }
    
    // Cập nhật trạng thái online của bạn bè
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
    
    // Phương thức nội bộ để lấy vị trí của tất cả bạn bè
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
