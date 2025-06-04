//
//  ClusterMarkerGenerator.swift
//  Zenlyne
//
//  Created by admin on 20/5/25.
//

import UIKit
import MapboxMaps
import Combine

// MARK: - Cluster Marker Styles
enum ClusterMarkerStyle {
    case standard
    case minimal
    case detailed
    case modern
    case glassmorphism
    case avatar
    
    var baseSize: CGFloat {
        switch self {
        case .standard, .minimal:
            return 60
        case .detailed, .modern:
            return 70
        case .glassmorphism:
            return 65
        case .avatar:
            return 75
        }
    }
}

// MARK: - Cluster Theme
struct ClusterTheme {
    let onlineColors: [UIColor]
    let offlineColors: [UIColor]
    let borderColor: UIColor
    let textColor: UIColor
    let shadowColor: UIColor
    let shadowOpacity: Float
    let shadowRadius: CGFloat
    
    static let `default` = ClusterTheme(
        onlineColors: [
            UIColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 0.9),
            UIColor(red: 0.0, green: 0.6, blue: 0.0, alpha: 0.9)
        ],
        offlineColors: [
            UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 0.9),
            UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 0.9)
        ],
        borderColor: .white,
        textColor: .white,
        shadowColor: .black,
        shadowOpacity: 0.3,
        shadowRadius: 4.0
    )
    
    static let modern = ClusterTheme(
        onlineColors: [
            UIColor(red: 0.0, green: 0.7, blue: 1.0, alpha: 0.95),
            UIColor(red: 0.0, green: 0.5, blue: 0.8, alpha: 0.95)
        ],
        offlineColors: [
            UIColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 0.9),
            UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.9)
        ],
        borderColor: UIColor(white: 1.0, alpha: 0.8),
        textColor: .white,
        shadowColor: .black,
        shadowOpacity: 0.2,
        shadowRadius: 6.0
    )
    
    static let avatar = ClusterTheme(
        onlineColors: [
            UIColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 0.95),
            UIColor(red: 0.1, green: 0.7, blue: 0.3, alpha: 0.95)
        ],
        offlineColors: [
            UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 0.9),
            UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.9)
        ],
        borderColor: .white,
        textColor: .white,
        shadowColor: .black,
        shadowOpacity: 0.25,
        shadowRadius: 8.0
    )
}

// MARK: - Cluster Marker Cache
class ClusterMarkerCache {
    private var cache: [String: UIImage] = [:]
    private let maxCacheSize = 150
    private var accessOrder: [String] = []
    
    func get(key: String) -> UIImage? {
        if let image = cache[key] {
            // Move to end (most recently used)
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
            }
            accessOrder.append(key)
            return image
        }
        return nil
    }
    
    func set(key: String, image: UIImage) {
        // Remove if exists
        if cache[key] != nil {
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
            }
        }
        
        // Add new
        cache[key] = image
        accessOrder.append(key)
        
        // Trim cache if needed
        while cache.count > maxCacheSize && !accessOrder.isEmpty {
            let oldestKey = accessOrder.removeFirst()
            cache.removeValue(forKey: oldestKey)
        }
    }
    
    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
    }
    
    var currentSize: Int {
        return cache.count
    }
}

class ClusterMarkerGenerator: ObservableObject {
    
    // MARK: - Published Properties
    @Published var currentTheme: ClusterTheme = .default
    @Published var currentStyle: ClusterMarkerStyle = .avatar
    @Published private(set) var cacheHitRate: Double = 0.0
    
    // MARK: - Private Properties
    private let cache = ClusterMarkerCache()
    private var cacheHits: Int = 0
    private var cacheRequests: Int = 0
    private var cancellables = Set<AnyCancellable>()
    
    // Performance monitoring
    private let performanceSubject = CurrentValueSubject<PerformanceMetrics, Never>(PerformanceMetrics())
    
    struct PerformanceMetrics {
        let cacheSize: Int
        let hitRate: Double
        let totalGenerations: Int
        let averageGenerationTime: Double
        
        init() {
            self.cacheSize = 0
            self.hitRate = 0.0
            self.totalGenerations = 0
            self.averageGenerationTime = 0.0
        }
        
        init(cacheSize: Int, hitRate: Double, totalGenerations: Int, averageGenerationTime: Double) {
            self.cacheSize = cacheSize
            self.hitRate = hitRate
            self.totalGenerations = totalGenerations
            self.averageGenerationTime = averageGenerationTime
        }
    }
    
