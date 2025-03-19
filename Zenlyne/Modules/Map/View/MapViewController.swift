//
//  MapViewController.swift
//  Zenlyne
//
//  Created by admin on 19/3/25.
//

import SwiftUI
import MapKit

struct MapView: View {
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.0),
        span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 50)
    )
    
    var body: some View {
        Map(coordinateRegion: $region)
            .edgesIgnoringSafeArea(.all)
            .navigationTitle("Map")
    }
}
