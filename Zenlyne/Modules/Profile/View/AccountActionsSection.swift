//
//  AccountActionsSection.swift
//  Zenlyne
//
//  Created by admin on 23/5/25.
//

import SwiftUI

// MARK: - Account Actions Section
struct AccountActionsSection: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Binding var showDeleteConfirmation: Bool
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Hoạt động tài khoản")
                .font(.headline)
                .foregroundColor(.gray)
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 5)
            
            VStack(spacing: 0) {
                Button(action: {
                    authViewModel.signOut()
                }) {
                    HStack {
                        IconContainer(systemName: "arrow.left.circle.fill")
                        
                        Text("Đăng xuất")
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding()
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                Button(action: {
                    showDeleteConfirmation = true
                }) {
                    HStack {
                        IconContainer(systemName: "xmark.circle.fill")
                        
                        Text("Xoá tài khoản")
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding()
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .background(Color.black.opacity(0.3))
            .cornerRadius(10)
            .padding(.horizontal)
        }
    }
}
