//
//  LocationButton.swift
//  Zenlyne
//
//  Created by admin on 21/3/25.
//

import SwiftUI

struct LocationButton: View {
    let action: () -> Void
    let isTracking: Bool
    
    var body: some View {
        Button(action: action) {
            Image(systemName: isTracking ? "location.fill" : "location")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(isTracking ? Color.blue : Color.gray)
                .clipShape(Circle())
                .shadow(radius: 4)
        }
    }
}
