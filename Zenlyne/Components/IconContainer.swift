//
//  IconContainer.swift
//  Zenlyne
//
//  Created by admin on 23/5/25.
//

import SwiftUICore

struct IconContainer: View {
    let systemName: String
    
    var body: some View {
        ZStack {
            // Background with pink-yellow-plain image
            Image("pink-yellow-plain")
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Black icon on top
            Image(systemName: systemName)
                .foregroundColor(.black)
                .font(.system(size: 16, weight: .medium))
        }
        .frame(width: 32, height: 32)
    }
}
