//
//  AvatarView.swift
//  Zenlyne
//
//  Created by admin on 22/5/25.
//

import SwiftUI

struct AvatarView: View {
    let user: User?
    let size: CGFloat
    let showOnlineStatus: Bool
    
    @StateObject private var imageLoader = ImageLoader()
    
    init(user: User?, size: CGFloat = 50, showOnlineStatus: Bool = false) {
        self.user = user
        self.size = size
        self.showOnlineStatus = showOnlineStatus
    }
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: size, height: size)
            
            // Avatar content
            Group {
                if let image = imageLoader.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size - 4, height: size - 4)
                        .clipShape(Circle())
                } else {
                    Text(user?.initials ?? "?")
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundColor(.blue)
                }
            }
            
            // Online status indicator
            if showOnlineStatus, let user = user {
                Circle()
                    .fill(user.isOnline ? Color.green : Color.gray)
                    .frame(width: size * 0.25, height: size * 0.25)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .offset(x: size * 0.3, y: size * 0.3)
            }
        }
        .onAppear {
            if let avatarUrl = user?.profileImageUrl {
                imageLoader.loadImage(from: avatarUrl)
            }
        }
        .onChange(of: user?.profileImageUrl) { oldValue, newValue in
            if let url = newValue {
                imageLoader.loadImage(from: url)
            } else {
                imageLoader.image = nil
            }
        }
    }
}

// Image loader with caching
class ImageLoader: ObservableObject {
    @Published var image: UIImage?
    private var cache = NSCache<NSString, UIImage>()
    
    func loadImage(from urlString: String) {
        // Check cache first
        if let cachedImage = cache.object(forKey: urlString as NSString) {
            self.image = cachedImage
            return
        }
        
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data,
                  let image = UIImage(data: data),
                  error == nil else { return }
            
            // Cache the image
            self?.cache.setObject(image, forKey: urlString as NSString)
            
            DispatchQueue.main.async {
                self?.image = image
            }
        }.resume()
    }
}
