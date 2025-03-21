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
                HStack {
                    // User info section
                    VStack(alignment: .leading) {
                        Text(User.MOCK_USER.fullName)
                            .font(.headline)
                        if let location = viewModel.userLocation {
                            Text(String(format: "%.4f, %.4f", location.latitude, location.longitude))
                                .font(.caption)
                        } else {
                            Text("Location: Unknown")
                                .font(.caption)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white)
                            .shadow(radius: 2)
                    )
                    
                    Spacer()
                }
                .padding()
                
                Spacer()
                
                // Bottom controls
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
