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
        let size: CGFloat = 70 // Marker size (slightly larger to accommodate previews)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        
        return renderer.image { ctx in
            // Create main circle
            let circleRect = CGRect(x: 5, y: 5, width: size-10, height: size-10)
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
            
            // Add subtle inner shadow
            ctx.cgContext.setShadow(
                offset: CGSize(width: 0, height: 1),
                blur: 3,
                color: UIColor.black.withAlphaComponent(0.2).cgColor
            )
            
            // For clusters with 2-4 friends, show mini avatars in a nice arrangement
            if count >= 2 && count <= 4 && !friendInitials.isEmpty {
                drawFriendPreviewAvatars(ctx: ctx, count: count, friendInitials: friendInitials, size: size)
            } else {
                // For larger clusters, just show the count
                let countText = "+\(count)"
                drawClusterCount(ctx: ctx, text: countText, size: size)
            }
            
            // Add expand indicator to suggest tapping
            drawExpandIndicator(ctx: ctx, size: size, isOnline: isOnline)
            
            // Draw online status indicator if any friends are online
            if isOnline {
                drawOnlineIndicator(ctx: ctx, size: size)
            }
        }
    }
    
    // Draw preview avatars for small clusters (2-4 friends)
    private static func drawFriendPreviewAvatars(
        ctx: UIGraphicsImageRendererContext,
        count: Int,
        friendInitials: [String],
        size: CGFloat
    ) {
        // Clear any shadow settings
        ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
        
        // Calculate positions based on count
        let positions: [[CGFloat]]
        let avatarSize: CGFloat
        
        switch count {
        case 2:
            // Two friends side by side
            avatarSize = size * 0.35
            positions = [
                [size/2 - avatarSize/1.5, size/2],
                [size/2 + avatarSize/1.5, size/2]
            ]
        case 3:
            // Three friends in a triangle
            avatarSize = size * 0.32
            positions = [
                [size/2, size/2 - avatarSize/1.2],
                [size/2 - avatarSize/1.2, size/2 + avatarSize/1.8],
                [size/2 + avatarSize/1.2, size/2 + avatarSize/1.8]
            ]
        case 4:
            // Four friends in a grid
            avatarSize = size * 0.28
            positions = [
                [size/2 - avatarSize/1.3, size/2 - avatarSize/1.3],
                [size/2 + avatarSize/1.3, size/2 - avatarSize/1.3],
                [size/2 - avatarSize/1.3, size/2 + avatarSize/1.3],
                [size/2 + avatarSize/1.3, size/2 + avatarSize/1.3]
            ]
        default:
            // Fallback (shouldn't happen)
            avatarSize = size * 0.3
            positions = []
        }
        
        // Draw avatar circles for available initials
        for i in 0..<min(count, friendInitials.count, positions.count) {
            let x = positions[i][0]
            let y = positions[i][1]
            
            // First draw a white circle as border
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(
                x: x - avatarSize/2 - 2,
                y: y - avatarSize/2 - 2,
                width: avatarSize + 4,
                height: avatarSize + 4
            ))
            
            // Then draw the colored avatar circle
            ctx.cgContext.setFillColor(UIColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 0.8).cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(
                x: x - avatarSize/2,
                y: y - avatarSize/2,
                width: avatarSize,
                height: avatarSize
            ))
            
            // Draw initial
            let initial = i < friendInitials.count ? String(friendInitials[i].prefix(1)) : "?"
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: avatarSize * 0.6, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            
            let attributedString = NSAttributedString(string: initial, attributes: attributes)
            
            // Position text in center of avatar
            let textRect = CGRect(
                x: x - avatarSize/2,
                y: y - avatarSize * 0.35,
                width: avatarSize,
                height: avatarSize * 0.7
            )
            
            attributedString.draw(in: textRect)
        }
    }
    
    // Draw the count number for larger clusters
    private static func drawClusterCount(
        ctx: UIGraphicsImageRendererContext,
        text: String,
        size: CGFloat
    ) {
        // Clear any shadow
        ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size * 0.35, weight: .bold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle
        ]
        
        // Position text in the center
        let textRect = CGRect(x: 5, y: (size - size * 0.4)/2, width: size - 10, height: size * 0.4)
        NSAttributedString(string: text, attributes: textAttributes)
            .draw(in: textRect)
    }
    
    // Draw expand indicator to suggest the cluster can be tapped
    private static func drawExpandIndicator(
        ctx: UIGraphicsImageRendererContext,
        size: CGFloat,
        isOnline: Bool
    ) {
        // Draw a small circle with a plus sign at the bottom right
        let expandSize: CGFloat = size * 0.2
        let expandX = size - expandSize/2 - 5
        let expandY = size - expandSize/2 - 5
        
        // White background circle
        ctx.cgContext.setFillColor(UIColor.white.cgColor)
        ctx.cgContext.fillEllipse(in: CGRect(
            x: expandX - expandSize/2,
            y: expandY - expandSize/2,
            width: expandSize,
            height: expandSize
        ))
        
        // Plus sign
        let plusColor = isOnline ? UIColor.orange : UIColor.gray
        ctx.cgContext.setStrokeColor(plusColor.cgColor)
        ctx.cgContext.setLineWidth(expandSize/6)
        
        // Horizontal line
        ctx.cgContext.move(to: CGPoint(x: expandX - expandSize/3, y: expandY))
        ctx.cgContext.addLine(to: CGPoint(x: expandX + expandSize/3, y: expandY))
        
        // Vertical line
        ctx.cgContext.move(to: CGPoint(x: expandX, y: expandY - expandSize/3))
        ctx.cgContext.addLine(to: CGPoint(x: expandX, y: expandY + expandSize/3))
        
        ctx.cgContext.strokePath()
    }
    
    // Draw online status indicator
    private static func drawOnlineIndicator(
        ctx: UIGraphicsImageRendererContext,
        size: CGFloat
    ) {
        let statusDotSize: CGFloat = size * 0.18
        let statusDotX = size - statusDotSize - 5
        let statusDotY = statusDotSize/2 + 5
        
        // Draw green dot with white border
        ctx.cgContext.setFillColor(UIColor.green.cgColor)
        ctx.cgContext.fillEllipse(in: CGRect(
            x: statusDotX - statusDotSize/2,
            y: statusDotY - statusDotSize/2,
            width: statusDotSize,
            height: statusDotSize
        ))
        
        ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
        ctx.cgContext.setLineWidth(statusDotSize/6)
        ctx.cgContext.strokeEllipse(in: CGRect(
            x: statusDotX - statusDotSize/2,
            y: statusDotY - statusDotSize/2,
            width: statusDotSize,
            height: statusDotSize
        ))
    }
    
    // Generate avatar texture for single friend markers
    static func generateAvatarTexture(initial: String, isOnline: Bool = false) -> UIImage {
        let size: CGFloat = 40
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        
        return renderer.image { ctx in
            // Background color changes based on online status
            let backgroundColor = isOnline ?
                UIColor(red: 0.0, green: 0.7, blue: 0.3, alpha: 0.7) :
                UIColor(red: 0.0, green: 0.4, blue: 0.9, alpha: 0.7)
            
            // Draw circle background
            ctx.cgContext.setFillColor(backgroundColor.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
            
            // Add white border
            ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
            ctx.cgContext.setLineWidth(2)
            ctx.cgContext.strokeEllipse(in: CGRect(x: 1, y: 1, width: size-2, height: size-2))
            
            // Draw initial
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size * 0.5, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            
            let attributedString = NSAttributedString(
                string: String(initial.prefix(1)),
                attributes: attributes
            )
            
            // Position text in center
            attributedString.draw(in: CGRect(
                x: 0,
                y: (size - size * 0.7)/2,
                width: size,
                height: size * 0.7
            ))
            
            // Add online/offline indicator
            if isOnline {
                let indicatorSize: CGFloat = size * 0.25
                ctx.cgContext.setFillColor(UIColor.green.cgColor)
                ctx.cgContext.fillEllipse(in: CGRect(
                    x: size - indicatorSize - 2,
                    y: 2,
                    width: indicatorSize,
                    height: indicatorSize
                ))
                
                ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
                ctx.cgContext.setLineWidth(1)
                ctx.cgContext.strokeEllipse(in: CGRect(
                    x: size - indicatorSize - 2,
                    y: 2,
                    width: indicatorSize,
                    height: indicatorSize
                ))
            }
        }
    }
}
