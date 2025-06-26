//
//  UserError.swift
//  Zenlyne
//
//  Created by admin on 26/6/25.
//

import Foundation

enum UserError: Error, LocalizedError {
    case notLoggedIn
    case userNotFound
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Người dùng chưa đăng nhập"
        case .userNotFound:
            return "Không tìm thấy người dùng"
        case .invalidData:
            return "Dữ liệu người dùng không hợp lệ"
        }
    }
}
