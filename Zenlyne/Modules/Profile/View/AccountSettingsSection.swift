//
//  AccountSettingsSection.swift
//  Zenlyne
//
//  Created by admin on 23/5/25.
//

import SwiftUI

// MARK: - Account Settings Section
struct AccountSettingsSection: View {
    @ObservedObject var viewModel: ProfileViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Cài đặt tài khoản")
                .font(.headline)
                .foregroundColor(.gray)
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 5)
            
            VStack(spacing: 0) {
                PasswordSection(viewModel: viewModel)
                Divider().background(Color.gray.opacity(0.3))
                PrivacySettingsRow()
                Divider().background(Color.gray.opacity(0.3))
                NotificationSettingsRow()
            }
            .background(Color.black.opacity(0.3))
            .cornerRadius(10)
            .padding(.horizontal)
        }
    }
}

// MARK: - Password Section
struct PasswordSection: View {
    @ObservedObject var viewModel: ProfileViewModel
    
    var body: some View {
        if viewModel.isEditingPassword {
            VStack(spacing: 15) {
                SecureField("Mật khẩu hiện tại", text: $viewModel.currentPassword)
                    .textContentType(.password)
                    .padding(.vertical, 8)
                    .foregroundColor(.white)
                
                SecureField("Mật khẩu mới", text: $viewModel.newPassword)
                    .textContentType(.newPassword)
                    .padding(.vertical, 8)
                    .foregroundColor(.white)
                
                SecureField("Xác nhận lại mật khẩu mới", text: $viewModel.confirmPassword)
                    .textContentType(.newPassword)
                    .padding(.vertical, 8)
                    .foregroundColor(.white)
                
                PasswordButtons(viewModel: viewModel)
            }
            .padding()
            .background(Color.black.opacity(0.3))
        } else {
            Button(action: { viewModel.isEditingPassword = true }) {
                HStack {
                    IconContainer(systemName: "lock.fill")
                    Text("Thay đổi mật khẩu")
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

// MARK: - Password Buttons
struct PasswordButtons: View {
    @ObservedObject var viewModel: ProfileViewModel
    
    var body: some View {
        HStack {
            Spacer()
            
            Button(action: { viewModel.cancelPasswordEdit() }) {
                Text("Huỷ")
                    .foregroundColor(.red)
            }
            .padding(.trailing, 10)
            
            Button(action: {
                viewModel.updatePassword { success in }
            }) {
                Text("Cập nhật mật khẩu")
                    .foregroundColor(.blue)
            }
            .disabled(viewModel.currentPassword.isEmpty ||
                      viewModel.newPassword.isEmpty ||
                      viewModel.confirmPassword.isEmpty ||
                      viewModel.newPassword.count < 6 ||
                      viewModel.newPassword != viewModel.confirmPassword)
        }
    }
}

// MARK: - Settings Rows
struct PrivacySettingsRow: View {
    var body: some View {
        NavigationLink(destination: PrivacySettingsView()) {
            HStack {
                IconContainer(systemName: "hand.raised.fill")
                Text("Cài đặt Quyền riêng tư")
                    .foregroundColor(.white)
                Spacer()
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct NotificationSettingsRow: View {
    var body: some View {
        NavigationLink(destination: NotificationSettingsView()) {
            HStack {
                IconContainer(systemName: "bell.fill")
                Text("Cài đặt thông báo")
                    .foregroundColor(.white)
                Spacer()
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
