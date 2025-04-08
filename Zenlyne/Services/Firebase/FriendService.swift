//
//  FriendService.swift
//  Zenlyne
//
//  Created by admin on 8/4/25.
//

import Foundation
import FirebaseFirestore

// Mở rộng FirebaseService để thêm các chức năng liên quan đến bạn bè
extension FirebaseService {
    
    // Gửi lời mời kết bạn
    func sendFriendRequest(from currentUser: User, to email: String, completion: @escaping (Bool, String) -> Void) {
        let db = Firestore.firestore()
        
        // Tìm người dùng theo email
        db.collection("users")
            .whereField("email", isEqualTo: email)
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    completion(false, "Không tìm thấy người dùng với email này")
                    return
                }
                
                // Lấy thông tin của người nhận
                guard let data = documents.first?.data(),
                      let recipientId = data["id"] as? String else {
                    completion(false, "Không thể xác định người nhận")
                    return
                }
                
                // Kiểm tra nếu đã là bạn bè
                if let friendIds = data["friendIds"] as? [String], friendIds.contains(currentUser.id) {
                    completion(false, "Bạn đã là bạn bè với người này")
                    return
                }
                
                // Kiểm tra nếu đã gửi lời mời trước đó
                db.collection("friendRequests")
                    .whereField("senderId", isEqualTo: currentUser.id)
                    .whereField("recipientId", isEqualTo: recipientId)
                    .whereField("status", isEqualTo: "pending")
                    .getDocuments { snapshot, error in
                        if let documents = snapshot?.documents, !documents.isEmpty {
                            completion(false, "Bạn đã gửi lời mời kết bạn trước đó")
                            return
                        }
                        
                        // Tạo lời mời kết bạn mới
                        let requestData: [String: Any] = [
                            "senderId": currentUser.id,
                            "senderEmail": currentUser.email,
                            "recipientId": recipientId,
                            "status": "pending",
                            "timestamp": Timestamp(date: Date())
                        ]
                        
                        // Lưu lời mời vào Firestore
                        db.collection("friendRequests").addDocument(data: requestData) { error in
                            if let error = error {
                                completion(false, "Lỗi: \(error.localizedDescription)")
                            } else {
                                completion(true, "Đã gửi lời mời kết bạn thành công")
                            }
                        }
                    }
            }
    }
    
    // Lấy số lượng lời mời kết bạn đang chờ
    func getPendingFriendRequestsCount(for userId: String, completion: @escaping (Int) -> Void) {
        let db = Firestore.firestore()
        
        db.collection("friendRequests")
            .whereField("recipientId", isEqualTo: userId)
            .whereField("status", isEqualTo: "pending")
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents else {
                    completion(0)
                    return
                }
                
                completion(documents.count)
            }
    }
    
    // Xóa bạn bè
    func removeFriend(currentUserId: String, friendId: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        let currentUserRef = db.collection("users").document(currentUserId)
        let friendRef = db.collection("users").document(friendId)
        
        db.runTransaction { (transaction, errorPointer) -> Any? in
            // Xóa bạn bè từ danh sách của người dùng hiện tại
            transaction.updateData([
                "friendIds": FieldValue.arrayRemove([friendId])
            ], forDocument: currentUserRef)
            
            // Xóa người dùng hiện tại từ danh sách bạn bè của bạn
            transaction.updateData([
                "friendIds": FieldValue.arrayRemove([currentUserId])
            ], forDocument: friendRef)
            
            return nil
        } completion: { (_, error) in
            if let error = error {
                print("Lỗi khi xóa bạn bè: \(error.localizedDescription)")
                completion(false)
            } else {
                completion(true)
            }
        }
    }
    
    // Mời bạn bè thông qua SMS hoặc Email
    func inviteFriendByEmail(email: String, from user: User, completion: @escaping (Bool, String) -> Void) {
        // Giả lập việc gửi email mời bạn bè
        // Trong ứng dụng thực tế, bạn sẽ cần sử dụng API để gửi email
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            completion(true, "Đã gửi lời mời đến \(email)")
        }
    }
}
