//
//  AddFriendView.swift
//  Zenlyne
//
//  Created by admin on 8/4/25.
//

import SwiftUI
import Combine

struct AddFriendView: View {
    @StateObject private var viewModel = AddFriendViewModel()
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                headerSection
                instructionSection
                emailInputSection
                errorSection
                actionButton
                Spacer()
            }
            .padding()
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitle("Thêm bạn bè", displayMode: .inline)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onTapGesture {
                hideKeyboard()
            }
            .onReceive(viewModel.$successMessage) { message in
                if !message.isEmpty {
                    showSuccessAlert(message: message)
                }
            }
            .onReceive(viewModel.$errorMessage) { message in
                if !message.isEmpty && showAlert == false {
                    showErrorAlert(message: message)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .padding(.top)
            
            Text("Thêm bạn bè")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
    
    private var instructionSection: some View {
        VStack(spacing: 8) {
            Text("Nhập email của người bạn muốn kết bạn")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            Text("Họ sẽ nhận được lời mời kết bạn từ bạn")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }
    
    private var emailInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Email")
                    .foregroundColor(.gray)
                    .fontWeight(.semibold)
                    .font(.footnote)
                
                Spacer()
                
                if viewModel.isValidEmail {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            
            HStack {
                Image(systemName: "envelope")
                    .foregroundColor(.gray)
                    .font(.system(size: 16))
                
                TextField("name@example.com", text: $viewModel.email)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                
                if !viewModel.email.isEmpty {
                    Button(action: {
                        viewModel.email = ""
                        viewModel.clearMessages()
                    }) {
                        Image(systemName: "multiply.circle.fill")
                            .foregroundColor(.gray)
                            .font(.system(size: 16))
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                viewModel.isValidEmail ? Color.green : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }
    
    private var errorSection: some View {
        Group {
            if !viewModel.errorMessage.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    
                    Text(viewModel.errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.horizontal)
                .transition(.opacity.combined(with: .scale))
            }
        }
    }
    
    private var actionButton: some View {
        VStack(spacing: 12) {
            Button(action: {
                viewModel.sendFriendRequest()
            }) {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16))
                        
                        Text("Gửi lời mời kết bạn")
                            .fontWeight(.semibold)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            viewModel.isValidEmail && !viewModel.isLoading
                                ? LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.purple]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    gradient: Gradient(colors: [Color.gray, Color.gray]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                        )
                )
                .scaleEffect(viewModel.isLoading ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: viewModel.isLoading)
            }
            .disabled(!viewModel.isValidEmail || viewModel.isLoading)
            .padding(.horizontal)
            .padding(.top, 10)
            
            // Quick add suggestions (if needed)
            if viewModel.email.isEmpty {
                VStack(spacing: 8) {
                    Text("Gợi ý")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 8) {
                        quickAddButton(title: "Từ danh bạ", icon: "person.crop.circle")
                        quickAddButton(title: "Quét QR", icon: "qrcode.viewfinder")
                    }
                }
                .padding(.top, 8)
            }
        }
    }
    
    private func quickAddButton(title: String, icon: String) -> some View {
        Button(action: {
            // TODO: Implement quick add functionality
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func showSuccessAlert(message: String) {
        alertTitle = "Thành công"
        alertMessage = message
        showAlert = true
    }
    
    private func showErrorAlert(message: String) {
        alertTitle = "Lỗi"
        alertMessage = message
        showAlert = true
    }
}

// Extension to hide keyboard
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct AddFriendView_Previews: PreviewProvider {
    static var previews: some View {
        AddFriendView()
            .environmentObject(AuthViewModel())
            .preferredColorScheme(.dark)
    }
}
