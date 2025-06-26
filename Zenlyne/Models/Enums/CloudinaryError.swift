//
//  CloudinaryError.swift
//  Zenlyne
//
//  Created by admin on 26/6/25.
//

import Foundation

enum CloudinaryError: LocalizedError {
    case imageProcessingFailed
    case invalidURL
    case noDataReceived
    case uploadFailed(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .imageProcessingFailed:
            return "Failed to process image"
        case .invalidURL:
            return "Invalid upload URL"
        case .noDataReceived:
            return "No data received from server"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}
