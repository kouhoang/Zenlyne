//
//  AuthState.swift
//  Zenlyne
//
//  Created by admin on 26/6/25.
//

import Foundation

enum AuthState {
    case idle
    case loading
    case authenticated(User)
    case unauthenticated
    case error(String)
}
