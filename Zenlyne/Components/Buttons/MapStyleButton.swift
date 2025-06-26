//
//  MapStyleButton.swift
//  Zenlyne
//
//  Created by admin on 28/5/25.
//

import SwiftUICore
import SwiftUI


struct MapStyleButton: View {
    @ObservedObject var viewModel: LocationViewModel
    
    var body: some View {
        Button(action: {
            viewModel.toggleMapStyle()
        }) {
            ZStack {
//                RoundedRectangle(cornerRadius: 12)
//                    .fill(Color.white)
//                    .frame(width: 40, height: 40)
//                    .shadow(radius: 4)
                
                VStack(spacing: 2) {
                    Image(systemName: viewModel.currentMapStyle.iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 35, height: 35)
                        .foregroundColor(.black)
                    
//                    Text(viewModel.currentMapStyle.displayName)
//                        .font(.system(size: 9))
//                        .foregroundColor(.black)
//                        .lineLimit(1)
                }
            }
        }
    }
}
