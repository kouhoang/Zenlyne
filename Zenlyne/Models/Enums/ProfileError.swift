//
//  ProfileError.swift
//  Zenlyne
//
//  Created by admin on 26/6/25.
//

import Foundation

enum ProfileError: LocalizedError {
    case invalidInput(String)
    case authenticationFailed(String)
    case networkError(String)
    case uploadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return message
        case .authenticationFailed(let message):
            return "Xác thực thất bại: \(message)"
        case .networkError(let message):
            return "Lỗi mạng: \(message)"
        case .uploadFailed(let message):
            return "Tải lên thất bại: \(message)"
        }
    }
}
