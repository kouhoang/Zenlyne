//
//  LoginView.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import SwiftUI
import Combine

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var showError = false
    @State private var showForgotPassword = false
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Image("gradient-theme-background")
                    .resizable()
                    .scaledToFill()
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    // Header
                    headerView
                    
                    // Title
                    titleView
                    
                    // Error message
                    if showError {
                        errorView
                    }
                    
                    // Form fields
                    formFieldsView
                    
                    // Forgot password button
                    forgotPasswordButton
                    
                    // Sign in button
                    signInButton
                    
                    Spacer()
                    
                    // Sign up navigation
                    signUpNavigationView
                }
                
                // Loading overlay
                if isLoading {
                    loadingOverlay
                }
                
                // Navigation to ForgotPasswordView
                NavigationLink(
                    destination: ForgotPasswordView().navigationBarBackButtonHidden(false),
                    isActive: $showForgotPassword
                ) {
                    EmptyView()
                }
            }
        }
        .onAppear {
            setupCombineObservers()
        }
    }
    
    // MARK: - View Components
    
    private var headerView: some View {
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
    }
    
    private var titleView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sign in to your Account")
                .font(.custom("Futura", size: 48))
                .fontWeight(.bold)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
            
            Text("Enter your email and password to login")
                .font(.system(size: 16))
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
                .padding(.top, 1)
        }
    }
    
    private var errorView: some View {
        Text(errorMessage.isEmpty ? "Incorrect email or password" : errorMessage)
            .foregroundColor(.red)
            .font(.system(size: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
            .padding(.top, 4)
    }
    
    private var formFieldsView: some View {
        VStack(spacing: 24) {
            InputView(text: $email, title: "Email Address", placeholder: "name@example.com")
                .autocapitalization(.none)
            
            InputView(text: $password, title: "Password", placeholder: "Enter your password", isSecureField: true)
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }
    
    private var forgotPasswordButton: some View {
        Button {
            showForgotPassword = true
        } label: {
            Text("Forgot password?")
                .font(.system(size: 14))
                .fontWeight(.semibold)
                .foregroundColor(.blue)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 16)
        .padding(.top, 8)
    }
    
    private var signInButton: some View {
        Button {
            signIn()
        } label: {
            VStack {
                Text("SIGN IN")
                    .fontWeight(.semibold)
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(.white)
            .frame(width: UIScreen.main.bounds.width - 32, height: 48)
        }
        .background(Color(.systemBlue))
        .disabled(!formIsValid || isLoading)
        .opacity(formIsValid && !isLoading ? 1.0 : 0.5)
        .cornerRadius(10)
        .padding(.top, 16)
    }
    
    private var signUpNavigationView: some View {
        NavigationLink {
            RegistrationView()
                .navigationBarBackButtonHidden(true)
        } label: {
            HStack(spacing: 3) {
                Text("Don't have an account?")
                Text("Sign up")
                    .fontWeight(.bold)
            }
            .font(.system(size: 14))
        }
    }
    
    private var loadingOverlay: some View {
        Color.black.opacity(0.3)
            .ignoresSafeArea()
            .overlay(
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            )
    }
    
    // MARK: - Methods
    
    private func setupCombineObservers() {
        // Observe loading state
        viewModel.isLoadingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [self] loading in
                isLoading = loading
            }
            .store(in: &cancellables)
        
        // Observe error state
        viewModel.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [self] error in
                if let error = error {
                    errorMessage = error
                    showError = true
                } else {
                    showError = false
                    errorMessage = ""
                }
            }
            .store(in: &cancellables)
        
        // Auto-dismiss error after successful authentication
        viewModel.isAuthenticatedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [self] isAuthenticated in
                if isAuthenticated {
                    showError = false
                    errorMessage = ""
                }
            }
            .store(in: &cancellables)
    }
    
    private func signIn() {
        Task {
            do {
                try await viewModel.signIn(withEmail: email, password: password)
            } catch {
                // Error handling is done through Combine observers
                print("DEBUG: Sign in failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - AuthenticationFormProtocol
extension LoginView: AuthentiicationFormProtocol {
    var formIsValid: Bool {
        return !email.isEmpty && email.contains("@") && !password.isEmpty && password.count > 5
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
