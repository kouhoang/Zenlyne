//
//  MapStyleManager.swift
//  Zenlyne
//
//  Created by admin on 30/6/25.
//


import Foundation
import MapboxMaps

class MapStyleManager {
    private let mapView: MapboxMaps.MapView
    
    init(mapView: MapboxMaps.MapView) {
        self.mapView = mapView
    }
    
    func updateStyle(to mapStyle: MapStyle) {
        print("DEBUG: Updating map style to: \(mapStyle.displayName)")
        mapView.mapboxMap.loadStyle(mapStyle.mapboxStyle)
    }
}