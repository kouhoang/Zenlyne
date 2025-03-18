//
//  ZenlyneApp.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import SwiftUI
import Firebase

@main
struct ZenlyneApp: App {
    @StateObject var viewModel = AuthViewModel()
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}
