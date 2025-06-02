//
//  FriendViewModel.swift
//  Zenlyne
//
//  Created by admin on 2/6/25.
//

import Foundation
import Combine
import FirebaseAuth

class FriendViewModel: ObservableObject {
    @Published var friends: [User] = []
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var searchText = ""
    
    private let friendService: FriendServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    var filteredFriends: [User] {
        if searchText.isEmpty {
            return friends.sorted { friend1, friend2 in
                if friend1.isOnline && !friend2.isOnline {
                    return true
                } else if !friend1.isOnline && friend2.isOnline {
                    return false
                } else {
                    return friend1.fullName.localizedCaseInsensitiveCompare(friend2.fullName) == .orderedAscending
                }
            }
        } else {
            return friends.filter { friend in
                friend.fullName.localizedCaseInsensitiveContains(searchText) ||
                friend.email.localizedCaseInsensitiveContains(searchText)
            }.sorted { friend1, friend2 in
                if friend1.isOnline && !friend2.isOnline {
                    return true
                } else if !friend1.isOnline && friend2.isOnline {
                    return false
                } else {
                    return friend1.fullName.localizedCaseInsensitiveCompare(friend2.fullName) == .orderedAscending
                }
            }
        }
    }
    
    init(friendService: FriendServiceProtocol = FriendService()) {
        self.friendService = friendService
    }
    
    func fetchFriends() {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "Bạn cần đăng nhập để xem danh sách bạn bè"
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        friendService.fetchFriends(forUserId: currentUser.uid)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] friends in
                    self?.friends = friends
                }
            )
            .store(in: &cancellables)
    }
    
    func removeFriend(_ friend: User) {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        friendService.removeFriend(currentUserId: currentUser.uid, friendId: friend.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Không thể xóa bạn bè: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] _ in
                    self?.friends.removeAll { $0.id == friend.id }
                }
            )
            .store(in: &cancellables)
    }
    
    func clearError() {
        errorMessage = ""
    }
}
