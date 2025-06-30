//
//  LocationDisplayView.swift
//  Zenlyne
//
//  Created by kou on 4/6/25.
//

import SwiftUI

struct LocationDisplayView: View {
    @ObservedObject var reverseGeocodingService: ReverseGeocodingService
    
    @State private var isExpanded = false
    @State private var showFullAddress = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainLocationDisplay
            
            if isExpanded && showFullAddress {
                fullAddressDisplay
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if reverseGeocodingService.currentLocationInfo != nil {
                    showFullAddress.toggle()
                    isExpanded = showFullAddress
                }
            }
        }
    }
    
    private var mainLocationDisplay: some View {
        HStack(spacing: 8) {
            // Location icon with loading state
            Group {
                if reverseGeocodingService.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle(tint: .primary))
                } else {
                    Image(systemName: "location.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
            .frame(width: 16, height: 16)
            
            // Location name
            VStack(alignment: .leading, spacing: 2) {
                if let locationInfo = reverseGeocodingService.currentLocationInfo {
                    Text(locationInfo.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    if showFullAddress {
                        Text("Nhấn để xem đầy đủ")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                } else if reverseGeocodingService.lastError != nil {
                    Text("Không xác định")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                } else if !reverseGeocodingService.isLoading {
                    Text("Di chuyển bản đồ")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            // Expansion indicator
            if reverseGeocodingService.currentLocationInfo != nil {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : 0))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private var fullAddressDisplay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
                .padding(.horizontal, 8)
            
            if let locationInfo = reverseGeocodingService.currentLocationInfo {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Địa chỉ đầy đủ")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Text(locationInfo.fullAddress)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Coordinates
                    Text("Tọa độ: \(String(format: "%.5f", locationInfo.coordinate.latitude)), \(String(format: "%.5f", locationInfo.coordinate.longitude))")
                        .font(.system(size: 10).monospaced())
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
    }
}

// MARK: - Compact Version for Limited Space
struct CompactLocationDisplayView: View {
    @ObservedObject var reverseGeocodingService: ReverseGeocodingService
    
    var body: some View {
        HStack(spacing: 6) {
            // Loading indicator or location icon
            if reverseGeocodingService.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else {
                Image(systemName: "location.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
            }
            
            // Location text
            if let locationInfo = reverseGeocodingService.currentLocationInfo {
                Text(locationInfo.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if !reverseGeocodingService.isLoading {
                Text("Vị trí")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.6))
                .backdrop(Color.black.opacity(0.1))
        )
        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Debug Info View (for development)
struct LocationDebugView: View {
    @ObservedObject var reverseGeocodingService: ReverseGeocodingService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Debug Info")
                .font(.caption.bold())
                .foregroundColor(.orange)
            
            Text("Cache size: \(reverseGeocodingService.cacheSize)")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text("Loading: \(reverseGeocodingService.isLoading)")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            if let error = reverseGeocodingService.lastError {
                Text("Error: \(error.localizedDescription)")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.yellow.opacity(0.1))
                .border(Color.orange, width: 1)
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        LocationDisplayView(reverseGeocodingService: ReverseGeocodingService())
        
        CompactLocationDisplayView(reverseGeocodingService: ReverseGeocodingService())
        
        LocationDebugView(reverseGeocodingService: ReverseGeocodingService())
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
