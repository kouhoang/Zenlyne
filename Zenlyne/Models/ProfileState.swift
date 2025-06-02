//
//  ProfileState.swift
//  Zenlyne
//
//  Created by admin on 2/6/25.
//


import Foundation
import UIKit

// MARK: - Profile Models
struct ProfileState {
    var userFullName: String = ""
    var userEmail: String = ""
    var profileImage: UIImage?
    var isEditingName: Bool = false
    var isEditingPassword: Bool = false
    var isLoading: Bool = false
}

struct PasswordUpdateRequest {
    let currentPassword: String
    let newPassword: String
    let confirmPassword: String
    
    var isValid: Bool {
        return !currentPassword.isEmpty &&
               !newPassword.isEmpty &&
               !confirmPassword.isEmpty &&
               newPassword.count >= 6 &&
               newPassword == confirmPassword
    }
}

struct ProfileUpdateRequest {
    let fullName: String
    
    var isValid: Bool {
        return !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Profile Events
enum ProfileEvent {
    case loadUserData
    case updateName(String)
    case updatePassword(PasswordUpdateRequest)
    case uploadProfileImage(UIImage)
    case cancelNameEdit
    case cancelPasswordEdit
}

// MARK: - Profile Error Types
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
