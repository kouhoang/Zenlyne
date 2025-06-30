//
//  FriendRequestRow.swift
//  Zenlyne
//
//  Created by admin on 26/6/25.
//

import SwiftUICore
import SwiftUI
import FirebaseFirestoreInternal

struct FriendRequestRow: View {
    let request: FriendRequest
    let isProcessing: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onTap: () -> Void
    
    @State private var senderName = ""
    @State private var senderImage: String?
    @State private var isLoadingSenderInfo = true
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar with loading state
                avatarSection
                
                // User info
                userInfoSection
                
                Spacer()
                
                // Action buttons
                actionButtonsSection
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6).opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            )
            .opacity(isProcessing ? 0.7 : 1.0)
            .scaleEffect(isProcessing ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isProcessing)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadSenderInfo()
        }
    }
    
    private var avatarSection: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 56, height: 56)
            
            if isLoadingSenderInfo {
                ProgressView()
                    .scaleEffect(0.7)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else if let senderImage = senderImage {
                AsyncImage(url: URL(string: senderImage)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Text(getInitials(from: senderName))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .frame(width: 52, height: 52)
                .clipShape(Circle())
            } else {
                Text(getInitials(from: senderName))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            
            // Online status indicator (if available)
            Circle()
                .fill(Color.green)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.black, lineWidth: 2)
                )
                .offset(x: 20, y: 20)
        }
    }
    
    private var userInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(senderName.isEmpty ? request.senderEmail : senderName)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(1)
            
            Text("Muốn kết bạn với bạn")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            if !senderName.isEmpty && senderName != request.senderEmail {
                Text(request.senderEmail)
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.8))
                    .lineLimit(1)
            }
            
            // Time stamp
            Text(timeAgoString(from: request.timestamp))
                .font(.caption2)
                .foregroundColor(.gray.opacity(0.6))
        }
    }
    
    private var actionButtonsSection: some View {
        HStack(spacing: 8) {
            // Decline button
            Button(action: onDecline) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 40, height: 40)
                    
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.gray)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isProcessing)
            
            // Accept button
            Button(action: onAccept) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.4, green: 0.9, blue: 0.8),
                                    Color(red: 0.6, green: 0.4, blue: 0.9),
                                    Color(red: 1.0, green: 0.7, blue: 0.4)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .opacity(isProcessing ? 0.6 : 1.0)
                        .frame(width: 40, height: 40)
                    
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isProcessing)
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadSenderInfo() {
        let db = Firestore.firestore()
        
        db.collection("users").document(request.senderId).getDocument { snapshot, error in
            DispatchQueue.main.async {
                self.isLoadingSenderInfo = false
                
                guard let data = snapshot?.data() else {
                    self.senderName = self.request.senderEmail
                    return
                }
                
                if let name = data["fullName"] as? String, !name.isEmpty {
                    self.senderName = name
                } else {
                    self.senderName = self.request.senderEmail
                }
                
                if let imageUrl = data["profileImageUrl"] as? String, !imageUrl.isEmpty {
                    self.senderImage = imageUrl
                }
            }
        }
    }
    
    private func getInitials(from name: String) -> String {
        if name.isEmpty {
            return "?"
        }
        
        let formatter = PersonNameComponentsFormatter()
        if let components = formatter.personNameComponents(from: name) {
            formatter.style = .abbreviated
            let initials = formatter.string(from: components)
            return initials.isEmpty ? String(name.prefix(1)).uppercased() : initials
        }
        
        return String(name.prefix(1)).uppercased()
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
