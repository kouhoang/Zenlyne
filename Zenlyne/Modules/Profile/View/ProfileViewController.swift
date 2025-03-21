//
//  ProfileViewController.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import SwiftUI
import PhotosUI
import FirebaseStorage

struct ProfileViewController: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var selectedItem: PhotosPickerItem?
    @State private var profileImage: UIImage?
    @State private var isLoading = false
    @State private var showingPhotoPicker = false
    
    var body: some View {
        if let user = viewModel.currentUser {
            List {
                Section {
                    HStack {
                        // Avatar với chức năng chọn ảnh
                        Button {
                            showingPhotoPicker = true
                        } label: {
                            ZStack {
                                if let profileImage = profileImage {
                                    Image(uiImage: profileImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(Circle())
                                } else {
                                    Text(user.initials)
                                        .font(.title)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .frame(width: 72, height: 72)
                                        .background(Color(.systemGray3))
                                        .clipShape(Circle())
                                }
                                
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .frame(width: 72, height: 72)
                                        .background(Color.black.opacity(0.3))
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedItem, matching: .images)
                        .onChange(of: selectedItem) { newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self),
                                   let image = UIImage(data: data) {
                                    await MainActor.run {
                                        self.profileImage = image
                                        isLoading = true
                                        uploadProfileImage(image)
                                    }
                                }
                            }
                        }
                        
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.fullName).font(.subheadline).fontWeight(.semibold).padding(.top, 4)
                            
                            Text(user.email).font(.footnote).accentColor(.gray)
                        }
                    }
                }
                
                Section("General") {
                    HStack {
                        SettingsRowView(imageName: "gear", title: "Version", tintColor: Color(.systemGray))
                        
                        Spacer()
                        
                        Text("1.0.0").font(.subheadline).foregroundColor(.gray)
                    }
                }
                
                Section("Account") {
                    Button {
                        viewModel.signOut()
                    } label: {
                        SettingsRowView(imageName: "arrow.left.circle.fill", title: "Sign Out", tintColor: .red)
                    }
                    
                    Button {
                        print("Delete account...")
                    } label: {
                        SettingsRowView(imageName: "xmark.circle.fill", title: "Delete Account", tintColor: .red)
                    }
                }
            }
            .onAppear {
                loadProfileImage()
            }
        }
    }
    
    func loadProfileImage() {
        guard let user = viewModel.currentUser, let profileImageUrl = user.profileImageUrl, let url = URL(string: profileImageUrl) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                print("DEBUG: Failed to fetch image: \(error.localizedDescription)")
                return
            }
            
            guard let data = data, let image = UIImage(data: data) else { return }
            
            DispatchQueue.main.async {
                self.profileImage = image
            }
        }.resume()
    }
    
    func uploadProfileImage(_ image: UIImage) {
        guard let uid = viewModel.userSessions?.uid else { return }
        guard let imageData = image.jpegData(compressionQuality: 0.5) else { return }
        
        let filename = "\(uid).jpg"
        
        // Tạo tham chiếu đến root của Storage trước
        let storageRef = Storage.storage().reference()
        
        // Kiểm tra xem thư mục profile_images có tồn tại hay không
        // Nếu không, tạo thư mục trước
        let profileImagesRef = storageRef.child("profile_images")
        
        // Tạo tham chiếu đến file cần tải lên
        let imageRef = profileImagesRef.child(filename)
        
        // Tải ảnh lên
        imageRef.putData(imageData, metadata: nil) { metadata, error in
            if let error = error {
                print("DEBUG: Failed to upload image with error: \(error.localizedDescription)")
                self.isLoading = false
                return
            }
            
            // Sau khi tải lên thành công, lấy URL
            imageRef.downloadURL { url, error in
                if let error = error {
                    print("DEBUG: Failed to get download URL: \(error.localizedDescription)")
                    self.isLoading = false
                    return
                }
                
                guard let imageUrl = url?.absoluteString else {
                    print("DEBUG: Failed to get valid URL")
                    self.isLoading = false
                    return
                }
                
                print("DEBUG: Successfully uploaded image with URL: \(imageUrl)")
                
                self.viewModel.updateUserProfileImage(imageUrl: imageUrl)
                self.isLoading = false
            }
        }
    }
}

#Preview {
    ProfileViewController()
}
