//
//  FriendError.swift
//  Zenlyne
//
//  Created by admin on 26/6/25.
//

import Foundation

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
