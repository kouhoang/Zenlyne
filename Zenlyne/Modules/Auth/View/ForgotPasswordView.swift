//
//  ForgotPasswordView.swift
//  Zenlyne
//
//  Created by admin on 13/5/25.
//

import SwiftUI
import FirebaseAuth

struct ForgotPasswordView: View {
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var message = ""
    @State private var showAlert = false
    @State private var isLoading = false
    @State private var alertTitle = ""
    @State private var isSuccess = false
    
    var body: some View {
        ZStack {
            Image("gradient-theme-background")
                .resizable()
                .scaledToFill()
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    
                    Text("Reset Password")
                        .font(.custom("Futura", size: 36))
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .padding(.top, 20)
                    
                    Text("Enter your email address and we'll send you a link to reset your password")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                        .padding(.top, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                
                // Form
                VStack(spacing: 20) {
                    InputView(text: $email, 
                             title: "Email Address", 
                             placeholder: "name@example.com")
                        .autocapitalization(.none)
                        .padding(.horizontal)
                    
                    // Reset password button
                    Button {
                        resetPassword()
                    } label: {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(width: UIScreen.main.bounds.width - 32, height: 48)
                        } else {
                            Text("SEND RESET LINK")
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .frame(width: UIScreen.main.bounds.width - 32, height: 48)
                        }
                    }
                    .background(Color(.systemBlue))
                    .disabled(!isValidEmail() || isLoading)
                    .opacity(isValidEmail() && !isLoading ? 1 : 0.5)
                    .cornerRadius(10)
                    .padding(.top, 24)
                }
                
                Spacer()
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(message),
                    dismissButton: .default(Text("OK")) {
                        // Return to login screen if reset was successful
                        if isSuccess {
                            dismiss()
                        }
                    }
                )
            }
        }
    }
    
    private func isValidEmail() -> Bool {
        return !email.isEmpty && email.contains("@") && email.contains(".")
    }
    
    private func resetPassword() {
        guard isValidEmail() else { return }
        
        isLoading = true
        
        Auth.auth().sendPasswordReset(withEmail: email) { error in
            isLoading = false
            
            if let error = error {
                alertTitle = "Error"
                message = error.localizedDescription
                isSuccess = false
            } else {
                alertTitle = "Success"
                message = "Password reset email has been sent to \(email). Please check your inbox."
                isSuccess = true
            }
            
            showAlert = true
        }
    }
}

#Preview {
    ForgotPasswordView()
}
