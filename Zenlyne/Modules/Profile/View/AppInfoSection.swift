//
//  AppInfoSection.swift
//  Zenlyne
//
//  Created by admin on 23/5/25.
//

import SwiftUI

// MARK: - Application Info Section
struct AppInfoSection: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("Thông tin ứng dụng")
                .font(.headline)
                .foregroundColor(.gray)
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 5)
            
            VStack(spacing: 0) {
                HStack {
                    IconContainer(systemName: "info.circle.fill")
                    
                    Text("Về Zenlyne")
                        .foregroundColor(.white)
                    Spacer()
                    Text("Version 1.0.0")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
                .padding()
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                NavigationLink(destination: HelpSupportView()) {
                    HStack {
                        IconContainer(systemName: "questionmark.circle.fill")
                        
                        Text("Trợ giúp và Hỗ trợ")
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding()
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                Link(destination: URL(string: "https://zenlyne.app/terms")!) {
                    HStack {
                        IconContainer(systemName: "doc.text.fill")
                        
                        Text("Điều khoản dịch vụ")
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundColor(.gray)
                    }
                    .padding()
                }
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                Link(destination: URL(string: "https://zenlyne.app/privacy")!) {
                    HStack {
                        IconContainer(systemName: "shield.fill")
                        
                        Text("Chính sách bảo mật")
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundColor(.gray)
                    }
                    .padding()
                }
            }
            .background(Color.black)
            .cornerRadius(10)
            .padding(.horizontal)
        }
    }
}
