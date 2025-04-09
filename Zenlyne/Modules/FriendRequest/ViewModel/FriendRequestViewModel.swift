//
//  FriendRequestViewModel.swift
//  Zenlyne
//
//  Created by admin on 25/3/25.
//


import Foundation
import Firebase
import FirebaseFirestore
import CoreLocation
import SwiftUI

struct FriendWithDistance: Identifiable {
    let id: String
    let name: String
    let email: String
    let profileImageUrl: String?
    let distance: Double?
}

class FriendRequestViewModel: ObservableObject {
    @Published var friendRequests: [FriendRequest] = []
    @Published var friends: [FriendWithDistance] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    
    private let db = Firestore.firestore()
    private let locationManager = CLLocationManager()
        
    func sendFriendRequest(toEmail email: String, completion: @escaping (Bool, String) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(false, "Người dùng chưa đăng nhập")
            return
        }
        
        // Check not sent to yourself
        if email == currentUser.email {
            completion(false, "Bạn không thể gửi lời mời kết bạn cho chính mình")
            return
        }
        
        isLoading = true
        
        // Find users by email
        db.collection("users")
            .whereField("email", isEqualTo: email)
            .getDocuments { [weak self] (snapshot, error) in
                self?.isLoading = false
                
                // Check query errors
                if let error = error {
                    completion(false, "Lỗi: \(error.localizedDescription)")
                    return
                }
                
                // Check if a user with this email is found
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    completion(false, "Không tìm thấy người dùng với email này")
                    return
                }
                
                let recipientId = documents[0].documentID
                
                // Check if this person is you
                guard recipientId != currentUser.uid else {
                    completion(false, "Bạn không thể gửi lời mời kết bạn cho chính mình")
                    return
                }
                
