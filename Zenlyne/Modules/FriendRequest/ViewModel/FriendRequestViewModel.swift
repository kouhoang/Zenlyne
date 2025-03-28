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
    private let db = Firestore.firestore()
    private let locationManager = CLLocationManager()
    
    func sendFriendRequest(toEmail email: String, completion: @escaping (Bool, String) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(false, "Người dùng chưa đăng nhập")
            return
        }
        
        db.collection("users")
            .whereField("email", isEqualTo: email)
            .getDocuments { (snapshot, error) in
                if let error = error {
                    completion(false, "Lỗi: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    completion(false, "Không tìm thấy người dùng với email này")
                    return
                }
                
                let recipientId = documents[0].documentID
                
                guard recipientId != currentUser.uid else {
                    completion(false, "Bạn không thể gửi lời mời kết bạn cho chính mình")
                    return
                }
                
                let friendRequest = [
                    "senderId": currentUser.uid,
                    "senderEmail": currentUser.email ?? "",
                    "recipientId": recipientId,
                    "status": "pending",
                    "timestamp": FieldValue.serverTimestamp()
                ]
                
                self.db.collection("friend_requests").addDocument(data: friendRequest) { error in
                    if let error = error {
                        completion(false, "Lỗi gửi lời mời: \(error.localizedDescription)")
                    } else {
                        completion(true, "Đã gửi lời mời kết bạn")
                    }
                }
            }
    }
    
    func fetchFriendRequests(completion: @escaping () -> Void) {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        db.collection("friend_requests")
            .whereField("recipientId", isEqualTo: currentUser.uid)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { (snapshot, error) in
                guard let documents = snapshot?.documents else { return }
                
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
        
        let requestRef = db.collection("friend_requests").document(requestId)
        
        db.runTransaction { (transaction, errorPointer) -> Any? in
            do {
                let requestDocument = try transaction.getDocument(requestRef)
                
                guard let data = requestDocument.data(),
                      let senderId = data["senderId"] as? String else {
                    errorPointer?.pointee = NSError(
                        domain: "FriendRequestError",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy thông tin lời mời"]
                    )
                    return nil
                }
                
                transaction.updateData(["status": "accepted"], forDocument: requestRef)
                
                let currentUserRef = self.db.collection("users").document(currentUser.uid)
                let senderRef = self.db.collection("users").document(senderId)
                
                transaction.updateData(["friendIds": FieldValue.arrayUnion([senderId])], forDocument: currentUserRef)
                transaction.updateData(["friendIds": FieldValue.arrayUnion([currentUser.uid])], forDocument: senderRef)
                
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        } completion: { (result, error) in
            if let error = error {
                completion(false, "Lỗi: \(error.localizedDescription)")
            } else {
                completion(true, "Đã chấp nhận lời mời kết bạn")
            }
        }
    }
    
    func declineFriendRequest(requestId: String, completion: @escaping (Bool, String) -> Void) {
        let requestRef = db.collection("friend_requests").document(requestId)
        
        requestRef.updateData(["status": "declined"]) { error in
            if let error = error {
                completion(false, "Lỗi: \(error.localizedDescription)")
            } else {
                completion(true, "Đã từ chối lời mời kết bạn")
            }
        }
    }
    
    func fetchFriends(currentUserLocation: CLLocationCoordinate2D?, completion: @escaping () -> Void) {
            guard let currentUser = Auth.auth().currentUser else {
                completion()
                return
            }
            
            // Fetch current user's friends
            db.collection("users").document(currentUser.uid)
                .getDocument { [weak self] (document, error) in
                    guard let document = document, document.exists,
                          let friendIds = document.data()?["friendIds"] as? [String] else {
                        completion()
                        return
                    }
                    
                    // Fetch details for each friend
                    let group = DispatchGroup()
                    var fetchedFriends: [FriendWithDistance] = []
                    
                    friendIds.forEach { friendId in
                        group.enter()
                        self?.fetchFriendDetails(friendId: friendId, currentUserLocation: currentUserLocation) { friend in
                            if let friend = friend {
                                fetchedFriends.append(friend)
                            }
                            group.leave()
                        }
                    }
                    
                    group.notify(queue: .main) {
                        self?.friends = fetchedFriends.sorted {
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
                    // Fetch friend's location from Firestore
                    self?.db.collection("user_locations").document(friendId).getDocument { (locationDoc, error) in
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
}
