//
//  ViewExtensions.swift
//  Zenlyne
//
//  Created by admin on 19/3/25.
//

import SwiftUI

// MARK: - AnyTransition Extensions
extension AnyTransition {
    static var bottomSlide: AnyTransition {
        AnyTransition.move(edge: .bottom).combined(with: .opacity)
    }
    
    static var topSlide: AnyTransition {
        AnyTransition.move(edge: .top).combined(with: .opacity)
    }
    
    static var leftSlide: AnyTransition {
        AnyTransition.move(edge: .leading).combined(with: .opacity)
    }
    
    static var rightSlide: AnyTransition {
        AnyTransition.move(edge: .trailing).combined(with: .opacity)
    }
    
    static var scaleAndFade: AnyTransition {
        AnyTransition.scale.combined(with: .opacity)
    }
    
    static var slideAndScale: AnyTransition {
        AnyTransition.move(edge: .bottom)
            .combined(with: .scale(scale: 0.8))
            .combined(with: .opacity)
    }
}

// MARK: - Animation Extensions
extension Animation {
    static var spring: Animation {
        Animation.spring(response: 0.35, dampingFraction: 0.8)
    }
    
    static var fastSpring: Animation {
        Animation.spring(response: 0.2, dampingFraction: 0.7)
    }
    
    static var slowSpring: Animation {
        Animation.spring(response: 0.6, dampingFraction: 0.9)
    }
    
    static var bouncy: Animation {
        Animation.spring(response: 0.4, dampingFraction: 0.6)
    }
    
    static var smooth: Animation {
        Animation.easeInOut(duration: 0.3)
    }
    
    static var quick: Animation {
        Animation.easeOut(duration: 0.15)
    }
}

// MARK: - View Modifiers
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct FloatingPanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
            )
    }
}

struct PulseEffect: ViewModifier {
    @State private var scale: CGFloat = 1.0
    let minScale: CGFloat
    let maxScale: CGFloat
    let duration: Double
    
    init(minScale: CGFloat = 0.95, maxScale: CGFloat = 1.05, duration: Double = 1.0) {
        self.minScale = minScale
        self.maxScale = maxScale
        self.duration = duration
    }
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    scale = maxScale
                }
            }
    }
}

struct ShakeEffect: ViewModifier {
    @State private var offset: CGFloat = 0
    let intensity: CGFloat
    let duration: Double
    
    init(intensity: CGFloat = 10, duration: Double = 0.1) {
        self.intensity = intensity
        self.duration = duration
    }
    
    func body(content: Content) -> some View {
        content
            .offset(x: offset)
    }
    
    func shake() {
        withAnimation(Animation.easeInOut(duration: duration).repeatCount(6, autoreverses: true)) {
            offset = intensity
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 6) {
            offset = 0
        }
    }
}

// MARK: - View Extensions
extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
    
    func floatingPanelStyle() -> some View {
        modifier(FloatingPanelStyle())
    }
    
    func pulseEffect(minScale: CGFloat = 0.95, maxScale: CGFloat = 1.05, duration: Double = 1.0) -> some View {
        modifier(PulseEffect(minScale: minScale, maxScale: maxScale, duration: duration))
    }
    
    func shakeEffect(intensity: CGFloat = 10, duration: Double = 0.1) -> some View {
        modifier(ShakeEffect(intensity: intensity, duration: duration))
    }
    
    /// Apply a conditional modifier
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    /// Apply a conditional modifier with else clause
    @ViewBuilder
    func `if`<TrueContent: View, FalseContent: View>(
        _ condition: Bool,
        if ifTransform: (Self) -> TrueContent,
        else elseTransform: (Self) -> FalseContent
    ) -> some View {
        if condition {
            ifTransform(self)
        } else {
            elseTransform(self)
        }
    }
    
    /// Hide view conditionally
    @ViewBuilder
    func hidden(_ shouldHide: Bool) -> some View {
        if shouldHide {
            self.hidden()
        } else {
            self
        }
    }
    
    /// Apply opacity conditionally
    func opacity(_ condition: Bool, _ opacity: Double = 0.5) -> some View {
        self.opacity(condition ? opacity : 1.0)
    }
    
    /// Apply corner radius to specific corners
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
    
    /// Add a border with specific color and width
    func border(_ color: Color, width: CGFloat = 1) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(color, lineWidth: width)
        )
    }
    
    /// Add a circular border
    func circularBorder(_ color: Color, width: CGFloat = 1) -> some View {
        overlay(
            Circle()
                .stroke(color, lineWidth: width)
        )
    }
    
    /// Add a glow effect
    func glow(color: Color = .blue, radius: CGFloat = 10) -> some View {
        self.shadow(color: color, radius: radius / 2)
            .shadow(color: color, radius: radius / 2)
            .shadow(color: color, radius: radius / 2)
    }
    
    /// Make view tappable with haptic feedback
    func tappableWithHaptic(action: @escaping () -> Void) -> some View {
        self.onTapGesture {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            action()
        }
    }
    
    /// Apply bounce animation on tap
    func bounceOnTap() -> some View {
        self.scaleEffect(1.0)
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    // Scale down briefly
                }
            }
    }
}

// MARK: - Custom Shapes
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Color Extensions
extension Color {
    static let primaryBackground = Color(.systemBackground)
    static let secondaryBackground = Color(.secondarySystemBackground)
    static let tertiaryBackground = Color(.tertiarySystemBackground)
    
    static let primaryText = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    static let tertiaryText = Color(.tertiaryLabel)
    
    // Custom app colors
    static let appBlue = Color(red: 0.0, green: 0.5, blue: 1.0)
    static let appGreen = Color(red: 0.0, green: 0.8, blue: 0.4)
    static let appOrange = Color(red: 1.0, green: 0.6, blue: 0.0)
    static let appRed = Color(red: 1.0, green: 0.3, blue: 0.3)
    
    // Glassmorphism colors
    static let glassBackground = Color.white.opacity(0.2)
    static let glassBorder = Color.white.opacity(0.3)
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Font Extensions
extension Font {
    static let appTitle = Font.custom("Futura", size: 28).weight(.bold)
    static let appHeadline = Font.custom("Avenir Next", size: 18).weight(.semibold)
    static let appBody = Font.system(size: 16, weight: .regular, design: .default)
    static let appCaption = Font.system(size: 12, weight: .medium, design: .default)
}
