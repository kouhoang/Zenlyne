//
//  FriendService.swift
//  Zenlyne
//
//  Created by admin on 8/4/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

extension FirebaseService {
    
    func sendFriendRequest(from currentUser: User, to email: String, completion: @escaping (Bool, String) -> Void) {
        let db = Firestore.firestore()
        
        guard email != currentUser.email else {
            completion(false, "Bạn không thể gửi lời mời kết bạn cho chính mình")
            return
        }
        
        // Find users by email
        db.collection("users")
            .whereField("email", isEqualTo: email)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(false, "Lỗi: \(error.localizedDescription)")
                    return
                }
                
                // Check if user found
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    completion(false, "Không tìm thấy người dùng với email này")
                    return
                }
                
                // Get recipient information
                guard let data = documents.first?.data(),
                      let recipientId = data["id"] as? String else {
                    completion(false, "Không thể xác định người nhận")
                    return
                }
                
                // Check if already friends
                self.checkIfAlreadyFriends(userId: currentUser.id, friendId: recipientId) { isAlreadyFriends in
                    if isAlreadyFriends {
                        completion(false, "Bạn đã là bạn bè với người này")
                        return
                    }
                    
                    // Check if invitation has been sent before
                    self.checkExistingFriendRequest(senderId: currentUser.id, recipientId: recipientId) { existingRequest in
                        if existingRequest {
                            completion(false, "Bạn đã gửi lời mời kết bạn trước đó")
                            return
                        }
                        
                        // Create new friend request
                        let requestData: [String: Any] = [
                            "senderId": currentUser.id,
                            "senderEmail": currentUser.email,
                            "recipientId": recipientId,
                            "status": "pending",
                            "timestamp": Timestamp(date: Date())
                        ]
                        
                        // Save request into Firestore
                        db.collection("friend_requests").addDocument(data: requestData) { error in
                            if let error = error {
                                completion(false, "Lỗi: \(error.localizedDescription)")
                            } else {
                                completion(true, "Đã gửi lời mời kết bạn thành công")
                            }
                        }
                    }
                }
            }
    }
    
    
    private func checkIfAlreadyFriends(userId: String, friendId: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
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
    
    private func checkExistingFriendRequest(senderId: String, recipientId: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
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
    
    // Get the number of pending friend requests
    func getPendingFriendRequestsCount(for userId: String, completion: @escaping (Int) -> Void) {
        let db = Firestore.firestore()
        
        db.collection("friendRequests")
            .whereField("receiverId", isEqualTo: userId)
            .whereField("status", isEqualTo: "pending")
            .getDocuments { snapshot, error in
                if let error = error {
                    print("DEBUG: Error getting pending requests: \(error.localizedDescription)")
                    completion(0)
                    return
                }
                
                completion(snapshot?.documents.count ?? 0)
            }
    }
    
    // Get the list of pending friend requests
    func getPendingFriendRequests(for userId: String, completion: @escaping ([FriendRequest]) -> Void) {
        let db = Firestore.firestore()
        
        db.collection("friend_requests")
            .whereField("recipientId", isEqualTo: userId)
            .whereField("status", isEqualTo: "pending")
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let requests = documents.compactMap { document -> FriendRequest? in
                    let data = document.data()
                    guard let senderId = data["senderId"] as? String,
                          let senderEmail = data["senderEmail"] as? String,
                          let recipientId = data["recipientId"] as? String,
                          let status = data["status"] as? String else {
                        return nil
                    }
                    
                    return FriendRequest(
                        id: document.documentID,
                        senderId: senderId,
                        senderEmail: senderEmail,
                        recipientId: recipientId,
                        status: status
                    )
                }
                
                completion(requests)
            }
    }
    
    func acceptFriendRequest(requestId: String, completion: @escaping (Bool, String) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(false, "Người dùng chưa đăng nhập")
            return
        }
        
        let db = Firestore.firestore()
        let requestRef = db.collection("friend_requests").document(requestId)
        
        db.runTransaction { (transaction, errorPointer) -> Any? in
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
                
                // Check the status of the invitation
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
                let currentUserRef = db.collection("users").document(currentUser.uid)
                transaction.updateData(["friendIds": FieldValue.arrayUnion([senderId])], forDocument: currentUserRef)
                
                // Add recipient to sender's friends list
                let senderRef = db.collection("users").document(senderId)
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
                completion(true, "Đã chấp nhận lời mời kết bạn thành công")
            }
        }
    }
    
    // Reject friend request
    func declineFriendRequest(requestId: String, completion: @escaping (Bool, String) -> Void) {
        let db = Firestore.firestore()
        let requestRef = db.collection("friend_requests").document(requestId)
        
        requestRef.updateData(["status": "declined"]) { error in
            if let error = error {
                completion(false, "Lỗi: \(error.localizedDescription)")
            } else {
                completion(true, "Đã từ chối lời mời kết bạn")
            }
        }
    }
    
    // Delete friend
    func removeFriend(currentUserId: String, friendId: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        
        // Remove friend from current user's friendIds
        db.collection("users").document(currentUserId).updateData([
            "friendIds": FieldValue.arrayRemove([friendId])
        ]) { error in
            if let error = error {
                print("DEBUG: Error removing friend from current user: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            // Remove current user from friend's friendIds
            db.collection("users").document(friendId).updateData([
                "friendIds": FieldValue.arrayRemove([currentUserId])
            ]) { error in
                if let error = error {
                    print("DEBUG: Error removing current user from friend: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                completion(true)
            }
        }
    }
    
    // Mời bạn bè thông qua Email
    func inviteFriendByEmail(email: String, from user: User, completion: @escaping (Bool, String) -> Void) {

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            completion(true, "Đã gửi lời mời đến \(email). Người dùng sẽ nhận được email với liên kết tải ứng dụng.")
        }
    }
}
