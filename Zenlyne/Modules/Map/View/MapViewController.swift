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
    @StateObject private var authViewModel = AuthViewModel()
    
    @State private var showProfileView = false
    @State private var showFriendRequestsView = false
    @State private var showAddFriendView = false
    
    var body: some View {
        ZStack {
            // Base Map View
            MapViewRepresentable(viewModel: viewModel)
                .ignoresSafeArea()
            
            // Overlay Views
            VStack {
                HStack {
                    Spacer()
                    
                    VStack(spacing: 10) { // Các nút xếp theo chiều dọc
                        // Profile Button
                        Button(action: {
                            showProfileView.toggle()
                        }) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                                .background(Color.white.clipShape(Circle()))
                                .shadow(radius: 4)
                        }
                        
                        // Friend Requests Button
                        Button(action: {
                            showFriendRequestsView.toggle()
                        }) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.green)
                                .background(Color.white.clipShape(Circle()))
                                .shadow(radius: 4)
                        }
                        
                        // Add Friend Button
                        Button(action: {
                            showAddFriendView.toggle()
                        }) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 40))
                                .foregroundColor(.purple)
                                .background(Color.white.clipShape(Circle()))
                                .shadow(radius: 4)
                        }
                    }
                    .padding(.top, 10)
                    .padding(.trailing, 10)
                }
                
                Spacer()
                
                // Bottom Row Buttons
                HStack {
                    Spacer()
                    
                    // Location Focus Button
                    LocationButton(
                        action: {
                            viewModel.focusOnUserLocation()
                        },
                        isTracking: viewModel.isTrackingLocation
                    )
                }
                .padding(.bottom, 30)
                .padding(.horizontal)
            }
            
            // Overlay Views (Sheets)
            .sheet(isPresented: $showProfileView) {
                ProfileViewController()
                    .environmentObject(authViewModel)
            }
            
            .sheet(isPresented: $showFriendRequestsView) {
                FriendRequestsView()
            }
            
            .sheet(isPresented: $showAddFriendView) {
                AddFriendView()
            }
        }
        .onAppear {
            // Start tracking location when app appears
            viewModel.startTrackingLocation()
        }
    }
}

#Preview {
    MapViewController()
}
