//
//  AddFriendViewModel.swift
//  Zenlyne
//
//  Created by admin on 2/6/25.
//

import Foundation
import Combine

class AddFriendViewModel: ObservableObject {
    @Published var email = ""
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var successMessage = ""
    
    private let friendService: FriendServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(friendService: FriendServiceProtocol = FriendService()) {
        self.friendService = friendService
    }
    
    var isValidEmail: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email) && !email.isEmpty
    }
    
    func sendFriendRequest() {
        guard isValidEmail else {
            errorMessage = "Email không hợp lệ"
            return
        }
        
        isLoading = true
        errorMessage = ""
        successMessage = ""
        
        friendService.sendFriendRequest(toEmail: email)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] message in
                    self?.successMessage = message
                    self?.email = ""
                }
            )
            .store(in: &cancellables)
    }
    
    func clearMessages() {
        errorMessage = ""
        successMessage = ""
    }
}