                // Check if you are friends
                self?.checkIfAlreadyFriends(userId: currentUser.uid, friendId: recipientId) { isAlreadyFriends in
                    if isAlreadyFriends {
                        completion(false, "Người này đã là bạn bè của bạn")
                        return
                    }
                    
                    // Check if invitation has been sent before
                    self?.checkExistingFriendRequest(senderId: currentUser.uid, recipientId: recipientId) { existingRequest in
                        if existingRequest {
                            completion(false, "Bạn đã gửi lời mời kết bạn cho người này trước đó")
                            return
                        }
                        
                        // Create new friend request
                        let friendRequest: [String: Any] = [
                            "senderId": currentUser.uid,
                            "senderEmail": currentUser.email ?? "",
                            "recipientId": recipientId,
                            "status": "pending",
                            "timestamp": FieldValue.serverTimestamp()
                        ]
                        
                        // Save friend request into Firestore
                        self?.db.collection("friend_requests").addDocument(data: friendRequest) { error in
                            if let error = error {
                                completion(false, "Lỗi gửi lời mời: \(error.localizedDescription)")
                            } else {
                                completion(true, "Đã gửi lời mời kết bạn thành công")
                            }
                        }
                    }
                }
            }
    }
    
    // Check if two users are already friends
    private func checkIfAlreadyFriends(userId: String, friendId: String, completion: @escaping (Bool) -> Void) {
        db.collection("users").document(userId).getDocument { snapshot, error in
            guard let document = snapshot, document.exists,
                  let data = document.data(),
                  let friendIds = data["friendIds"] as? [String] else {
                completion(false)
                return
            }
            
            completion(friendIds.contains(friendId))
        }
    }
    
    // Check if there are any pending friend requests
    private func checkExistingFriendRequest(senderId: String, recipientId: String, completion: @escaping (Bool) -> Void) {
        db.collection("friend_requests")
            .whereField("senderId", isEqualTo: senderId)
            .whereField("recipientId", isEqualTo: recipientId)
            .whereField("status", isEqualTo: "pending")
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents else {
                    completion(false)
                    return
                }
                
                completion(!documents.isEmpty)
            }
    }
    
    func fetchFriendRequests(completion: @escaping () -> Void = {}) {
        guard let currentUser = Auth.auth().currentUser else {
            completion()
            return
        }
        
        isLoading = true
        
        db.collection("friend_requests")
            .whereField("recipientId", isEqualTo: currentUser.uid)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] (snapshot, error) in
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Lỗi khi tải lời mời kết bạn: \(error.localizedDescription)"
                    completion()
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self.friendRequests = []
                    completion()
                    return
                }
                
                self.friendRequests = documents.compactMap { document in
                    let data = document.data()
                    return FriendRequest(
                        id: document.documentID,
                        senderId: data["senderId"] as? String ?? "",
                        senderEmail: data["senderEmail"] as? String ?? "",
                        recipientId: data["recipientId"] as? String ?? "",
                        status: data["status"] as? String ?? ""
                    )
                }
                
                completion()
            }
    }
    
    func acceptFriendRequest(requestId: String, completion: @escaping (Bool, String) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(false, "Người dùng chưa đăng nhập")
            return
        }
        
        isLoading = true
        let requestRef = db.collection("friend_requests").document(requestId)
        
        db.runTransaction { [weak self] (transaction, errorPointer) -> Any? in
            guard let self = self else { return nil }
            
            do {
                let requestDocument = try transaction.getDocument(requestRef)
                
                guard let data = requestDocument.data(),
                      let senderId = data["senderId"] as? String,
                      let status = data["status"] as? String else {
                    errorPointer?.pointee = NSError(
                        domain: "FriendRequestError",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy thông tin lời mời"]
                    )
                    return nil
                }
                
                // Check request status
                if status != "pending" {
                    errorPointer?.pointee = NSError(
                        domain: "FriendRequestError",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Lời mời này đã được xử lý"]
                    )
                    return nil
                }
                
                // Update invitation status to "accepted"
                transaction.updateData(["status": "accepted"], forDocument: requestRef)
                
                // Add sender to recipient's friends list
                let currentUserRef = self.db.collection("users").document(currentUser.uid)
                transaction.updateData(["friendIds": FieldValue.arrayUnion([senderId])], forDocument: currentUserRef)
                
                // Add recipient to sender's friends list
                let senderRef = self.db.collection("users").document(senderId)
                transaction.updateData(["friendIds": FieldValue.arrayUnion([currentUser.uid])], forDocument: senderRef)
                
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        } completion: { [weak self] (result, error) in
            self?.isLoading = false
            
            if let error = error {
                completion(false, "Lỗi: \(error.localizedDescription)")
            } else {
                completion(true, "Đã chấp nhận lời mời kết bạn thành công")
            }
        }
    }
    
    func declineFriendRequest(requestId: String, completion: @escaping (Bool, String) -> Void) {
        isLoading = true
        let requestRef = db.collection("friend_requests").document(requestId)
        
        requestRef.updateData(["status": "declined"]) { [weak self] error in
            self?.isLoading = false
            
            if let error = error {
                completion(false, "Lỗi: \(error.localizedDescription)")
            } else {
                completion(true, "Đã từ chối lời mời kết bạn")
            }
        }
    }
    
    func fetchFriends(currentUserLocation: CLLocationCoordinate2D?, completion: @escaping () -> Void = {}) {
        guard let currentUser = Auth.auth().currentUser else {
            completion()
            return
        }
        
        isLoading = true
        
        // Fetch current user's friends
        db.collection("users").document(currentUser.uid)
            .getDocument { [weak self] (document, error) in
                guard let self = self else { return }
                
                if let error = error {
                    self.isLoading = false
                    self.errorMessage = "Lỗi khi tải danh sách bạn bè: \(error.localizedDescription)"
                    completion()
                    return
                }
                
                guard let document = document, document.exists,
                      let friendIds = document.data()?["friendIds"] as? [String] else {
                    self.isLoading = false
                    self.friends = []
                    completion()
                    return
                }
                
                if friendIds.isEmpty {
                    self.isLoading = false
                    self.friends = []
                    completion()
                    return
                }
                
                // Fetch details for each friend
                let group = DispatchGroup()
                var fetchedFriends: [FriendWithDistance] = []
                
                friendIds.forEach { friendId in
                    group.enter()
                    self.fetchFriendDetails(friendId: friendId, currentUserLocation: currentUserLocation) { friend in
                        if let friend = friend {
                            fetchedFriends.append(friend)
                        }
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    self.isLoading = false
                    self.friends = fetchedFriends.sorted {
                        // Sort by distance, with nil (unknown distance) at the end
                        if let dist1 = $0.distance, let dist2 = $1.distance {
                            return dist1 < dist2
                        }
                        return $0.distance != nil
                    }
                    completion()
                }
            }
    }
    
    private func fetchFriendDetails(
        friendId: String,
        currentUserLocation: CLLocationCoordinate2D?,
        completion: @escaping (FriendWithDistance?) -> Void
    ) {
        // Fetch friend's user document
        db.collection("users").document(friendId).getDocument { [weak self] (document, error) in
            guard let self = self else {
                completion(nil)
                return
            }
            
            guard let document = document, document.exists,
                  let data = document.data(),
                  let email = data["email"] as? String,
                  let fullName = data["fullName"] as? String else {
                completion(nil)
                return
            }
            
            // Fetch friend's location
            var distance: Double? = nil
            if let currentUserLocation = currentUserLocation {
                // Fetch friend's location from Firebase
                self.db.collection("locations").document(friendId).getDocument { (locationDoc, error) in
                    if let locationData = locationDoc?.data(),
                       let lat = locationData["latitude"] as? Double,
                       let lon = locationData["longitude"] as? Double {
                        let friendLocation = CLLocation(latitude: lat, longitude: lon)
                        let currentLocation = CLLocation(
                            latitude: currentUserLocation.latitude,
                            longitude: currentUserLocation.longitude
                        )
                        
                        distance = currentLocation.distance(from: friendLocation) / 1000 // Convert to kilometers
                    }
                    
                    let friend = FriendWithDistance(
                        id: friendId,
                        name: fullName,
                        email: email,
                        profileImageUrl: data["profileImageUrl"] as? String,
                        distance: distance
                    )
                    
                    completion(friend)
                }
            } else {
                // If no current location, create friend without distance
                let friend = FriendWithDistance(
                    id: friendId,
                    name: fullName,
                    email: email,
                    profileImageUrl: data["profileImageUrl"] as? String,
                    distance: nil
                )
                
                completion(friend)
            }
        }
    }
    
    // Get the number of unread friend requests
    func getPendingFriendRequestsCount(completion: @escaping (Int) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(0)
            return
        }
        
        db.collection("friend_requests")
            .whereField("recipientId", isEqualTo: currentUser.uid)
            .whereField("status", isEqualTo: "pending")
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents else {
                    completion(0)
                    return
                }
                
                completion(documents.count)
            }
    }
    
    func fetchFriends(forUserId userId: String, completion: @escaping ([User]) -> Void) {
        print("DEBUG: Bắt đầu tải danh sách bạn bè cho userId: \(userId)")
        
        let userRef = db.collection("users").document(userId)
        
        userRef.getDocument { snapshot, error in
            if let error = error {
                print("DEBUG: Lỗi khi tải document của người dùng: \(error)")
                completion([])
                return
            }
            
            guard let document = snapshot, document.exists else {
                print("DEBUG: Document của người dùng không tồn tại")
                completion([])
                return
            }
            
            guard let data = document.data() else {
                print("DEBUG: Document của người dùng không có dữ liệu")
                completion([])
                return
            }
            
            let friendIds = data["friendIds"] as? [String] ?? []
            print("DEBUG: Tìm thấy \(friendIds.count) friendIds: \(friendIds)")
            
            if friendIds.isEmpty {
                print("DEBUG: Danh sách friendIds trống, trả về danh sách bạn bè trống")
                completion([])
                return
            }
        }
    }
}
