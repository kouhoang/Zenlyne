//
//  MapStyle.swift
//  Zenlyne
//
//  Created by admin on 30/6/25.
//

import Foundation
import MapboxMaps

enum MapStyle {
    case streets
    case satellite
    case satelliteStreets
    
    var mapboxStyle: StyleURI {
        switch self {
        case .streets:
            return .streets
        case .satellite:
            return .satellite
        case .satelliteStreets:
            return .satelliteStreets
        }
    }
    
    var displayName: String {
        switch self {
        case .streets:
            return "Standard"
        case .satellite:
            return "Satellite"
        case .satelliteStreets:
            return "Hybrid"
        }
    }
    
    var iconName: String {
        switch self {
        case .streets:
            return "map"
        case .satellite:
            return "globe"
        case .satelliteStreets:
            return "building.2"
        }
    }
    
    func nextStyle() -> MapStyle {
        switch self {
        case .streets:
            return .satellite
        case .satellite:
            return .satelliteStreets
        case .satelliteStreets:
            return .streets
        }
    }
}
