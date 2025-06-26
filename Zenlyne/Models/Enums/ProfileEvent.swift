//
//  ProfileEvent.swift
//  Zenlyne
//
//  Created by admin on 26/6/25.
//

import Foundation
import UIKit

enum ProfileEvent {
    case loadUserData
    case updateName(String)
    case updatePassword(PasswordUpdateRequest)
    case uploadProfileImage(UIImage)
    case cancelNameEdit
    case cancelPasswordEdit
}
