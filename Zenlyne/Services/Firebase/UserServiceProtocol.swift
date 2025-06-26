//
//  UserServiceProtocol.swift
//  Zenlyne
//
//  Created by admin on 2/6/25.
//


import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

protocol UserServiceProtocol {
    func getUser(by id: String) -> AnyPublisher<User, Error>
    func getFriends() -> AnyPublisher<[User], Error>
    func observeUserOnlineStatus(userId: String) -> AnyPublisher<Bool, Error>
}

class UserService: UserServiceProtocol {
    private let firestore = Firestore.firestore()
    
    func getUser(by id: String) -> AnyPublisher<User, Error> {
        return Future<User, Error> { promise in
            self.firestore.collection("users").document(id).getDocument { snapshot, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }
                
                guard let document = snapshot,
                      let data = document.data(),
                      let fullName = data["fullName"] as? String,
                      let email = data["email"] as? String else {
                    promise(.failure(UserError.userNotFound))
                    return
                }
                
                var user = User(id: id, fullName: fullName, email: email)
                user.profileImageUrl = data["profileImageUrl"] as? String
                user.isOnline = data["isOnline"] as? Bool ?? false
                
                if let lastSeenTimestamp = data["lastSeen"] as? Timestamp {
                    user.lastSeen = lastSeenTimestamp.dateValue()
                }
                
                promise(.success(user))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func getFriends() -> AnyPublisher<[User], Error> {
        return Future<[User], Error> { promise in
            guard let currentUserId = Auth.auth().currentUser?.uid else {
                promise(.failure(UserError.notLoggedIn))
                return
            }
            
            self.firestore.collection("users").document(currentUserId).getDocument { snapshot, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }
                
                guard let document = snapshot,
                      let data = document.data(),
                      let friendIds = data["friendIds"] as? [String] else {
                    promise(.success([]))
                    return
                }
                
                if friendIds.isEmpty {
                    promise(.success([]))
                    return
                }
                
                let group = DispatchGroup()
                var loadedFriends: [User] = []
                
                for friendId in friendIds {
                    group.enter()
                    
                    self.firestore.collection("users").document(friendId).getDocument { document, error in
                        defer { group.leave() }
                        
                        guard let document = document,
                              let data = document.data(),
                              let fullName = data["fullName"] as? String,
                              let email = data["email"] as? String else {
                            return
                        }
                        
                        var user = User(id: friendId, fullName: fullName, email: email)
                        user.profileImageUrl = data["profileImageUrl"] as? String
                        user.isOnline = data["isOnline"] as? Bool ?? false
                        
                        if let lastSeenTimestamp = data["lastSeen"] as? Timestamp {
                            user.lastSeen = lastSeenTimestamp.dateValue()
                        }
                        
                        loadedFriends.append(user)
                    }
                }
                
                group.notify(queue: .main) {
                    promise(.success(loadedFriends))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    func observeUserOnlineStatus(userId: String) -> AnyPublisher<Bool, Error> {
        return Future<Bool, Error> { promise in
            self.firestore.collection("users").document(userId)
                .addSnapshotListener { snapshot, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }
                    
                    guard let document = snapshot,
                          let data = document.data() else {
                        promise(.success(false))
                        return
                    }
                    
                    let isOnline = data["isOnline"] as? Bool ?? false
                    promise(.success(isOnline))
                }
        }
        .eraseToAnyPublisher()
    }
}
