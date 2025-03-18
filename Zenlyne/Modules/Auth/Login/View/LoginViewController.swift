//
//  LoginViewController.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import SwiftUI

struct LoginViewController: View {
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @EnvironmentObject var viewModel: AuthViewModel
    
    var body: some View {
        NavigationStack {
            
            ZStack {
                Image("gradient-theme-background")
                    .resizable()
                    .scaledToFill()
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    
                    HStack {
                        Image("ice-cream-icon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 70, height: 70)
                        Text("Zenlyne")
                            .font(.custom("Avenir Next", size: 18))
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 0)
                    
                    Text("Sign in to your Account")
                        .font(.custom("Futura", size: 48))
                        .fontWeight(.bold)
                        .foregroundColor(.black).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16)
                    
                    Text("Enter your email and password to login")
                        .font(.system(size: 16))
                        .foregroundColor(.gray).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16).padding(.top, 1)
                    
                    // form fields
                    VStack(spacing: 24) {
                        InputView(text: $email, title: "Email Address", placeholder: "name@example.com").autocapitalization(.none)
                        
                        if let errorMessage = errorMessage {Text(errorMessage)
                                .foregroundColor(.red).font(.footnote).padding(.top, 4)}
                        
                        InputView(text: $password, title:"Password", placeholder: "Enter your password", isSecureField: true)
                        
                        if let errorMessage = errorMessage {Text(errorMessage).foregroundColor(.red).font(.footnote).padding(.top, 4)}
                    }
                    .padding(.horizontal).padding(.top, 12)
                    
                    // sign in button
                    
                    Button {
                        Task {
                            do {
                                try await viewModel.signIn(withEmail: email, password: password)
                                errorMessage = nil
                            }
                            catch {
                                errorMessage = "Invalid account or password"
                            }
                        }
                    } label: {
                        VStack {
                            Text("SIGN IN").fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                        }
                        .foregroundStyle(.white)
                        .frame(width: UIScreen.main.bounds.width - 32, height: 48)
                    }
                    .background(Color(.systemBlue)).disabled(!formIsValid).opacity(formIsValid ? 1.5 : 0.5).cornerRadius(10).padding(.top, 24)
                    
                    Spacer()
                    
                    // sign up button
                    
                    NavigationLink {
                        RegistrationViewController().navigationBarBackButtonHidden(true)
                    } label: {
                        HStack(spacing: 3) {
                            Text("Don't have an account?")
                            Text("Sign up").fontWeight(.bold)
                        }
                        .font(.system(size: 14))
                    }
                }
            }
        }
    }
}

// MARK: - AuthenticationFormProtocol

extension LoginViewController: AuthentiicationFormProtocol {
    var formIsValid: Bool {
        return !email.isEmpty && email.contains("@") && !password.isEmpty && password.count > 5
    }
}

#Preview {
    LoginViewController()
}
