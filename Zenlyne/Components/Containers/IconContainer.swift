//
//  IconContainer.swift
//  Zenlyne
//
//  Created by admin on 23/5/25.
//

import SwiftUI
import UIKit

struct IconContainer: View {
    let systemName: String
    let size: CGFloat
    let color: Color
    
    init(systemName: String, size: CGFloat = 16, color: Color = .white) {
        self.systemName = systemName
        self.size = size
        self.color = color
    }
    
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size))
            .foregroundColor(color)
            .frame(width: 32, height: 32)
            .background(Color.gray.opacity(0.3))
            .clipShape(Circle())
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
