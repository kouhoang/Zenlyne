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
