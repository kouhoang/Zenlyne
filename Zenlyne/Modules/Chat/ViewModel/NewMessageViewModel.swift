//
//  NewMessageViewModel.swift
//  Zenlyne
//
//  Created by admin on 2/6/25.
//


import Foundation
import Combine
import FirebaseAuth

class NewMessageViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var friends: [User] = []
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    
    // MARK: - Private Properties
    
    private let userService: UserServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
    var sortedFriends: [User] {
        let filteredUsers = searchText.isEmpty ? friends : friends.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchText) ||
            $0.email.localizedCaseInsensitiveContains(searchText)
        }
        
        return filteredUsers.sorted { (user1, user2) -> Bool in
            if user1.isOnline && !user2.isOnline {
                return true
            } else if !user1.isOnline && user2.isOnline {
                return false
            } else {
                return user1.fullName < user2.fullName
            }
        }
    }
    
    // MARK: - Initialization
    
    init(userService: UserServiceProtocol = UserService()) {
        self.userService = userService
        
        setupBindings()
        loadFriends()
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Auto-clear error message after 5 seconds
        $errorMessage
            .compactMap { $0.isEmpty ? nil : $0 }
            .delay(for: .seconds(5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.errorMessage = ""
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    func loadFriends() {
        isLoading = true
        
        userService.getFriends()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Không thể tải danh sách bạn bè: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] friends in
                    self?.friends = friends
                }
            )
            .store(in: &cancellables)
    }
    
    func refreshFriends() {
        loadFriends()
    }
}