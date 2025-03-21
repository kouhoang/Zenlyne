//
//  MapViewController.swift
//  Zenlyne
//
//  Created by admin on 19/3/25.
//

import SwiftUI
import MapboxMaps
import CoreLocation

struct MapViewController: View {

    @StateObject private var viewModel = LocationViewModel()
    
    var body: some View {
        ZStack {
            // Map View
            MapViewRepresentable(viewModel: viewModel)
                .ignoresSafeArea()
            
            // UI Controls
            VStack {
                Spacer()
                
                HStack {
                    Spacer()
                    
                    LocationButton(
                        action: {
                            if viewModel.isTrackingLocation {
                                viewModel.focusOnUserLocation()
                            } else {
                                viewModel.startTrackingLocation()
                            }
                        },
                        isTracking: viewModel.isTrackingLocation
                    )
                }
                .padding(.bottom, 30)
                .padding(.trailing)
            }
        }
        .onAppear {
            viewModel.startTrackingLocation()
        }
    }
}

#Preview {
    MapViewController()
}
