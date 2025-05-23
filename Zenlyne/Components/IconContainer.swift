//
//  IconContainer.swift
//  Zenlyne
//
//  Created by admin on 23/5/25.
//

import SwiftUI
import UIKit

// MARK: - Icon Container Component
struct IconContainer: View {
    let systemName: String
    
    var body: some View {
        ZStack {
            Image("pink-yellow-plain")
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Image(systemName: systemName)
                .foregroundColor(.black)
                .font(.system(size: 16, weight: .medium))
        }
        .frame(width: 32, height: 32)
    }
}

// MARK: - Helper Views
struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                
                Text(message)
                    .foregroundColor(.white)
                    .font(.subheadline)
                
                Spacer()
                
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(Color.red)
            .cornerRadius(8)
            .padding()
            
            Spacer()
        }
    }
}

struct SuccessBanner: View {
    let message: String
    let dismiss: () -> Void
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.white)
                
                Text(message)
                    .foregroundColor(.white)
                    .font(.subheadline)
                
                Spacer()
                
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(Color.green)
            .cornerRadius(8)
            .padding()
            
            Spacer()
        }
    }
}

struct OTPModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .frame(height: 45)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .padding(.horizontal)
    }
}
