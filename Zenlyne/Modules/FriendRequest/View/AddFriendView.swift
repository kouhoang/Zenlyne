//
//  AddFriendView.swift
//  Zenlyne
//
//  Created by admin on 8/4/25.
//

import SwiftUI
import FirebaseFirestore

struct AddFriendView: View {
    @StateObject private var viewModel = FriendRequestViewModel()
    @State private var email = ""
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Tiêu đề
                Text("Thêm bạn bè")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top)
                
                // Mô tả
                Text("Nhập email của người bạn muốn kết bạn")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Trường nhập email
                VStack(alignment: .leading) {
                    Text("Email").foregroundColor(Color(.darkGray)).fontWeight(.semibold).font(.footnote)
                    
                    HStack {
                        TextField("name@example.com", text: $email)
                            .font(.system(size: 14))
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                            .disableAutocorrection(true)
                        
                        if !email.isEmpty {
                            Button(action: {
                                email = ""
                            }) {
                                Image(systemName: "multiply.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    
                    Divider()
                }
                .padding(.horizontal)
                .padding(.top, 20)
                
                // Nút gửi lời mời kết bạn
                Button(action: sendFriendRequest) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding(.vertical, 13)
                    } else {
                        Text("Gửi lời mời kết bạn")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                }
                .background(isValidEmail ? Color(.systemBlue) : Color(.systemGray4))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 20)
                .disabled(!isValidEmail || isLoading)
                
                Spacer()
            }
            .padding()
            .navigationBarTitle("Thêm bạn bè", displayMode: .inline)
            .navigationBarItems(trailing: Button("Đóng") {
                dismiss()
            })
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onTapGesture {
                hideKeyboard()
            }
        }
    }
    
    // Kiểm tra email hợp lệ
    private var isValidEmail: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email) && email != authViewModel.currentUser?.email
    }
    
    // Gửi lời mời kết bạn
    private func sendFriendRequest() {
        isLoading = true
        
        viewModel.sendFriendRequest(toEmail: email) { success, message in
            DispatchQueue.main.async {
                isLoading = false
                alertTitle = success ? "Thành công" : "Lỗi"
                alertMessage = message
                showAlert = true
                
                if success {
                    email = ""
                }
            }
        }
    }
}

// Extension để ẩn bàn phím
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct AddFriendView_Previews: PreviewProvider {
    static var previews: some View {
        AddFriendView()
            .environmentObject(AuthViewModel())
    }
}
