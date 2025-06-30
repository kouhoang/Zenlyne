//
//  CameraUpdateReason.swift
//  Zenlyne
//
//  Created by admin on 30/6/25.
//

import Foundation

enum CameraUpdateReason {
    case userLocation
    case friendLocation(String)
    case clusterFocus(String)
    case userInitiated
    case initialLoad
    case none
}
