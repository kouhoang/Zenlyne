//
//  ContentView.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import SwiftUI
import Firebase

struct ContentView: View {
    @EnvironmentObject var viewModel: AuthViewModel

    var body: some View {
        Group {
            if viewModel.userSessions != nil {
                MapViewController()
            } else {
                LoginViewController()
            }
        }
        .onAppear {
        // Thực hiện hành động khi màn hình xuất hiện
        if viewModel.userSessions == nil {
            print("DEBUG: User is not signed in, showing login screen")
        }
    }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
