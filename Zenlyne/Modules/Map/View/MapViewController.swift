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
            MapViewRepresentable(viewModel: viewModel)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                HStack {
                    Spacer()
                    
                    LocationButton(
                        action: {
                            viewModel.focusOnUserLocation()
                        },
                        isTracking: viewModel.isTrackingLocation
                    )
                }
                .padding(.bottom, 30)
                .padding(.trailing)
            }
        }
        .onAppear {
            // Bắt đầu tracking location ngay khi vào app
            viewModel.startTrackingLocation()
        }
    }
}

#Preview {
    MapViewController()
}
