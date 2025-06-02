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

// MARK: - Password Section (Fixed)
struct PasswordSection: View {
    @ObservedObject var viewModel: ProfileViewModel
    
    var body: some View {
        if viewModel.isEditingPassword {
            VStack(spacing: 15) {
                SecureField("Mật khẩu hiện tại", text: $viewModel.currentPassword)
                    .textContentType(.password)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(8)

                SecureField("Mật khẩu mới", text: $viewModel.newPassword)
                    .textContentType(.newPassword)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(8)

                SecureField("Xác nhận lại mật khẩu mới", text: $viewModel.confirmPassword)
                    .textContentType(.newPassword)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                
                // Password validation feedback
                if !viewModel.newPassword.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ValidationRow(
                            text: "Tối thiểu 6 ký tự",
                            isValid: viewModel.newPassword.count >= 6
                        )
                        
                        if !viewModel.confirmPassword.isEmpty {
                            ValidationRow(
                                text: "Mật khẩu khớp",
                                isValid: viewModel.newPassword == viewModel.confirmPassword
                            )
                        }
                    }
                    .padding(.vertical, 5)
                }
                
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

// MARK: - Validation Row
struct ValidationRow: View {
    let text: String
    let isValid: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isValid ? .green : .red)
                .font(.caption)
            
            Text(text)
                .font(.caption)
                .foregroundColor(isValid ? .green : .red)
            
            Spacer()
        }
    }
}

// MARK: - Password Buttons (Fixed)
struct PasswordButtons: View {
    @ObservedObject var viewModel: ProfileViewModel
    
    private var isFormValid: Bool {
        !viewModel.currentPassword.isEmpty &&
        !viewModel.newPassword.isEmpty &&
        !viewModel.confirmPassword.isEmpty &&
        viewModel.newPassword.count >= 6 &&
        viewModel.newPassword == viewModel.confirmPassword
    }
    
    var body: some View {
        HStack {
            Spacer()
            
            Button(action: {
                viewModel.cancelPasswordEdit()
            }) {
                Text("Huỷ")
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(8)
            }
            .padding(.trailing, 10)
            
            Button(action: {
                viewModel.updatePassword { success in
                    if success {
                        print("Password updated successfully")
                    }
                }
            }) {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    
                    Text("Cập nhật mật khẩu")
                        .foregroundColor(isFormValid ? .white : .gray)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isFormValid ? Color.blue : Color.gray.opacity(0.3))
                .cornerRadius(8)
            }
            .disabled(!isFormValid || viewModel.isLoading)
        }
    }
}

// MARK: - Settings Rows (Unchanged)
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
