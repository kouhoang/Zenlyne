//
//  ClusterMarkerGenerator.swift
//  Zenlyne
//
//  Created by admin on 20/5/25.
//

import UIKit
import MapboxMaps

class ClusterMarkerGenerator {
    // Generate a marker image for a cluster of friends
    static func generateClusterMarker(
        count: Int,
        friendInitials: [String] = [],
        isOnline: Bool = true
    ) -> UIImage {
        let size: CGFloat = 64 // Marker size
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        
        return renderer.image { ctx in
            // Create main circle
            let circleRect = CGRect(x: 0, y: 0, width: size, height: size)
            let circlePath = UIBezierPath(ovalIn: circleRect)
            
            // Fill background with gradient
            let colors: [CGColor]
            if isOnline {
                // Orange gradient for online clusters
                colors = [
                    UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 0.9).cgColor,
                    UIColor(red: 0.9, green: 0.4, blue: 0.0, alpha: 0.9).cgColor
                ]
            } else {
                // Gray gradient for offline clusters
                colors = [
                    UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 0.9).cgColor,
                    UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 0.9).cgColor
                ]
            }
            
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0.0, 1.0]
            )!
            
            ctx.cgContext.addPath(circlePath.cgPath)
            ctx.cgContext.clip()
            
            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: size/2, y: size/2),
                startRadius: 0,
                endCenter: CGPoint(x: size/2, y: size/2),
                endRadius: size/2,
                options: []
            )
            
            // Draw a white border
            ctx.cgContext.resetClip()
            ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
            ctx.cgContext.setLineWidth(3)
            ctx.cgContext.addPath(circlePath.cgPath)
            ctx.cgContext.strokePath()
            
            // Draw count text
            let countText = "+\(count)"
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            
            // Position text in the center of the circle
            let textRect = CGRect(x: 0, y: (size - 30)/2, width: size, height: 30)
            NSAttributedString(string: countText, attributes: textAttributes)
                .draw(in: textRect)
            
            // Add subtle drop shadow
            ctx.cgContext.setShadow(
                offset: CGSize(width: 0, height: 2),
                blur: 4,
                color: UIColor.black.withAlphaComponent(0.3).cgColor
            )
            
            // Optional: Draw online status indicator
            if isOnline {
                let statusDotSize: CGFloat = 12
                let statusDotX = size - statusDotSize - 4
                let statusDotY = 4 + statusDotSize/2
                
                ctx.cgContext.setFillColor(UIColor.green.cgColor)
                ctx.cgContext.fillEllipse(in: CGRect(
                    x: statusDotX - statusDotSize/2,
                    y: statusDotY - statusDotSize/2,
                    width: statusDotSize,
                    height: statusDotSize
                ))
                
                // Add white border to status dot
                ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
                ctx.cgContext.setLineWidth(2.0)
                ctx.cgContext.strokeEllipse(in: CGRect(
                    x: statusDotX - statusDotSize/2,
                    y: statusDotY - statusDotSize/2,
                    width: statusDotSize,
                    height: statusDotSize
                ))
            }
        }
    }
    
    // Optional: Create avatar placeholders method
    static func generateInitialsTexture(initial: String, backgroundColor: UIColor = UIColor(red: 0.0, green: 0.4, blue: 0.9, alpha: 0.5)) -> UIImage {
        let size: CGFloat = 30
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        
        return renderer.image { ctx in
            // Draw circle background
            ctx.cgContext.setFillColor(backgroundColor.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
            
            // Draw text
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            
            let textRect = CGRect(x: 0, y: (size - 20)/2, width: size, height: 20)
            NSAttributedString(string: initial, attributes: attributes)
                .draw(in: textRect)
        }
    }
}
