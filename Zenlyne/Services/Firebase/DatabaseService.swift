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
    
    // Save the user's current location to the Realtime Database
    func saveUserLocation(userId: String, location: UserLocation) {
        let locationRef = database.child("locations").child(userId)
        locationRef.setValue(location.toDictionary())
        
        // Update last seen time
        let lastSeenRef = database.child("users").child(userId).child("lastSeen")
        lastSeenRef.setValue(ServerValue.timestamp())
        
        // Update status online
        let onlineRef = database.child("users").child(userId).child("isOnline")
        onlineRef.setValue(true)
        
        // Set offline status when connection is lost
        let onDisconnectRef = database.child("users").child(userId)
        onDisconnectRef.onDisconnectUpdateChildValues(["isOnline": false])
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
            
            let userLocation = UserLocation(
                latitude: latitude,
                longitude: longitude,
                timestamp: timestamp
            )
            
            completion(userLocation)
        }
    }
    
    // Listen to your friends' locations in real time
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
                
                let location = UserLocation(
                    latitude: latitude,
                    longitude: longitude,
                    timestamp: timestamp
                )
                
                // Get all friends location to update UI
                self?.fetchAllFriendLocations(userIds: userIds, completion: completion)
            }
            
            locationObservers.append(handle)
        }
        
        // Get current location of all friends
        fetchAllFriendLocations(userIds: userIds, completion: completion)
    }
    
    // Stop listening to your friends location
    func stopObservingFriendLocations() {
        for handle in locationObservers {
            database.removeObserver(withHandle: handle)
        }
        locationObservers.removeAll()
    }
    
    // Get the user's friends list
    // Add this to FirebaseService.swift
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
            
            // Lấy danh sách ID bạn bè
            let friendIds = data["friendIds"] as? [String] ?? []
            print("DEBUG: Tìm thấy \(friendIds.count) friendIds: \(friendIds)")
            
            if friendIds.isEmpty {
                print("DEBUG: Danh sách friendIds trống, trả về danh sách bạn bè trống")
                completion([])
                return
            }
            
            // Lấy thông tin chi tiết của từng người bạn
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
                
                // Cập nhật trạng thái online (nếu cần)
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
    
    // Update your friends online status
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
    
    func enhancedFetchFriends(forUserId userId: String, completion: @escaping ([User]) -> Void) {
        print("DEBUG: Fetching friends for user ID: \(userId)")
        
        let usersRef = firestore.collection("users").document(userId)
        
        usersRef.getDocument { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("DEBUG: Error fetching user document: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let document = snapshot, document.exists else {
                print("DEBUG: User document does not exist")
                completion([])
                return
            }
            
            guard let data = document.data() else {
                print("DEBUG: User document has no data")
                completion([])
                return
            }
            
            let friendIds = data["friendIds"] as? [String] ?? []
            print("DEBUG: Found \(friendIds.count) friendIds: \(friendIds)")
            
            if friendIds.isEmpty {
                print("DEBUG: Friend IDs list is empty, returning empty friends list")
                completion([])
                return
            }
            
            // If there are many friends, we might need to use multiple queries
            // Firestore has a limitation where "in" query can only take up to 10 values
            let chunks = stride(from: 0, to: friendIds.count, by: 10).map {
                Array(friendIds[$0..<min($0 + 10, friendIds.count)])
            }
            
            var allFriends: [User] = []
            let group = DispatchGroup()
            
            for chunk in chunks {
                group.enter()
                
                self.firestore.collection("users")
                    .whereField("id", in: chunk)
                    .getDocuments { snapshot, error in
                        defer { group.leave() }
                        
                        if let error = error {
                            print("DEBUG: Error fetching friends chunk: \(error.localizedDescription)")
                            return
                        }
                        
                        guard let documents = snapshot?.documents else {
                            print("DEBUG: No friend documents found")
                            return
                        }
                        
                        print("DEBUG: Found \(documents.count) friend documents in chunk")
                        
                        let friends = documents.compactMap { document -> User? in
                            let data = document.data()
                            guard let id = data["id"] as? String,
                                  let fullName = data["fullName"] as? String,
                                  let email = data["email"] as? String else {
                                print("DEBUG: Missing required fields for friend with data: \(data)")
                                return nil
                            }
                            
                            var user = User(id: id, fullName: fullName, email: email)
                            user.profileImageUrl = data["profileImageUrl"] as? String
                            return user
                        }
                        
                        allFriends.append(contentsOf: friends)
                    }
            }
            
            group.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                print("DEBUG: Fetched a total of \(allFriends.count) friends")
                
                // Now fetch online status and lastSeen
                self.fetchOnlineStatus(forUsers: allFriends) { usersWithStatus in
                    completion(usersWithStatus)
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
