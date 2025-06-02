//
//  FriendCoordinator.swift
//  Zenlyne
//
//  Created by admin on 2/6/25.
//

import Foundation
import SwiftUI
import Combine

class FriendCoordinator: ObservableObject {
    @Published var currentView: FriendView = .list
    
    private let friendService: FriendServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    enum FriendView {
        case list
        case addFriend
        case requests
    }
    
    init(friendService: FriendServiceProtocol = FriendService()) {
        self.friendService = friendService
    }
    
    func showAddFriend() {
        currentView = .addFriend
    }
    
    func showRequests() {
        currentView = .requests
    }
    
    func showFriendsList() {
        currentView = .list
    }
}
