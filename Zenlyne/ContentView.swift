//
//  ContentView.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import SwiftUI
import Firebase

struct ContentView: View {
    @StateObject private var authViewModel = AuthViewModel()
    
    var body: some View {
        // Use userSessions to determine if user is logged in
        if authViewModel.userSessions == nil {
            LoginViewController()
                .environmentObject(authViewModel)
        } else {
            MapViewController()
                .environmentObject(authViewModel)
        }
    }
}

#Preview {
    ContentView()
}