    // MARK: - Combine Publishers
    var performanceMetricsPublisher: AnyPublisher<PerformanceMetrics, Never> {
        performanceSubject
            .removeDuplicates { lhs, rhs in
                lhs.cacheSize == rhs.cacheSize && abs(lhs.hitRate - rhs.hitRate) < 0.01
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    init() {
        setupPerformanceMonitoring()
    }
    
    private func setupPerformanceMonitoring() {
        Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updatePerformanceMetrics()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    static func generateClusterMarker(
        count: Int,
        friendInitials: [String] = [],
        isOnline: Bool = false
    ) -> UIImage {
        return ClusterMarkerGenerator.shared.generateMarker(
            count: count,
            friendInitials: friendInitials,
            isOnline: isOnline,
            style: .avatar,
            theme: .avatar
        )
    }
    
    static func generateAvatarClusterMarker(
        count: Int,
        friendInitials: [String] = [],
        isOnline: Bool = false,
        primaryAvatarImage: UIImage? = nil
    ) -> UIImage {
        return ClusterMarkerGenerator.shared.generateAvatarStyleMarker(
            count: count,
            friendInitials: friendInitials,
            isOnline: isOnline,
            primaryAvatarImage: primaryAvatarImage
        )
    }
    
    // MARK: - Enhanced Methods
    
    static let shared = ClusterMarkerGenerator()
    
    func generateMarker(
        count: Int,
        friendInitials: [String] = [],
        isOnline: Bool = false,
        style: ClusterMarkerStyle? = nil,
        theme: ClusterTheme? = nil
    ) -> UIImage {
        let actualStyle = style ?? currentStyle
        let actualTheme = theme ?? currentTheme
        
        // Generate cache key
        let cacheKey = generateCacheKey(
            count: count,
            friendInitials: friendInitials,
            isOnline: isOnline,
            style: actualStyle,
            theme: actualTheme
        )
        
        cacheRequests += 1
        
        // Check cache first
        if let cachedImage = cache.get(key: cacheKey) {
            cacheHits += 1
            updateCacheHitRate()
            return cachedImage
        }
        
        // Generate new marker
        let startTime = CFAbsoluteTimeGetCurrent()
        let image = generateMarkerImage(
            count: count,
            friendInitials: friendInitials,
            isOnline: isOnline,
            style: actualStyle,
            theme: actualTheme
        )
        let generationTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // Cache the result
        cache.set(key: cacheKey, image: image)
        
        // Update performance metrics
        updatePerformanceMetrics(generationTime: generationTime)
        
        return image
    }
    
    func generateAvatarStyleMarker(
        count: Int,
        friendInitials: [String] = [],
        isOnline: Bool = false,
        primaryAvatarImage: UIImage? = nil
    ) -> UIImage {
        let size: CGFloat = 75
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        
        return renderer.image { ctx in
            let rectangle = CGRect(x: 0, y: 0, width: size, height: size)
            
            // Draw shadow
            ctx.cgContext.setShadow(
                offset: CGSize(width: 0, height: 3),
                blur: 8.0,
                color: UIColor.black.withAlphaComponent(0.25).cgColor
            )
            
            if count <= 4 && !friendInitials.isEmpty {
                // Draw multiple small avatar circles for small clusters
                drawMultipleAvatarCircles(
                    ctx: ctx,
                    count: count,
                    friendInitials: friendInitials,
                    isOnline: isOnline,
                    size: size,
                    primaryImage: primaryAvatarImage
                )
            } else {
                // Draw single large circle with count for larger clusters
                drawLargeClusterCircle(
                    ctx: ctx,
                    count: count,
                    isOnline: isOnline,
                    size: size,
                    primaryImage: primaryAvatarImage
                )
            }
        }
    }
    
    // MARK: - Private Generation Methods
    
    private func generateMarkerImage(
        count: Int,
        friendInitials: [String],
        isOnline: Bool,
        style: ClusterMarkerStyle,
        theme: ClusterTheme
    ) -> UIImage {
        let size = style.baseSize
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        
        return renderer.image { ctx in
            switch style {
            case .avatar:
                drawAvatarStyleMarker(ctx: ctx, count: count, friendInitials: friendInitials, isOnline: isOnline, theme: theme, size: size)
            case .standard:
                drawStandardMarker(ctx: ctx, count: count, friendInitials: friendInitials, isOnline: isOnline, theme: theme, size: size)
            case .minimal:
                drawMinimalMarker(ctx: ctx, count: count, isOnline: isOnline, theme: theme, size: size)
            case .detailed:
                drawDetailedMarker(ctx: ctx, count: count, friendInitials: friendInitials, isOnline: isOnline, theme: theme, size: size)
            case .modern:
                drawModernMarker(ctx: ctx, count: count, friendInitials: friendInitials, isOnline: isOnline, theme: theme, size: size)
            case .glassmorphism:
                drawGlassmorphismMarker(ctx: ctx, count: count, isOnline: isOnline, theme: theme, size: size)
            }
        }
    }
    
    private func drawAvatarStyleMarker(
        ctx: UIGraphicsImageRendererContext,
        count: Int,
        friendInitials: [String],
        isOnline: Bool,
        theme: ClusterTheme,
        size: CGFloat
    ) {
        let rectangle = CGRect(x: 0, y: 0, width: size, height: size)
        
        // Draw shadow
        ctx.cgContext.setShadow(
            offset: CGSize(width: 0, height: 3),
            blur: theme.shadowRadius,
            color: theme.shadowColor.withAlphaComponent(CGFloat(theme.shadowOpacity)).cgColor
        )
        
        if count <= 3 && !friendInitials.isEmpty {
            // Draw overlapping avatar circles for small clusters
            drawOverlappingAvatarCircles(
                ctx: ctx,
                count: count,
                friendInitials: friendInitials,
                isOnline: isOnline,
                size: size,
                theme: theme
            )
        } else {
            // Draw single avatar-style circle with count for larger clusters
            drawSingleAvatarCircle(
                ctx: ctx,
                count: count,
                isOnline: isOnline,
                size: size,
                theme: theme
            )
        }
    }
    
    private func drawOverlappingAvatarCircles(
        ctx: UIGraphicsImageRendererContext,
        count: Int,
        friendInitials: [String],
        isOnline: Bool,
        size: CGFloat,
        theme: ClusterTheme
    ) {
        let circleSize: CGFloat = size * 0.6
        let positions = calculateOverlapPositions(count: count, containerSize: size, circleSize: circleSize)
        
        for (index, initial) in friendInitials.prefix(count).enumerated() {
            guard index < positions.count else { break }
            
            let position = positions[index]
            let circleRect = CGRect(
                x: position.x - circleSize/2,
                y: position.y - circleSize/2,
                width: circleSize,
                height: circleSize
            )
            
            // Draw individual avatar circle
            drawSingleAvatarAtPosition(
                ctx: ctx,
                rect: circleRect,
                initial: String(initial.prefix(1)),
                isOnline: isOnline,
                theme: theme,
                zIndex: index
            )
        }
        
        // Add cluster indicator
        if count > 1 {
            drawClusterIndicator(ctx: ctx, count: count, size: size, isOnline: isOnline)
        }
    }
    
    private func drawSingleAvatarAtPosition(
        ctx: UIGraphicsImageRendererContext,
        rect: CGRect,
        initial: String,
        isOnline: Bool,
        theme: ClusterTheme,
        zIndex: Int
    ) {
        // Apply clipping for circle
        let path = UIBezierPath(ovalIn: rect)
        ctx.cgContext.addPath(path.cgPath)
        ctx.cgContext.clip()
        
        // Draw gradient background
        let colors = isOnline ? theme.onlineColors : theme.offlineColors
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors.map { $0.cgColor } as CFArray,
            locations: colors.count == 1 ? [0.0] : [0.0, 1.0]
        )!
        
        ctx.cgContext.drawLinearGradient(
            gradient,
            start: rect.origin,
            end: CGPoint(x: rect.maxX, y: rect.maxY),
            options: []
        )
        
        // Reset clipping
        ctx.cgContext.resetClip()
        
        // Draw border with depth effect
        let borderWidth: CGFloat = 3.0
        let borderRect = rect.insetBy(dx: borderWidth/2, dy: borderWidth/2)
        
        // Outer border (white)
        ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
        ctx.cgContext.setLineWidth(borderWidth)
        ctx.cgContext.strokeEllipse(in: borderRect)
        
        // Inner border (status color)
        let innerBorderRect = rect.insetBy(dx: borderWidth + 1, dy: borderWidth + 1)
        let statusColor = isOnline ? UIColor.systemGreen : UIColor.systemGray
        ctx.cgContext.setStrokeColor(statusColor.withAlphaComponent(0.7).cgColor)
        ctx.cgContext.setLineWidth(1.5)
        ctx.cgContext.strokeEllipse(in: innerBorderRect)
        
        // Draw initial
        let fontSize = rect.width * 0.35
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: theme.textColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let attributedString = NSAttributedString(string: initial, attributes: attributes)
        let textRect = CGRect(
            x: rect.minX,
            y: rect.midY - fontSize/2,
            width: rect.width,
            height: fontSize
        )
        
        attributedString.draw(in: textRect)
    }
    
    private func drawSingleAvatarCircle(
        ctx: UIGraphicsImageRendererContext,
        count: Int,
        isOnline: Bool,
        size: CGFloat,
        theme: ClusterTheme
    ) {
        let rectangle = CGRect(x: 0, y: 0, width: size, height: size)
        
        // Apply clipping for circle
        let path = UIBezierPath(ovalIn: rectangle)
        ctx.cgContext.addPath(path.cgPath)
        ctx.cgContext.clip()
        
        // Draw gradient background
        let colors = isOnline ? theme.onlineColors : theme.offlineColors
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors.map { $0.cgColor } as CFArray,
            locations: colors.count == 1 ? [0.0] : [0.0, 1.0]
        )!
        
        ctx.cgContext.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: size/2, y: size/2),
            startRadius: 0,
            endCenter: CGPoint(x: size/2, y: size/2),
            endRadius: size/2,
            options: []
        )
        
