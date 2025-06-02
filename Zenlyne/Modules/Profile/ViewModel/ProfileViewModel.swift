//
//  ProfileViewModel.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import Foundation
import Firebase
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore
import SwiftUI
import Combine

class ProfileViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var state = ProfileState()
    @Published var newFullName: String = ""
    @Published var currentPassword: String = ""
    @Published var newPassword: String = ""
    @Published var confirmPassword: String = ""
    @Published var errorMessage: String = ""
    @Published var successMessage: String = ""
    
    // MARK: - Computed Properties
    var userFullName: String {
        get { state.userFullName }
        set { state.userFullName = newValue }
    }
    
    var userEmail: String {
        get { state.userEmail }
        set { state.userEmail = newValue }
    }
    
    var profileImage: UIImage? {
        get { state.profileImage }
        set { state.profileImage = newValue }
    }
    
    var isEditingName: Bool {
        get { state.isEditingName }
        set { state.isEditingName = newValue }
    }
    
    var isEditingPassword: Bool {
        get { state.isEditingPassword }
        set { state.isEditingPassword = newValue }
    }
    
    var isLoading: Bool {
        get { state.isLoading }
        set { state.isLoading = newValue }
    }
    
    // MARK: - Dependencies
    private let firebaseService: FirebaseServiceProtocol
    private let cloudinaryService: CloudinaryServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(firebaseService: FirebaseServiceProtocol = FirebaseService(),
         cloudinaryService: CloudinaryServiceProtocol = CloudinaryService.shared) {
        self.firebaseService = firebaseService
        self.cloudinaryService = cloudinaryService
        setupBindings()
        loadUserData()
    }
    
    // MARK: - Setup
    private func setupBindings() {
        // Clear messages after delay
        $errorMessage
            .filter { !$0.isEmpty }
            .delay(for: .seconds(3), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.errorMessage = ""
            }
            .store(in: &cancellables)
        
        $successMessage
            .filter { !$0.isEmpty }
            .delay(for: .seconds(3), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.successMessage = ""
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    func handle(_ event: ProfileEvent) {
        Task {
            await handleEvent(event)
        }
    }
    
    func loadUserData() {
        Task {
            await handleEvent(.loadUserData)
        }
    }
    
    func updateUserName(completion: @escaping (Bool) -> Void) {
        guard !newFullName.isEmpty else {
            errorMessage = "Tên không thể trống"
            completion(false)
            return
        }
        
        Task {
            await handleEvent(.updateName(newFullName))
            completion(errorMessage.isEmpty)
        }
    }
    
    func updatePassword(completion: @escaping (Bool) -> Void) {
        let request = PasswordUpdateRequest(
            currentPassword: currentPassword,
            newPassword: newPassword,
            confirmPassword: confirmPassword
        )
        
        guard request.isValid else {
            if newPassword.count < 6 {
                errorMessage = "Mật khẩu phải tối thiểu 6 ký tự"
            } else if newPassword != confirmPassword {
                errorMessage = "Mật khẩu không khớp"
            } else {
                errorMessage = "Vui lòng điền đầy đủ thông tin"
            }
            completion(false)
            return
        }
        
        Task {
            await handleEvent(.updatePassword(request))
            completion(errorMessage.isEmpty)
        }
    }
    
    func uploadProfileImage(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        Task {
            await handleEvent(.uploadProfileImage(image))
            completion(errorMessage.isEmpty)
        }
    }
    
    func cancelNameEdit() {
        handle(.cancelNameEdit)
    }
    
    func cancelPasswordEdit() {
        handle(.cancelPasswordEdit)
    }
    
    // MARK: - Private Event Handling
    private func handleEvent(_ event: ProfileEvent) async {
        switch event {
        case .loadUserData:
            await loadUserDataInternal()
            
        case .updateName(let name):
            await updateUserNameInternal(name)
            
        case .updatePassword(let request):
            await updatePasswordInternal(request)
            
        case .uploadProfileImage(let image):
            await uploadProfileImageInternal(image)
            
        case .cancelNameEdit:
            isEditingName = false
            newFullName = userFullName
            
        case .cancelPasswordEdit:
            isEditingPassword = false
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
        }
    }
    
    // MARK: - Internal Implementation
    func loadUserDataInternal() async {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        await MainActor.run {
            userEmail = currentUser.email ?? ""
        }
        
        do {
            let document = try await Firestore.firestore()
                .collection("users")
                .document(currentUser.uid)
                .getDocument()
            
            if document.exists, let data = document.data() {
                await MainActor.run {
                    userFullName = data["fullName"] as? String ?? ""
                    newFullName = userFullName
                }
                
                // Load profile image
                let avatarUrl = data["avatarUrl"] as? String ?? data["profileImageUrl"] as? String
                if let avatarUrl = avatarUrl, let url = URL(string: avatarUrl) {
                    await loadProfileImage(from: url)
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Lỗi tải dữ liệu người dùng: \(error.localizedDescription)"
            }
        }
    }

    private func updateUserNameInternal(_ name: String) async {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        await MainActor.run {
            isLoading = true
            errorMessage = ""
        }
        
        do {
            // Update display name in Firebase Auth
            let profileChangeRequest = currentUser.createProfileChangeRequest()
            profileChangeRequest.displayName = name
            try await profileChangeRequest.commitChanges()
            
            // Update name in Firestore
            try await Firestore.firestore()
                .collection("users")
                .document(currentUser.uid)
                .updateData(["fullName": name])
            
            await MainActor.run {
                userFullName = name
                isEditingName = false
                successMessage = "Đã cập nhật tên thành công"
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Lỗi cập nhật tên: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isLoading = false
        }
    }

    private func updatePasswordInternal(_ request: PasswordUpdateRequest) async {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        await MainActor.run {
            isLoading = true
            errorMessage = ""
        }
        
        do {
            // Reauthenticate user with current password
            let credential = EmailAuthProvider.credential(
                withEmail: userEmail,
                password: request.currentPassword
            )
            
            try await currentUser.reauthenticate(with: credential)
            
            // Update password
            try await currentUser.updatePassword(to: request.newPassword)
            
            // Reset fields
            await MainActor.run {
                isEditingPassword = false
                currentPassword = ""
                newPassword = ""
                confirmPassword = ""
                successMessage = "Đã cập nhật mật khẩu thành công"
            }
            
        } catch {
            await MainActor.run {
                if error.localizedDescription.contains("wrong-password") ||
                   error.localizedDescription.contains("invalid-credential") {
                    errorMessage = "Mật khẩu hiện tại không chính xác"
                } else {
                    errorMessage = "Lỗi cập nhật mật khẩu: \(error.localizedDescription)"
                }
            }
        }
        
        await MainActor.run {
            isLoading = false
        }
    }

    private func uploadProfileImageInternal(_ image: UIImage) async {
        guard let currentUser = Auth.auth().currentUser else {
            await MainActor.run {
                errorMessage = "Không có người dùng được xác thực"
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = ""
        }
        
        do {
            // Upload to Cloudinary
            let imageUrl = try await withCheckedThrowingContinuation { continuation in
                cloudinaryService.uploadImage(image) { result in
                    continuation.resume(with: result)
                }
            }
            
            // Update user profile in Firestore
            let updateData: [String: Any] = [
                "avatarUrl": imageUrl,
                "profileImageUrl": imageUrl,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            
            try await Firestore.firestore()
                .collection("users")
                .document(currentUser.uid)
                .updateData(updateData)
            
            await MainActor.run {
                profileImage = image
                successMessage = "Avatar được cập nhật thành công"
            }
            
            // Post notification
            await MainActor.run {
                NotificationCenter.default.post(
                    name: NSNotification.Name("AvatarUpdated"),
                    object: nil,
                    userInfo: [
                        "userId": currentUser.uid,
                        "avatarUrl": imageUrl
                    ]
                )
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Tải ảnh lên thất bại: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isLoading = false
        }
    }

    private func loadProfileImage(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                await MainActor.run {
                    profileImage = image
                }
            }
        } catch {
            print("DEBUG: Failed to load profile image: \(error.localizedDescription)")
        }
    }
}

// MARK: - CloudinaryService Protocol
protocol CloudinaryServiceProtocol {
    func uploadImage(_ image: UIImage, completion: @escaping (Result<String, Error>) -> Void)
}

extension CloudinaryService: CloudinaryServiceProtocol {}
