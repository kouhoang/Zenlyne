//
//  FriendService.swift
//  Zenlyne
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

protocol FriendServiceProtocol {
    func sendFriendRequest(toEmail email: String) -> AnyPublisher<String, Error>
    func fetchFriendRequests() -> AnyPublisher<[FriendRequest], Error>
    func acceptFriendRequest(requestId: String) -> AnyPublisher<String, Error>
    func declineFriendRequest(requestId: String) -> AnyPublisher<String, Error>
    func fetchFriends(forUserId userId: String) -> AnyPublisher<[User], Error>
    func removeFriend(currentUserId: String, friendId: String) -> AnyPublisher<Void, Error>
    func getPendingRequestsCount() -> AnyPublisher<Int, Error>
}

class FriendService: FriendServiceProtocol {
    private let db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Send Friend Request
    func sendFriendRequest(toEmail email: String) -> AnyPublisher<String, Error> {
        Future<String, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(FriendError.serviceUnavailable))
                return
            }
            
            guard let currentUser = Auth.auth().currentUser else {
                promise(.failure(FriendError.userNotAuthenticated))
                return
            }
            
            // Validate email
            guard email != currentUser.email else {
                promise(.failure(FriendError.cannotAddSelf))
                return
            }
            
            // Find user by email
            self.db.collection("users")
                .whereField("email", isEqualTo: email)
                .getDocuments { snapshot, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }
                    
                    guard let documents = snapshot?.documents, !documents.isEmpty else {
                        promise(.failure(FriendError.userNotFound))
                        return
                    }
                    
                    let recipientId = documents[0].documentID
                    
                    // Check if already friends
                    self.checkIfAlreadyFriends(userId: currentUser.uid, friendId: recipientId) { isAlreadyFriends in
                        if isAlreadyFriends {
                            promise(.failure(FriendError.alreadyFriends))
                            return
                        }
                        
                        // Check existing request
                        self.checkExistingFriendRequest(senderId: currentUser.uid, recipientId: recipientId) { existingRequest in
                            if existingRequest {
                                promise(.failure(FriendError.requestAlreadySent))
                                return
                            }
                            
                            // Create friend request
                            let friendRequest: [String: Any] = [
                                "senderId": currentUser.uid,
                                "senderEmail": currentUser.email ?? "",
                                "recipientId": recipientId,
                                "status": "pending",
                                "timestamp": FieldValue.serverTimestamp()
                            ]
                            
                            self.db.collection("friend_requests").addDocument(data: friendRequest) { error in
                                if let error = error {
                                    promise(.failure(error))
                                } else {
                                    promise(.success("Đã gửi lời mời kết bạn thành công"))
                                }
                            }
                        }
                    }
                }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Fetch Friend Requests
    func fetchFriendRequests() -> AnyPublisher<[FriendRequest], Error> {
        Future<[FriendRequest], Error> { promise in
            guard let currentUser = Auth.auth().currentUser else {
                promise(.failure(FriendError.userNotAuthenticated))
                return
            }
            
            self.db.collection("friend_requests")
                .whereField("recipientId", isEqualTo: currentUser.uid)
                .whereField("status", isEqualTo: "pending")
                .getDocuments { snapshot, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        promise(.success([]))
                        return
                    }
                    
                    let requests = documents.compactMap { document -> FriendRequest? in
                        let data = document.data()
                        return FriendRequest(
                            id: document.documentID,
                            senderId: data["senderId"] as? String ?? "",
                            senderEmail: data["senderEmail"] as? String ?? "",
                            recipientId: data["recipientId"] as? String ?? "",
                            status: data["status"] as? String ?? ""
                        )
                    }
                    
                    promise(.success(requests))
                }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Accept Friend Request
    func acceptFriendRequest(requestId: String) -> AnyPublisher<String, Error> {
        Future<String, Error> { promise in
            guard let currentUser = Auth.auth().currentUser else {
                promise(.failure(FriendError.userNotAuthenticated))
                return
            }
            
            let requestRef = self.db.collection("friend_requests").document(requestId)
            
            self.db.runTransaction({ (transaction, errorPointer) -> Any? in
                do {
                    let requestDocument = try transaction.getDocument(requestRef)
                    
                    guard let data = requestDocument.data(),
                          let senderId = data["senderId"] as? String,
                          let recipientId = data["recipientId"] as? String,
                          let status = data["status"] as? String else {
                        let error = NSError(
                            domain: "FriendRequestError",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy lời mời kết bạn"]
                        )
                        errorPointer?.pointee = error
                        return nil
                    }
                    
                    guard recipientId == currentUser.uid else {
                        let error = NSError(
                            domain: "FriendRequestError",
                            code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "Bạn không có quyền chấp nhận lời mời này"]
                        )
                        errorPointer?.pointee = error
                        return nil
                    }
                    
                    guard status == "pending" else {
                        let error = NSError(
                            domain: "FriendRequestError",
                            code: -3,
                            userInfo: [NSLocalizedDescriptionKey: "Lời mời này đã được xử lý"]
                        )
                        errorPointer?.pointee = error
                        return nil
                    }
                    
                    // Update request status
                    transaction.updateData(["status": "accepted"], forDocument: requestRef)
                    
                    // Add to friends lists
                    let currentUserRef = self.db.collection("users").document(currentUser.uid)
                    transaction.updateData([
                        "friendIds": FieldValue.arrayUnion([senderId])
                    ], forDocument: currentUserRef)
                    
                    let senderRef = self.db.collection("users").document(senderId)
                    transaction.updateData([
                        "friendIds": FieldValue.arrayUnion([currentUser.uid])
                    ], forDocument: senderRef)
                    
                    return nil
                    
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }) { (result, error) in
                if let error = error {
                    promise(.failure(error))
                } else {
                    promise(.success("Đã chấp nhận lời mời kết bạn thành công"))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Decline Friend Request
    func declineFriendRequest(requestId: String) -> AnyPublisher<String, Error> {
        Future<String, Error> { promise in
            guard let currentUser = Auth.auth().currentUser else {
                promise(.failure(FriendError.userNotAuthenticated))
                return
            }
            
            let requestRef = self.db.collection("friend_requests").document(requestId)
            
            self.db.runTransaction({ (transaction, errorPointer) -> Any? in
                do {
                    let requestDocument = try transaction.getDocument(requestRef)
                    
                    guard let data = requestDocument.data(),
                          let recipientId = data["recipientId"] as? String,
                          let status = data["status"] as? String else {
                        let error = NSError(
                            domain: "FriendRequestError",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy lời mời kết bạn"]
                        )
                        errorPointer?.pointee = error
                        return nil
                    }
                    
                    guard recipientId == currentUser.uid else {
                        let error = NSError(
                            domain: "FriendRequestError",
                            code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "Bạn không có quyền từ chối lời mời này"]
                        )
                        errorPointer?.pointee = error
                        return nil
                    }
                    
                    guard status == "pending" else {
                        let error = NSError(
                            domain: "FriendRequestError",
                            code: -3,
                            userInfo: [NSLocalizedDescriptionKey: "Lời mời này đã được xử lý"]
                        )
                        errorPointer?.pointee = error
                        return nil
                    }
                    
                    transaction.updateData(["status": "declined"], forDocument: requestRef)
                    
                    return nil
                    
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }) { (result, error) in
                if let error = error {
                    promise(.failure(error))
                } else {
                    promise(.success("Đã từ chối lời mời kết bạn"))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Fetch Friends
    func fetchFriends(forUserId userId: String) -> AnyPublisher<[User], Error> {
        Future<[User], Error> { promise in
            let userRef = self.db.collection("users").document(userId)
            
            userRef.getDocument { snapshot, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }
                
                guard let document = snapshot, document.exists,
                      let data = document.data() else {
                    promise(.success([]))
                    return
                }
                
                let friendIds = data["friendIds"] as? [String] ?? []
                
                if friendIds.isEmpty {
                    promise(.success([]))
                    return
                }
                
                let group = DispatchGroup()
                var friends: [User] = []
                
                for friendId in friendIds {
                    group.enter()
                    
                    self.db.collection("users").document(friendId).getDocument { friendSnapshot, friendError in
                        defer { group.leave() }
                        
                        guard let friendDoc = friendSnapshot, friendDoc.exists,
                              let friendData = friendDoc.data(),
                              let fullName = friendData["fullName"] as? String,
                              let email = friendData["email"] as? String else {
                            return
                        }
                        
                        var friend = User(id: friendId, fullName: fullName, email: email)
                        friend.profileImageUrl = friendData["profileImageUrl"] as? String
                        friend.isOnline = friendData["isOnline"] as? Bool ?? false
                        
                        if let lastSeenTimestamp = friendData["lastSeen"] as? TimeInterval {
                            friend.lastSeen = Date(timeIntervalSince1970: lastSeenTimestamp)
                        }
                        
                        friends.append(friend)
                    }
                }
                
                group.notify(queue: .main) {
                    promise(.success(friends))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Remove Friend
    func removeFriend(currentUserId: String, friendId: String) -> AnyPublisher<Void, Error> {
        Future<Void, Error> { promise in
            self.db.collection("users").document(currentUserId).updateData([
                "friendIds": FieldValue.arrayRemove([friendId])
            ]) { error in
                if let error = error {
                    promise(.failure(error))
                    return
                }
                
                self.db.collection("users").document(friendId).updateData([
                    "friendIds": FieldValue.arrayRemove([currentUserId])
                ]) { error in
                    if let error = error {
                        promise(.failure(error))
                    } else {
                        promise(.success(()))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Get Pending Requests Count
    func getPendingRequestsCount() -> AnyPublisher<Int, Error> {
        Future<Int, Error> { promise in
            guard let currentUser = Auth.auth().currentUser else {
                promise(.failure(FriendError.userNotAuthenticated))
                return
            }
            
            self.db.collection("friend_requests")
                .whereField("recipientId", isEqualTo: currentUser.uid)
                .whereField("status", isEqualTo: "pending")
                .getDocuments { snapshot, error in
                    if let error = error {
                        promise(.failure(error))
                    } else {
                        promise(.success(snapshot?.documents.count ?? 0))
                    }
                }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Helper Methods
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
}

// MARK: - Friend Errors
enum FriendError: LocalizedError {
    case userNotAuthenticated
    case userNotFound
    case cannotAddSelf
    case alreadyFriends
    case requestAlreadySent
    case serviceUnavailable
    
    var errorDescription: String? {
        switch self {
        case .userNotAuthenticated:
            return "Người dùng chưa đăng nhập"
        case .userNotFound:
            return "Không tìm thấy người dùng với email này"
        case .cannotAddSelf:
            return "Bạn không thể gửi lời mời kết bạn cho chính mình"
        case .alreadyFriends:
            return "Người này đã là bạn bè của bạn"
        case .requestAlreadySent:
            return "Bạn đã gửi lời mời kết bạn cho người này trước đó"
        case .serviceUnavailable:
            return "Dịch vụ tạm thời không khả dụng"
        }
    }
}