        // Reset clipping
        ctx.cgContext.resetClip()
        
        // Draw borders
        let borderWidth: CGFloat = 4.0
        
        // Outer border (white)
        ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
        ctx.cgContext.setLineWidth(borderWidth)
        ctx.cgContext.strokeEllipse(in: rectangle.insetBy(dx: borderWidth/2, dy: borderWidth/2))
        
        // Status border
        let statusColor = isOnline ? UIColor.systemGreen : UIColor.systemGray
        ctx.cgContext.setStrokeColor(statusColor.cgColor)
        ctx.cgContext.setLineWidth(2.0)
        ctx.cgContext.strokeEllipse(in: rectangle.insetBy(dx: borderWidth + 1, dy: borderWidth + 1))
        
        // Draw count
        drawCountText(ctx: ctx, count: count, size: size, textColor: theme.textColor)
        
        // Add expansion indicator
        drawExpansionIndicator(ctx: ctx, size: size, isOnline: isOnline)
    }
    
    private func drawMultipleAvatarCircles(
        ctx: UIGraphicsImageRendererContext,
        count: Int,
        friendInitials: [String],
        isOnline: Bool,
        size: CGFloat,
        primaryImage: UIImage?
    ) {
        let circleSize: CGFloat = size * 0.5
        let positions = calculateStackedPositions(count: count, containerSize: size, circleSize: circleSize)
        
        for (index, initial) in friendInitials.prefix(count).enumerated() {
            guard index < positions.count else { break }
            
            let position = positions[index]
            let circleRect = CGRect(
                x: position.x - circleSize/2,
                y: position.y - circleSize/2,
                width: circleSize,
                height: circleSize
            )
            
            // Draw circle with depth
            drawAvatarCircleWithDepth(
                ctx: ctx,
                rect: circleRect,
                initial: String(initial.prefix(1)),
                isOnline: isOnline,
                index: index,
                avatarImage: index == 0 ? primaryImage : nil
            )
        }
    }
    
    private func drawLargeClusterCircle(
        ctx: UIGraphicsImageRendererContext,
        count: Int,
        isOnline: Bool,
        size: CGFloat,
        primaryImage: UIImage?
    ) {
        let rectangle = CGRect(x: 0, y: 0, width: size, height: size)
        
        // Draw main circle with avatar or gradient
        if let avatarImage = primaryImage {
            // Clip to circle
            let path = UIBezierPath(ovalIn: rectangle)
            ctx.cgContext.addPath(path.cgPath)
            ctx.cgContext.clip()
            
            // Draw avatar
            avatarImage.draw(in: rectangle)
            
            // Draw overlay
            let overlayColor = isOnline ?
                UIColor.systemGreen.withAlphaComponent(0.3) :
                UIColor.systemGray.withAlphaComponent(0.3)
            ctx.cgContext.setFillColor(overlayColor.cgColor)
            ctx.cgContext.fillEllipse(in: rectangle)
            
            ctx.cgContext.resetClip()
        } else {
            // Draw gradient background
            let colors = isOnline ? [
                UIColor.systemGreen.cgColor,
                UIColor.systemGreen.withAlphaComponent(0.8).cgColor
            ] : [
                UIColor.systemGray.cgColor,
                UIColor.systemGray.withAlphaComponent(0.8).cgColor
            ]
            
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0.0, 1.0]
            )!
            
            let path = UIBezierPath(ovalIn: rectangle)
            ctx.cgContext.addPath(path.cgPath)
            ctx.cgContext.clip()
            
            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: size/2, y: size/2),
                startRadius: 0,
                endCenter: CGPoint(x: size/2, y: size/2),
                endRadius: size/2,
                options: []
            )
            
            ctx.cgContext.resetClip()
        }
        
        // Draw borders
        ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
        ctx.cgContext.setLineWidth(4.0)
        ctx.cgContext.strokeEllipse(in: rectangle.insetBy(dx: 2, dy: 2))
        
        // Draw count badge
        drawCountBadge(ctx: ctx, count: count, size: size)
    }
    
    private func drawAvatarCircleWithDepth(
        ctx: UIGraphicsImageRendererContext,
        rect: CGRect,
        initial: String,
        isOnline: Bool,
        index: Int,
        avatarImage: UIImage?
    ) {
        // Draw shadow for depth
        ctx.cgContext.setShadow(
            offset: CGSize(width: 1, height: 2),
            blur: 3.0,
            color: UIColor.black.withAlphaComponent(0.3).cgColor
        )
        
        // Draw circle
        if let image = avatarImage {
            let path = UIBezierPath(ovalIn: rect)
            ctx.cgContext.addPath(path.cgPath)
            ctx.cgContext.clip()
            
            image.draw(in: rect)
            ctx.cgContext.resetClip()
        } else {
            // Gradient background
            let colors = isOnline ? [
                UIColor.systemBlue.cgColor,
                UIColor.systemBlue.withAlphaComponent(0.8).cgColor
            ] : [
                UIColor.systemGray.cgColor,
                UIColor.systemGray.withAlphaComponent(0.8).cgColor
            ]
            
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0.0, 1.0]
            )!
            
            ctx.cgContext.fillEllipse(in: rect)
        }
        
        ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
        
        // Draw border
        ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
        ctx.cgContext.setLineWidth(2.0)
        ctx.cgContext.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
        
        // Draw initial if no image
        if avatarImage == nil {
            let fontSize = rect.width * 0.4
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            
            let attributedString = NSAttributedString(string: initial, attributes: attributes)
            let textRect = CGRect(
                x: rect.minX,
                y: rect.midY - fontSize/2,
                width: rect.width,
                height: fontSize
            )
            
            attributedString.draw(in: textRect)
        }
    }
    
    private func drawCountBadge(ctx: UIGraphicsImageRendererContext, count: Int, size: CGFloat) {
        let badgeSize: CGFloat = size * 0.35
        let badgeRect = CGRect(
            x: size - badgeSize - 5,
            y: 5,
            width: badgeSize,
            height: badgeSize
        )
        
        // Draw badge background
        ctx.cgContext.setFillColor(UIColor.red.cgColor)
        ctx.cgContext.fillEllipse(in: badgeRect)
        
        // Draw badge border
        ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
        ctx.cgContext.setLineWidth(2.0)
        ctx.cgContext.strokeEllipse(in: badgeRect.insetBy(dx: 1, dy: 1))
        
        // Draw count text
        let countText = count > 99 ? "99+" : "\(count)"
        let fontSize = badgeSize * 0.5
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle
        ]
        
        let attributedString = NSAttributedString(string: countText, attributes: attributes)
        let textRect = CGRect(
            x: badgeRect.minX,
            y: badgeRect.midY - fontSize/2,
            width: badgeRect.width,
            height: fontSize
        )
        
        attributedString.draw(in: textRect)
    }
    
    // MARK: - Position Calculation Helpers
    
    private func calculateOverlapPositions(count: Int, containerSize: CGFloat, circleSize: CGFloat) -> [CGPoint] {
        let center = CGPoint(x: containerSize/2, y: containerSize/2)
        let overlap: CGFloat = circleSize * 0.3 // 30% overlap
        
        switch count {
        case 1:
            return [center]
        case 2:
            let offset = (circleSize - overlap) / 2
            return [
                CGPoint(x: center.x - offset, y: center.y),
                CGPoint(x: center.x + offset, y: center.y)
            ]
        case 3:
            let radius = (circleSize - overlap) / 2
            return [
                CGPoint(x: center.x, y: center.y - radius),
                CGPoint(x: center.x - radius * 0.866, y: center.y + radius * 0.5),
                CGPoint(x: center.x + radius * 0.866, y: center.y + radius * 0.5)
            ]
        default:
            return [center]
        }
    }
    
    private func calculateStackedPositions(count: Int, containerSize: CGFloat, circleSize: CGFloat) -> [CGPoint] {
        let center = CGPoint(x: containerSize/2, y: containerSize/2)
        let stackOffset: CGFloat = circleSize * 0.25
        
        switch count {
        case 1:
            return [center]
        case 2:
            return [
                CGPoint(x: center.x - stackOffset, y: center.y - stackOffset),
                CGPoint(x: center.x + stackOffset, y: center.y + stackOffset)
            ]
        case 3:
            return [
                CGPoint(x: center.x - stackOffset, y: center.y - stackOffset),
                CGPoint(x: center.x + stackOffset, y: center.y - stackOffset),
                CGPoint(x: center.x, y: center.y + stackOffset)
            ]
        case 4:
            return [
                CGPoint(x: center.x - stackOffset, y: center.y - stackOffset),
                CGPoint(x: center.x + stackOffset, y: center.y - stackOffset),
                CGPoint(x: center.x - stackOffset, y: center.y + stackOffset),
                CGPoint(x: center.x + stackOffset, y: center.y + stackOffset)
            ]
        default:
            return [center]
        }
    }
    
    // MARK: - Legacy Methods (for compatibility)
    
    private func drawStandardMarker(
        ctx: UIGraphicsImageRendererContext,
        count: Int,
        friendInitials: [String],
        isOnline: Bool,
        theme: ClusterTheme,
        size: CGFloat
    ) {
        let rectangle = CGRect(x: 0, y: 0, width: size, height: size)
        
        // Choose colors based on online status
        let colors = isOnline ? theme.onlineColors : theme.offlineColors
        
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors.map { $0.cgColor } as CFArray,
            locations: colors.count == 1 ? [0.0] : [0.0, 1.0]
        )!
        
        // Draw shadow
        if theme.shadowRadius > 0 {
            ctx.cgContext.setShadow(
                offset: CGSize(width: 0, height: 2),
                blur: theme.shadowRadius,
                color: theme.shadowColor.withAlphaComponent(CGFloat(theme.shadowOpacity)).cgColor
            )
        }
        
        // Draw circular background
        ctx.cgContext.addEllipse(in: rectangle)
        ctx.cgContext.clip()
        
        // Draw gradient
        ctx.cgContext.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: size, y: size),
            options: []
        )
        
        // Reset clipping and shadow
        ctx.cgContext.resetClip()
        ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
        
        // Draw border
        if theme.borderColor != .clear {
            ctx.cgContext.setStrokeColor(theme.borderColor.cgColor)
            ctx.cgContext.setLineWidth(3.0)
            ctx.cgContext.strokeEllipse(in: rectangle.insetBy(dx: 1.5, dy: 1.5))
        }
        
        // Draw count or initials
        if count <= 4 && !friendInitials.isEmpty {
            drawFriendInitials(ctx: ctx, initials: friendInitials, size: size, textColor: theme.textColor)
        } else {
            drawCountText(ctx: ctx, count: count, size: size, textColor: theme.textColor)
        }
        
        // Draw status indicator
        if isOnline {
            drawOnlineIndicator(ctx: ctx, size: size)
        }
    }
    
    private func drawMinimalMarker(
        ctx: UIGraphicsImageRendererContext,
        count: Int,
        isOnline: Bool,
        theme: ClusterTheme,
        size: CGFloat
    ) {
        let rectangle = CGRect(x: 0, y: 0, width: size, height: size)
        let colors = isOnline ? theme.onlineColors : theme.offlineColors
        
        // Simple filled circle
        ctx.cgContext.setFillColor(colors.first?.cgColor ?? UIColor.gray.cgColor)
        ctx.cgContext.fillEllipse(in: rectangle)
        
        // Count text only
        drawCountText(ctx: ctx, count: count, size: size, textColor: theme.textColor)
    }
    
    private func drawDetailedMarker(
        ctx: UIGraphicsImageRendererContext,
        count: Int,
        friendInitials: [String],
        isOnline: Bool,
        theme: ClusterTheme,
        size: CGFloat
    ) {
        // Similar to standard but with more visual elements
        drawStandardMarker(ctx: ctx, count: count, friendInitials: friendInitials, isOnline: isOnline, theme: theme, size: size)
        
        // Add additional ring
        let ringRect = CGRect(x: 5, y: 5, width: size - 10, height: size - 10)
        ctx.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
        ctx.cgContext.setLineWidth(1.0)
        ctx.cgContext.strokeEllipse(in: ringRect)
        
        // Add expansion indicator
        drawExpansionIndicator(ctx: ctx, size: size, isOnline: isOnline)
    }
    
    private func drawModernMarker(
        ctx: UIGraphicsImageRendererContext,
        count: Int,
        friendInitials: [String],
        isOnline: Bool,
        theme: ClusterTheme,
        size: CGFloat
    ) {
        let rectangle = CGRect(x: 0, y: 0, width: size, height: size)
        
        // Modern gradient with multiple stops
        let colors = isOnline ? theme.onlineColors : theme.offlineColors
        let extendedColors = colors + [colors.last?.withAlphaComponent(0.7) ?? UIColor.clear]
        
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: extendedColors.map { $0.cgColor } as CFArray,
            locations: [0.0, 0.6, 1.0]
        )!
        
        // Subtle shadow
        ctx.cgContext.setShadow(
            offset: CGSize(width: 0, height: 4),
            blur: 8.0,
            color: UIColor.black.withAlphaComponent(0.15).cgColor
        )
        
        // Draw main circle
        ctx.cgContext.addEllipse(in: rectangle)
        ctx.cgContext.clip()
        
        // Radial gradient from center
        ctx.cgContext.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: size/2, y: size/2),
            startRadius: 0,
            endCenter: CGPoint(x: size/2, y: size/2),
            endRadius: size/2,
            options: []
        )
        
        ctx.cgContext.resetClip()
        ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
        
        // Modern border
        ctx.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.6).cgColor)
        ctx.cgContext.setLineWidth(2.0)
        ctx.cgContext.strokeEllipse(in: rectangle.insetBy(dx: 1, dy: 1))
        
        // Content
        drawCountText(ctx: ctx, count: count, size: size, textColor: theme.textColor)
    }
    
    private func drawGlassmorphismMarker(
        ctx: UIGraphicsImageRendererContext,
        count: Int,
        isOnline: Bool,
        theme: ClusterTheme,
        size: CGFloat
    ) {
        let rectangle = CGRect(x: 0, y: 0, width: size, height: size)
        
        // Glassmorphism background
        let baseColor = isOnline ? UIColor.systemBlue : UIColor.systemGray
        ctx.cgContext.setFillColor(baseColor.withAlphaComponent(0.2).cgColor)
        ctx.cgContext.fillEllipse(in: rectangle)
        
        // Blur effect simulation (simplified)
        ctx.cgContext.setFillColor(UIColor.white.withAlphaComponent(0.1).cgColor)
        ctx.cgContext.fillEllipse(in: rectangle.insetBy(dx: 5, dy: 5))
        
        // Border
        ctx.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
        ctx.cgContext.setLineWidth(1.5)
        ctx.cgContext.strokeEllipse(in: rectangle.insetBy(dx: 0.75, dy: 0.75))
        
        // Count
        drawCountText(ctx: ctx, count: count, size: size, textColor: .white)
    }
    
    // MARK: - Helper Drawing Methods
    
    private func drawCountText(ctx: UIGraphicsImageRendererContext, count: Int, size: CGFloat, textColor: UIColor) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let fontSize = size * 0.35
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let countText = count > 99 ? "99+" : "\(count)"
        let attributedString = NSAttributedString(string: countText, attributes: attributes)
        
        let textRect = CGRect(x: 0, y: (size - fontSize * 1.2) / 2, width: size, height: fontSize * 1.2)
        attributedString.draw(in: textRect)
    }
    
    private func drawFriendInitials(ctx: UIGraphicsImageRendererContext, initials: [String], size: CGFloat, textColor: UIColor) {
        // For small clusters, show individual initials
        let positions = calculateInitialPositions(count: initials.count, size: size)
        let fontSize = size * 0.25
        
        for (index, initial) in initials.prefix(4).enumerated() {
            guard index < positions.count else { break }
            
            let position = positions[index]
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle
            ]
            
            let text = String(initial.prefix(1))
            let attributedString = NSAttributedString(string: text, attributes: attributes)
            
            let textRect = CGRect(
                x: position.x - fontSize/2,
                y: position.y - fontSize/2,
                width: fontSize,
                height: fontSize
            )
            
            attributedString.draw(in: textRect)
        }
    }
    
    private func calculateInitialPositions(count: Int, size: CGFloat) -> [CGPoint] {
        let center = CGPoint(x: size/2, y: size/2)
        let radius = size * 0.2
        
        var positions: [CGPoint] = []
        
        switch count {
        case 1:
            positions.append(center)
        case 2:
            positions.append(CGPoint(x: center.x - radius/2, y: center.y))
            positions.append(CGPoint(x: center.x + radius/2, y: center.y))
        case 3:
            let angle: CGFloat = 2 * .pi / 3
            for i in 0..<3 {
                let x = center.x + radius * cos(CGFloat(i) * angle - .pi/2)
                let y = center.y + radius * sin(CGFloat(i) * angle - .pi/2)
                positions.append(CGPoint(x: x, y: y))
            }
        case 4:
            let angle: CGFloat = .pi / 2
            for i in 0..<4 {
                let x = center.x + radius * cos(CGFloat(i) * angle)
                let y = center.y + radius * sin(CGFloat(i) * angle)
                positions.append(CGPoint(x: x, y: y))
            }
        default:
            positions.append(center)
        }
        
        return positions
    }
    
    private func drawOnlineIndicator(ctx: UIGraphicsImageRendererContext, size: CGFloat) {
        let dotSize: CGFloat = size * 0.18
        let dotX = size - dotSize - 4
        let dotY = 4 + dotSize/2
        
        ctx.cgContext.setFillColor(UIColor.green.cgColor)
        ctx.cgContext.fillEllipse(in: CGRect(
            x: dotX - dotSize/2,
            y: dotY - dotSize/2,
            width: dotSize,
            height: dotSize
        ))
        
        ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
        ctx.cgContext.setLineWidth(2.0)
        ctx.cgContext.strokeEllipse(in: CGRect(
            x: dotX - dotSize/2,
            y: dotY - dotSize/2,
            width: dotSize,
            height: dotSize
        ))
    }
    
    private func drawExpansionIndicator(ctx: UIGraphicsImageRendererContext, size: CGFloat, isOnline: Bool) {
        let expandSize: CGFloat = size * 0.15
        let expandX = size - expandSize - 6
        let expandY = size - expandSize - 6
        
        // Background circle
        ctx.cgContext.setFillColor(UIColor.white.cgColor)
        ctx.cgContext.fillEllipse(in: CGRect(
            x: expandX - expandSize/2,
            y: expandY - expandSize/2,
            width: expandSize,
            height: expandSize
        ))
        
        // Plus sign
        let lineColor = isOnline ? UIColor.systemBlue : UIColor.systemGray
        ctx.cgContext.setStrokeColor(lineColor.cgColor)
        ctx.cgContext.setLineWidth(expandSize/5)
        
        // Horizontal line
        ctx.cgContext.move(to: CGPoint(x: expandX - expandSize/3, y: expandY))
        ctx.cgContext.addLine(to: CGPoint(x: expandX + expandSize/3, y: expandY))
        
        // Vertical line
        ctx.cgContext.move(to: CGPoint(x: expandX, y: expandY - expandSize/3))
        ctx.cgContext.addLine(to: CGPoint(x: expandX, y: expandY + expandSize/3))
        
        ctx.cgContext.strokePath()
    }
    
    private func drawClusterIndicator(ctx: UIGraphicsImageRendererContext, count: Int, size: CGFloat, isOnline: Bool) {
        // Small indicator showing this is a cluster
        let indicatorSize: CGFloat = size * 0.25
        let indicatorRect = CGRect(
            x: size - indicatorSize - 3,
            y: 3,
            width: indicatorSize,
            height: indicatorSize
        )
        
        // Background
        ctx.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.7).cgColor)
        ctx.cgContext.fillEllipse(in: indicatorRect)
        
        // Border
        ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
        ctx.cgContext.setLineWidth(1.0)
        ctx.cgContext.strokeEllipse(in: indicatorRect.insetBy(dx: 0.5, dy: 0.5))
        
        // Count text
        let fontSize = indicatorSize * 0.6
        let countText = count > 9 ? "9+" : "\(count)"
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle
        ]
        
        let attributedString = NSAttributedString(string: countText, attributes: attributes)
        let textRect = CGRect(
            x: indicatorRect.minX,
            y: indicatorRect.midY - fontSize/2,
            width: indicatorRect.width,
            height: fontSize
        )
        
        attributedString.draw(in: textRect)
    }
    
    // MARK: - Cache Management
    
    private func generateCacheKey(
        count: Int,
        friendInitials: [String],
        isOnline: Bool,
        style: ClusterMarkerStyle,
        theme: ClusterTheme
    ) -> String {
        let initialsString = friendInitials.prefix(4).joined(separator: "")
        let themeHash = "\(theme.onlineColors.count)_\(theme.offlineColors.count)_\(isOnline)"
        return "\(count)_\(initialsString)_\(isOnline)_\(style)_\(themeHash)"
    }
    
    private func updateCacheHitRate() {
        DispatchQueue.main.async {
            self.cacheHitRate = self.cacheRequests > 0 ? Double(self.cacheHits) / Double(self.cacheRequests) : 0.0
        }
    }
    
    private func updatePerformanceMetrics(generationTime: Double = 0) {
        let metrics = PerformanceMetrics(
            cacheSize: cache.currentSize,
            hitRate: cacheHitRate,
            totalGenerations: cacheRequests - cacheHits,
            averageGenerationTime: generationTime
        )
        
        performanceSubject.send(metrics)
    }
    
    // MARK: - Public Utility Methods
    
    func clearCache() {
        cache.clear()
        cacheHits = 0
        cacheRequests = 0
        updateCacheHitRate()
        updatePerformanceMetrics()
    }
    
    func preloadCommonMarkers() {
        // Preload frequently used marker configurations
        let commonCounts = [2, 3, 4, 5, 8, 10, 15, 20]
        let states = [true, false] // online/offline
        
        for count in commonCounts {
            for isOnline in states {
                _ = generateMarker(count: count, isOnline: isOnline)
            }
        }
        
        print("DEBUG: Preloaded \(commonCounts.count * states.count) common markers")
    }
    
    func getCacheStatistics() -> (size: Int, hitRate: Double, requests: Int) {
        return (cache.currentSize, cacheHitRate, cacheRequests)
    }
}

// MARK: - Static Convenience Methods

extension ClusterMarkerGenerator {
    
    static func generateAvatarTexture(initial: String, isOnline: Bool = false) -> UIImage {
        let size: CGFloat = 40
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        
        return renderer.image { ctx in
            let backgroundColor = isOnline ?
                UIColor(red: 0.0, green: 0.7, blue: 0.3, alpha: 0.7) :
                UIColor(red: 0.0, green: 0.4, blue: 0.9, alpha: 0.7)
            
            ctx.cgContext.setFillColor(backgroundColor.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
            
            ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
            ctx.cgContext.setLineWidth(2)
            ctx.cgContext.strokeEllipse(in: CGRect(x: 1, y: 1, width: size-2, height: size-2))
            
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
            
            attributedString.draw(in: CGRect(
                x: 0,
                y: (size - size * 0.7)/2,
                width: size,
                height: size * 0.7
            ))
            
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
