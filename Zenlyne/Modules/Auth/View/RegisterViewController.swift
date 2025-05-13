//
//  RegisterViewController.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import SwiftUI

struct RegistrationViewController: View {
    
    @State private var email = ""
    @State private var fullName = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var viewModel: AuthViewModel
    
    
    var body: some View {
        
        ZStack {
            Image("gradient-theme-background")
                .resizable()
                .scaledToFill()
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                // image
                Image("ice-cream-icon").resizable()
                    .scaledToFill().frame(width: 200, height: 200).padding(.vertical, 32)
                
                // form fields
                VStack(spacing: 24) {
                    InputView(text: $email, title: "Email Address", placeholder: "name@example.com").autocapitalization(.none)
                    
                    InputView(text: $fullName, title: "Full Name", placeholder: "Enter your name")
                    
                    InputView(text: $password, title:"Password", placeholder: "Enter your password", isSecureField: true)
                    
                    ZStack(alignment: .trailing) {
                        InputView(text: $confirmPassword, title: "Confirm Password", placeholder: "Confirm your password", isSecureField: true)
                        
                        if !password.isEmpty && !confirmPassword.isEmpty {
                            if password == confirmPassword {
                                Image(systemName: "checkmark.circle.fill").imageScale(.large).fontWeight(.bold).foregroundColor(Color(.systemGreen))
                            } else {
                                Image(systemName: "checkmark.circle.fill").imageScale(.large).fontWeight(.bold).foregroundColor(Color(.systemRed))
                            }
                        }
                    }
                }
                .padding(.horizontal).padding(.top, 12)
                
                Button {
                    Task {
                        try await viewModel.createUser(withEmail: email, password: password, fullName: fullName)
                    }
                } label: {
                    VStack {
                        Text("SIGN UP").fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                    }
                    .foregroundStyle(.white)
                    .frame(width: UIScreen.main.bounds.width - 32, height: 48)
                }
                .background(Color(.systemBlue)).disabled(!formIsValid).opacity(formIsValid ? 1.5 : 0.5).cornerRadius(10).padding(.top, 24)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 3) {
                        Text("Already have an acoount?")
                        Text("Sign in").fontWeight(.bold)
                    }
                    .font(.system(size: 14))
                }
            }
        }
        
    }
}

// MARK: - AuthenticationFormProtocol

extension RegistrationViewController: AuthentiicationFormProtocol {
    var formIsValid: Bool {
        return !email.isEmpty && email.contains("@") && !password.isEmpty && password.count > 5 && confirmPassword == password && !fullName.isEmpty
    }
}

#Preview {
    RegistrationViewController()
}
