//
//  RegisterView.swift
//  Self-Social
//

import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var db: SelfDBManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var error: String?
    
    private var isFormValid: Bool {
        !firstName.isEmpty && !lastName.isEmpty && !email.isEmpty && !password.isEmpty && !confirmPassword.isEmpty
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Self-Social")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(colors: [.orange, .blue], startPoint: .leading, endPoint: .trailing)
                        )
                    
                    Text("Create your account to get started.")
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                .padding(.bottom, 20)
                
                VStack(spacing: 16) {
                    if let error = error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(10)
                    }
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("First Name").font(.subheadline).fontWeight(.medium)
                            HStack {
                                Image(systemName: "person.fill").foregroundColor(.secondary)
                                TextField("John", text: $firstName)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Last Name").font(.subheadline).fontWeight(.medium)
                            TextField("Doe", text: $lastName)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email").font(.subheadline).fontWeight(.medium)
                        HStack {
                            Image(systemName: "envelope.fill").foregroundColor(.secondary)
                            TextField("you@example.com", text: $email)
                                .textContentType(.emailAddress)
                                .autocapitalization(.none)
                                .keyboardType(.emailAddress)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password").font(.subheadline).fontWeight(.medium)
                        HStack {
                            Image(systemName: "lock.fill").foregroundColor(.secondary)
                            if showPassword {
                                TextField("••••••••", text: $password)
                            } else {
                                SecureField("••••••••", text: $password)
                            }
                            Button { showPassword.toggle() } label: {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Password").font(.subheadline).fontWeight(.medium)
                        HStack {
                            Image(systemName: "lock.fill").foregroundColor(.secondary)
                            if showPassword {
                                TextField("••••••••", text: $confirmPassword)
                            } else {
                                SecureField("••••••••", text: $confirmPassword)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    
                    Button {
                        Task { await register() }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Create Account").fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(colors: [.orange, .blue], startPoint: .leading, endPoint: .trailing)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isLoading || !isFormValid)
                    .opacity(isFormValid ? 1 : 0.6)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.1), radius: 10)
                .padding(.horizontal)
                
                HStack {
                    Text("Already have an account?").foregroundColor(.secondary)
                    Button("Sign In") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }
                .padding(.top, 8)
            }
        }
        .background(
            LinearGradient(colors: [.orange.opacity(0.1), .white, .blue.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").fontWeight(.semibold)
                }
            }
        }
    }
    
    private func register() async {
        guard isFormValid else { return }
        
        if password != confirmPassword {
            error = "Passwords do not match"
            return
        }
        
        if password.count < 6 {
            error = "Password must be at least 6 characters"
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            try await db.register(email: email, password: password, firstName: firstName, lastName: lastName)
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        RegisterView()
            .environmentObject(SelfDBManager.shared)
    }
}
