//
//  ProfileHeaderView.swift
//  Zenlyne
//
//  Created by admin on 23/5/25.
//

import SwiftUI
import PhotosUI

// MARK: - Profile Header Component
struct ProfileHeaderView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @Binding var selectedItem: PhotosPickerItem?
    @Binding var showingPhotoPicker: Bool
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Hồ sơ")
                .font(.headline)
                .foregroundColor(.gray)
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 5)
            
            VStack(spacing: 20) {
                ProfileAvatarView(
                    viewModel: viewModel,
                    selectedItem: $selectedItem,
                    showingPhotoPicker: $showingPhotoPicker
                )
                ProfileNameSection(viewModel: viewModel)
                ProfileEmailSection(viewModel: viewModel)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(ProfileBackgroundView())
            .cornerRadius(10)
            .padding(.horizontal)
        }
    }
}

// MARK: - Profile Avatar Component
struct ProfileAvatarView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @Binding var selectedItem: PhotosPickerItem?
    @Binding var showingPhotoPicker: Bool
    
    var body: some View {
        VStack {
            ZStack {
                Button(action: { showingPhotoPicker = true }) {
                    ZStack {
                        if let profileImage = viewModel.profileImage {
                            Image(uiImage: profileImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                        } else {
                            Circle()
                                .fill(Color(.systemGray4))
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Text(getInitials(from: viewModel.userFullName))
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                        
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(width: 100, height: 100)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                        
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                            )
                            .offset(x: 32, y: 32)
                    }
                }
            }
            .padding(.top, 10)
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedItem, matching: .images)
        .onChange(of: selectedItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        viewModel.profileImage = image
                        viewModel.uploadProfileImage(image) { _ in }
                    }
                }
            }
        }
    }
    
    private func getInitials(from name: String) -> String {
        let formatter = PersonNameComponentsFormatter()
        if let components = formatter.personNameComponents(from: name) {
            formatter.style = .abbreviated
            return formatter.string(from: components)
        }
        
        let words = name.split(separator: " ")
        if words.count > 1 {
            return String(words[0].prefix(1)) + String(words.last!.prefix(1))
        } else if !words.isEmpty {
            return String(words[0].prefix(1))
        } else {
            return "?"
        }
    }
}

// MARK: - Profile Name Section
struct ProfileNameSection: View {
    @ObservedObject var viewModel: ProfileViewModel
    
    var body: some View {
        if viewModel.isEditingName {
            HStack {
                TextField("Tên", text: $viewModel.newFullName)
                    .font(.headline)
                    .autocapitalization(.words)
                    .disableAutocorrection(true)
                    .foregroundColor(.black)
                
                Spacer()
                
                HStack(spacing: 10) {
                    Button(action: { viewModel.cancelNameEdit() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .frame(width: 44, height: 44)
                    }
                    
                    Button(action: {
                        viewModel.updateUserName { success in }
                    }) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .frame(width: 44, height: 44)
                    }
                }
            }
        } else {
            HStack {
                Text(viewModel.userFullName)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                
                Spacer()
                
                Button(action: {
                    viewModel.isEditingName = true
                    viewModel.newFullName = viewModel.userFullName
                }) {
                    Image(systemName: "pencil.circle")
                        .foregroundColor(.blue)
                        .frame(width: 44, height: 44)
                }
            }
            .background(Color.clear)
        }
    }
}

// MARK: - Profile Email Section
struct ProfileEmailSection: View {
    @ObservedObject var viewModel: ProfileViewModel
    
    var body: some View {
        HStack {
            Text(viewModel.userEmail)
                .font(.subheadline)
                .foregroundColor(.black.opacity(0.8))
        }
    }
}

// MARK: - Profile Background
struct ProfileBackgroundView: View {
    var body: some View {
        ZStack {
            Image("pink-yellow-plain")
                .resizable()
                .scaledToFill()
                .clipped()
            
            Color.black.opacity(0.1)
        }
    }
}
