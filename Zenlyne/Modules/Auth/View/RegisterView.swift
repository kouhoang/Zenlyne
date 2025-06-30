//
//  RegistrationView.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import SwiftUI
import Combine

struct RegistrationView: View {
    @State private var email = ""
    @State private var fullName = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        ZStack {
            Image("gradient-theme-background")
                .resizable()
                .scaledToFill()
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                // App icon
                iconView
                
                // Error message
                if showError {
                    errorView
                }
                
                // Form fields
                formFieldsView
                
                // Sign up button
                signUpButton
                
                Spacer()
                
                // Sign in navigation
                signInNavigationView
            }
            
            // Loading overlay
            if isLoading {
                loadingOverlay
            }
        }
        .onAppear {
            setupCombineObservers()
        }
    }
    
    // MARK: - View Components
    
    private var iconView: some View {
        Image("ice-cream-icon")
            .resizable()
            .scaledToFill()
            .frame(width: 200, height: 200)
            .padding(.vertical, 32)
    }
    
    private var errorView: some View {
        Text(errorMessage)
            .foregroundColor(.red)
            .font(.system(size: 14))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }
    
    private var formFieldsView: some View {
        VStack(spacing: 24) {
            InputView(text: $email, title: "Email Address", placeholder: "name@example.com")
                .autocapitalization(.none)
            
            InputView(text: $fullName, title: "Full Name", placeholder: "Enter your name")
            
            InputView(text: $password, title: "Password", placeholder: "Enter your password", isSecureField: true)
            
            ZStack(alignment: .trailing) {
                InputView(text: $confirmPassword, title: "Confirm Password", placeholder: "Confirm your password", isSecureField: true)
                
                if !password.isEmpty && !confirmPassword.isEmpty {
                    Image(systemName: password == confirmPassword ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .imageScale(.large)
                        .fontWeight(.bold)
                        .foregroundColor(password == confirmPassword ? Color(.systemGreen) : Color(.systemRed))
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }
    
    private var signUpButton: some View {
        Button {
            signUp()
        } label: {
            VStack {
                Text("SIGN UP")
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
        .padding(.top, 24)
    }
    
    private var signInNavigationView: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 3) {
                Text("Already have an account?")
                Text("Sign in")
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
        
        // Auto-dismiss on successful authentication
        viewModel.isAuthenticatedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [self] isAuthenticated in
                if isAuthenticated {
                    showError = false
                    errorMessage = ""
                    // Don't dismiss here as navigation will be handled by ContentView
                }
            }
            .store(in: &cancellables)
    }
    
    private func signUp() {
        Task {
            do {
                try await viewModel.createUser(withEmail: email, password: password, fullName: fullName)
            } catch {
                // Error handling is done through Combine observers
                print("DEBUG: Sign up failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - AuthenticationFormProtocol
extension RegistrationView: AuthentiicationFormProtocol {
    var formIsValid: Bool {
        return !email.isEmpty &&
               email.contains("@") &&
               !password.isEmpty &&
               password.count > 5 &&
               confirmPassword == password &&
               !fullName.isEmpty
    }
}

#Preview {
    RegistrationView()
        .environmentObject(AuthViewModel())
}
