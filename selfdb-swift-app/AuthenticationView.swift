//
//  AuthenticationView.swift
//  selfd-swift
//
//  Created by rodgers magabo on 04/06/2025.
//

import SwiftUI

struct AuthenticationView: View {
    @State private var isLoginMode = true
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    @Binding var isPresented: Bool
    @ObservedObject var selfDBManager: SelfDBManager
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(isLoginMode ? "Login" : "Register")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                VStack(spacing: 16) {
                    // Email field
                    TextField("Email", text: $email)
                        .textFieldStyle(CustomTextFieldStyle())
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    
                    // Password field
                    SecureField("Password", text: $password)
                        .textFieldStyle(CustomTextFieldStyle())
                    
                    // Confirm password (only for register)
                    if !isLoginMode {
                        SecureField("Confirm Password", text: $confirmPassword)
                            .textFieldStyle(CustomTextFieldStyle())
                    }
                }
                
                // Error message
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                
                // Submit button
                Button {
                    handleSubmit()
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(isLoginMode ? "Login" : "Register")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(25)
                }
                .disabled(isLoading)
                
                // Toggle mode
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isLoginMode.toggle()
                        errorMessage = ""
                        password = ""
                        confirmPassword = ""
                    }
                } label: {
                    Text(isLoginMode ? "Don't have an account? Register here" : "Already have an account? Login here")
                        .foregroundColor(.blue)
                        .font(.callout)
                }
            }
            .padding(.horizontal, 32)
            .navigationTitle("")  // keeps large title off
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
            .interactiveDismissDisabled(isLoading)   // prevent swipe-down while loading
        }
    }
    
    private func handleSubmit() {
        guard !email.isEmpty && !password.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        
        if !isLoginMode {
            guard password == confirmPassword else {
                errorMessage = "Passwords do not match"
                return
            }
            
            guard password.count >= 6 else {
                errorMessage = "Password must be at least 6 characters"
                return
            }
        }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            // removed do-catch – these functions are non-throwing
            if isLoginMode {
                await selfDBManager.signIn(email: email, password: password)
            } else {
                await selfDBManager.signUp(email: email, password: password)
            }
            
            await MainActor.run {
                isPresented = false
                isLoading = false
            }
        }
    }
}

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .font(.system(size: 16))
    }
}

#Preview {
    AuthenticationView(isPresented: .constant(true), selfDBManager: SelfDBManager())
}
