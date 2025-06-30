//
//  LocationTrackingState.swift
//  Zenlyne
//
//  Created by admin on 30/6/25.
//

import Foundation

enum LocationTrackingState {
    case idle
    case requesting
    case tracking
    case denied
    case error(String)
}
