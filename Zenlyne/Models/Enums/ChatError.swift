//
//  ChatError.swift
//  Zenlyne
//
//  Created by admin on 26/6/25.
//

import Foundation

enum ChatError: Error, LocalizedError {
    case notLoggedIn
    case invalidData
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Người dùng chưa đăng nhập"
        case .invalidData:
            return "Dữ liệu không hợp lệ"
        case .networkError:
            return "Lỗi kết nối mạng"
        }
    }
}
