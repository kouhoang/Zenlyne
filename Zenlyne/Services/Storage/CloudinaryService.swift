//
//  CloudinaryService.swift
//  Zenlyne
//
//  Created by admin on 22/5/25.
//

import Foundation
import UIKit

class CloudinaryService {
    static let shared = CloudinaryService()
    
    // Replace with your actual Cloudinary configuration
    private let cloudName = "ddxbw0snt"
    private let uploadPreset = "Zenlyne"
    
    private init() {}
    
    func uploadImage(_ image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        // Resize and compress image
        guard let processedImage = processImage(image),
              let imageData = processedImage.jpegData(compressionQuality: 0.7) else {
            completion(.failure(CloudinaryError.imageProcessingFailed))
            return
        }
        
        // Create upload URL
        let uploadURL = "https://api.cloudinary.com/v1_1/\(cloudName)/image/upload"
        
        guard let url = URL(string: uploadURL) else {
            completion(.failure(CloudinaryError.invalidURL))
            return
        }
        
        // Create multipart form data
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add upload preset
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"upload_preset\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(uploadPreset)\r\n".data(using: .utf8)!)
        
        // Add image data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"avatar.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        // Perform upload
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(CloudinaryError.noDataReceived))
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]

                if let secureUrl = json?["secure_url"] as? String {
                    completion(.success(secureUrl))
                } else if let errorDict = json?["error"] as? [String: Any],
                          let errorMessage = errorDict["message"] as? String {
                    completion(.failure(CloudinaryError.uploadFailed(errorMessage)))
                } else {
                    completion(.failure(CloudinaryError.invalidResponse))
                }

            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    private func processImage(_ image: UIImage) -> UIImage? {
        // Resize to 256x256 pixels
        let targetSize = CGSize(width: 256, height: 256)
        
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: targetSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage
    }
}
