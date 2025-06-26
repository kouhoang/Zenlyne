//
//  LocationError.swift
//  Zenlyne
//
//  Created by admin on 26/6/25.
//

import Foundation

enum LocationError: Error, LocalizedError {
    case permissionDenied
    case locationUnavailable
    case timeout
    case accuracyTooLow
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location permission denied"
        case .locationUnavailable:
            return "Location services unavailable"
        case .timeout:
            return "Location request timed out"
        case .accuracyTooLow:
            return "Location accuracy too low"
        case .unknown(let error):
            return "Unknown location error: \(error.localizedDescription)"
        }
    }
}
