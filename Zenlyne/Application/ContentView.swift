//
//  ContentView.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import SwiftUI
import Firebase
import Combine

struct ContentView: View {
    @StateObject private var authViewModel = AuthViewModel()
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        Group {
            if authViewModel.userSessions == nil {
                LoginView()
                    .environmentObject(authViewModel)
            } else {
                MapView()
                    .environmentObject(authViewModel)
            }
        }
        .onAppear {
            setupCombineObservers()
        }
    }
    
    private func setupCombineObservers() {
        // Observe authentication state changes
        authViewModel.isAuthenticatedPublisher
            .sink { isAuthenticated in
                print("DEBUG: Authentication state changed: \(isAuthenticated)")
            }
            .store(in: &cancellables)
        
        // Observe loading state
        authViewModel.isLoadingPublisher
            .sink { isLoading in
                print("DEBUG: Loading state changed: \(isLoading)")
            }
            .store(in: &cancellables)
        
        // Observe errors
        authViewModel.errorPublisher
            .compactMap { $0 }
            .sink { error in
                print("DEBUG: Auth error occurred: \(error)")
                // Handle error presentation here if needed
            }
            .store(in: &cancellables)
    }
}

#Preview {
    ContentView()
}
