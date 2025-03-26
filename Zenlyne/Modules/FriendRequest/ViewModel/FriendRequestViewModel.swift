//
//  FriendRequestViewModel.swift
//  Zenlyne
//
//  Created by admin on 25/3/25.
//


import Foundation
import Firebase
import FirebaseFirestore

class FriendRequestViewModel: ObservableObject {
    @Published var friendRequests: [FriendRequest] = []
    private let db = Firestore.firestore()
    
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
}
