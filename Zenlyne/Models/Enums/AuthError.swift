//
//  AuthError.swift
//  Zenlyne
//
//  Created by admin on 26/6/25.
//

import Foundation

enum AuthError: Error {
    case userNotFound
    case emailInUse
    case weakPassword
    case invalidEmail
    case wrongPassword
    case unknownError
    
    var localizedDescription: String {
        switch self {
        case .userNotFound:
            return "User not found"
        case .emailInUse:
            return "Email already in use"
        case .weakPassword:
            return "Password too weak"
        case .invalidEmail:
            return "Invalid email"
        case .wrongPassword:
            return "Wrong password"
        case .unknownError:
            return "Unknown error occurred"
        }
    }
}
