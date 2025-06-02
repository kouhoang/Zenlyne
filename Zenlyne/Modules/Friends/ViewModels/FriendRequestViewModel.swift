//
//  FriendRequestViewModel.swift
//  Zenlyne
//
//  Created by admin on 2/6/25.
//


import Foundation
import Combine

class FriendRequestViewModel: ObservableObject {
    @Published var friendRequests: [FriendRequest] = []
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var pendingRequestsCount = 0
    
    private let friendService: FriendServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(friendService: FriendServiceProtocol = FriendService()) {
        self.friendService = friendService
    }
    
    func fetchFriendRequests() {
        isLoading = true
        errorMessage = ""
        
        friendService.fetchFriendRequests()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] requests in
                    self?.friendRequests = requests
                }
            )
            .store(in: &cancellables)
    }
    
    func acceptFriendRequest(_ request: FriendRequest) {
        friendService.acceptFriendRequest(requestId: request.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] message in
                    // Remove accepted request from list
                    self?.friendRequests.removeAll { $0.id == request.id }
                    
                    // Post notification for other views
                    NotificationCenter.default.post(
                        name: NSNotification.Name("FriendRequestAccepted"),
                        object: nil,
                        userInfo: ["friendId": request.senderId]
                    )
                }
            )
            .store(in: &cancellables)
    }
    
    func declineFriendRequest(_ request: FriendRequest) {
        friendService.declineFriendRequest(requestId: request.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] _ in
                    // Remove declined request from list
                    self?.friendRequests.removeAll { $0.id == request.id }
                }
            )
            .store(in: &cancellables)
    }
    
    func loadPendingRequestsCount() {
        friendService.getPendingRequestsCount()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] count in
                    self?.pendingRequestsCount = count
                }
            )
            .store(in: &cancellables)
    }
}
