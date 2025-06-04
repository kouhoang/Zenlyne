//
//  ClusterAnimationType.swift
//  Zenlyne
//
//  Created by kou on 4/6/25.
//


import UIKit
import MapboxMaps
import CoreLocation
import Combine

// MARK: - Cluster Animation Types
enum ClusterAnimationType {
    case expansion
    case contraction
    case explosion
    case implosion
    case ripple
    case smooth
}

// MARK: - Animation State
enum ClusterAnimationState {
    case idle
    case expanding
    case contracting
    case expanded
    case contracted
    case animating(type: ClusterAnimationType, progress: Double)
}

// MARK: - Cluster Animation Configuration
struct ClusterAnimationConfiguration {
    let duration: TimeInterval
    let expansionRadius: Double
    let easingFunction: EasingFunction
    let delayBetweenMarkers: TimeInterval
    let maxSimultaneousAnimations: Int
    let animationType: ClusterAnimationType
    
    static let `default` = ClusterAnimationConfiguration(
        duration: 0.4,
        expansionRadius: 35.0,
        easingFunction: .easeOutCubic,
        delayBetweenMarkers: 0.03,
        maxSimultaneousAnimations: 10,
        animationType: .smooth
    )
    
    static let fast = ClusterAnimationConfiguration(
        duration: 0.25,
        expansionRadius: 30.0,
        easingFunction: .easeOutQuart,
        delayBetweenMarkers: 0.02,
        maxSimultaneousAnimations: 15,
        animationType: .explosion
    )
    
    static let smooth = ClusterAnimationConfiguration(
        duration: 0.5,
        expansionRadius: 40.0,
        easingFunction: .easeInOutCubic,
        delayBetweenMarkers: 0.05,
        maxSimultaneousAnimations: 8,
        animationType: .smooth
    )
    
    static let bouncy = ClusterAnimationConfiguration(
        duration: 0.6,
        expansionRadius: 35.0,
        easingFunction: .bounceOut,
        delayBetweenMarkers: 0.04,
        maxSimultaneousAnimations: 12,
        animationType: .ripple
    )
}

// MARK: - Easing Functions
enum EasingFunction {
    case linear
    case easeInCubic
    case easeOutCubic
    case easeInOutCubic
    case easeInQuart
    case easeOutQuart
    case easeInBack
    case easeOutBack
    case bounceOut
    case elasticOut
    
    func apply(_ progress: Double) -> Double {
        let t = max(0, min(1, progress)) // Clamp between 0 and 1
        
        switch self {
        case .linear:
            return t
        case .easeInCubic:
            return t * t * t
        case .easeOutCubic:
            return 1 - pow(1 - t, 3)
        case .easeInOutCubic:
            return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        case .easeInQuart:
            return t * t * t * t
        case .easeOutQuart:
            return 1 - pow(1 - t, 4)
        case .easeInBack:
            let c1 = 1.70158
            let c3 = c1 + 1
            return c3 * t * t * t - c1 * t * t
        case .easeOutBack:
            let c1 = 1.70158
            let c3 = c1 + 1
            return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
        case .bounceOut:
            let n1 = 7.5625
            let d1 = 2.75
            
            if t < 1 / d1 {
                return n1 * t * t
            } else if t < 2 / d1 {
                let adjustedT = t - 1.5 / d1
                return n1 * adjustedT * adjustedT + 0.75
            } else if t < 2.5 / d1 {
                let adjustedT = t - 2.25 / d1
                return n1 * adjustedT * adjustedT + 0.9375
            } else {
                let adjustedT = t - 2.625 / d1
                return n1 * adjustedT * adjustedT + 0.984375
            }
        case .elasticOut:
            let c4 = (2 * Double.pi) / 3
            
            if t == 0 {
                return 0
            } else if t == 1 {
                return 1
            } else {
                return pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1
            }
        }
    }
}

class ClusterAnimationManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var activeClusterAnimations: [String: ClusterAnimationState] = [:]
    @Published private(set) var animationCount: Int = 0
    @Published var defaultConfiguration: ClusterAnimationConfiguration = .default
    
    // MARK: - Private Properties
    private var animationTimers: [String: Timer] = [:]
    private var animationProgress: [String: Double] = [:]
    private var clusterCenters: [String: CLLocationCoordinate2D] = [:]
    private var targetPositions: [String: [String: CLLocationCoordinate2D]] = [:] // clusterId -> [friendId: position]
    private var animationConfigurations: [String: ClusterAnimationConfiguration] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // Performance tracking
    private var animationStartTimes: [String: Date] = [:]
    private var frameRateTracker: [String: [TimeInterval]] = [:]
    
    // Combine subjects
    private let animationStateSubject = CurrentValueSubject<[String: ClusterAnimationState], Never>([:])
    private let performanceMetricsSubject = CurrentValueSubject<PerformanceMetrics, Never>(PerformanceMetrics())
    
    struct PerformanceMetrics {
        let activeAnimations: Int
        let memoryUsage: Int
        let averageFrameRate: Double
        let droppedFrames: Int
        
        init() {
            self.activeAnimations = 0
            self.memoryUsage = 0
            self.averageFrameRate = 60.0
            self.droppedFrames = 0
        }
        
        init(activeAnimations: Int, memoryUsage: Int, averageFrameRate: Double, droppedFrames: Int) {
            self.activeAnimations = activeAnimations
            self.memoryUsage = memoryUsage
            self.averageFrameRate = averageFrameRate
            self.droppedFrames = droppedFrames
        }
    }
    
    // MARK: - Combine Publishers
    var animationStatePublisher: AnyPublisher<[String: ClusterAnimationState], Never> {
        animationStateSubject
            .removeDuplicates { $0.count == $1.count }
            .eraseToAnyPublisher()
    }
    
    var performanceMetricsPublisher: AnyPublisher<PerformanceMetrics, Never> {
        performanceMetricsSubject
            .removeDuplicates { lhs, rhs in
                lhs.activeAnimations == rhs.activeAnimations &&
                lhs.memoryUsage == rhs.memoryUsage
            }
            .eraseToAnyPublisher()
    }
    
    var hasActiveAnimationsPublisher: AnyPublisher<Bool, Never> {
        $animationCount
            .map { $0 > 0 }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    init() {
        setupCombineBindings()
        startPerformanceMonitoring()
    }
    
    private func setupCombineBindings() {
        // Sync animation count
        $activeClusterAnimations
            .map { $0.count }
            .assign(to: &$animationCount)
        
        // Sync animation state subject
        $activeClusterAnimations
            .sink { [weak self] state in
                self?.animationStateSubject.send(state)
            }
            .store(in: &cancellables)
    }
    
    private func startPerformanceMonitoring() {
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updatePerformanceMetrics()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Animation Methods
    
    /// Start expansion animation for a cluster with smooth avatar transitions
    func animateClusterExpansion(
        clusterId: String,
        friendIds: [String],
        clusterCenter: CLLocationCoordinate2D,
        targetPositions: [String: CLLocationCoordinate2D],
        configuration: ClusterAnimationConfiguration? = nil,
        completion: @escaping () -> Void = {}
    ) {
        print("DEBUG: Starting smooth cluster expansion animation for \(clusterId)")
        
        // Cancel any existing animation for this cluster
        cancelClusterAnimation(clusterId: clusterId)
        
        // Store configuration and state
        let animationConfig = configuration ?? defaultConfiguration
        animationConfigurations[clusterId] = animationConfig
        clusterCenters[clusterId] = clusterCenter
        self.targetPositions[clusterId] = targetPositions
        activeClusterAnimations[clusterId] = .expanding
        animationStartTimes[clusterId] = Date()
        
        // Start the main animation
        startSmoothExpansionAnimation(
            clusterId: clusterId,
            friendIds: friendIds,
            clusterCenter: clusterCenter,
            targetPositions: targetPositions,
            configuration: animationConfig,
            completion: completion
        )
    }
    
    /// Start contraction animation for a cluster
    func animateClusterContraction(
        clusterId: String,
        friendIds: [String],
        startPositions: [String: CLLocationCoordinate2D],
        targetCenter: CLLocationCoordinate2D,
        configuration: ClusterAnimationConfiguration? = nil,
        completion: @escaping () -> Void = {}
    ) {
        print("DEBUG: Starting smooth cluster contraction animation for \(clusterId)")
        
        let animationConfig = configuration ?? ClusterAnimationConfiguration(
            duration: 0.3,
            expansionRadius: 0,
            easingFunction: .easeInCubic,
            delayBetweenMarkers: 0,
            maxSimultaneousAnimations: 20,
            animationType: .contraction
        )
        
        activeClusterAnimations[clusterId] = .contracting
        clusterCenters[clusterId] = targetCenter
        animationStartTimes[clusterId] = Date()
        
        startSmoothContractionAnimation(
            clusterId: clusterId,
            friendIds: friendIds,
            startPositions: startPositions,
            targetCenter: targetCenter,
            configuration: animationConfig,
            completion: completion
        )
    }
    
    /// Cancel all animations for a specific cluster
    func cancelClusterAnimation(clusterId: String) {
        // Remove from active animations
        activeClusterAnimations.removeValue(forKey: clusterId)
        
        // Cancel timer
        animationTimers[clusterId]?.invalidate()
        animationTimers.removeValue(forKey: clusterId)
        
        // Clean up stored data
        animationProgress.removeValue(forKey: clusterId)
        clusterCenters.removeValue(forKey: clusterId)
        targetPositions.removeValue(forKey: clusterId)
        animationConfigurations.removeValue(forKey: clusterId)
        animationStartTimes.removeValue(forKey: clusterId)
        frameRateTracker.removeValue(forKey: clusterId)
        
        print("DEBUG: Cancelled cluster animation for \(clusterId)")
    }
    
    /// Cancel all cluster animations
    func cancelAllAnimations() {
        let clusterIds = Array(activeClusterAnimations.keys)
        for clusterId in clusterIds {
            cancelClusterAnimation(clusterId: clusterId)
        }
        
        print("DEBUG: Cancelled all cluster animations")
    }
    
    // MARK: - Private Animation Implementation
    
    private func startSmoothExpansionAnimation(
        clusterId: String,
        friendIds: [String],
        clusterCenter: CLLocationCoordinate2D,
        targetPositions: [String: CLLocationCoordinate2D],
        configuration: ClusterAnimationConfiguration,
        completion: @escaping () -> Void
    ) {
        animationProgress[clusterId] = 0.0
        frameRateTracker[clusterId] = []
        
        let frameInterval: TimeInterval = 0.016 // ~60fps
        var lastFrameTime = Date()
        
        let timer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            // Track frame rate
            let now = Date()
            let frameTime = now.timeIntervalSince(lastFrameTime)
            self.frameRateTracker[clusterId]?.append(frameTime)
            lastFrameTime = now
            
            // Update progress
            let currentProgress = self.animationProgress[clusterId] ?? 0.0
            let newProgress = min(1.0, currentProgress + frameInterval / configuration.duration)
            
            // Apply easing function
            let easedProgress = configuration.easingFunction.apply(newProgress)
            
            // Calculate current positions for all friends
            var currentPositions: [String: CLLocationCoordinate2D] = [:]
            
            for friendId in friendIds {
                guard let targetPos = targetPositions[friendId] else { continue }
                
                // Add special effects based on animation type
                let adjustedProgress = self.applyAnimationTypeEffect(
                    progress: easedProgress,
                    animationType: configuration.animationType,
                    friendIndex: friendIds.firstIndex(of: friendId) ?? 0,
                    totalFriends: friendIds.count
                )
                
                // Interpolate position
                let lat = clusterCenter.latitude + (targetPos.latitude - clusterCenter.latitude) * adjustedProgress
                let lon = clusterCenter.longitude + (targetPos.longitude - clusterCenter.longitude) * adjustedProgress
                
                currentPositions[friendId] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            
            // Update animation state
            self.activeClusterAnimations[clusterId] = .animating(type: configuration.animationType, progress: easedProgress)
            self.animationProgress[clusterId] = newProgress
            
            // Notify about position updates via notification
            NotificationCenter.default.post(
                name: NSNotification.Name("ClusterAnimationUpdate"),
                object: nil,
                userInfo: [
                    "clusterId": clusterId,
                    "positions": currentPositions,
                    "progress": easedProgress,
                    "type": "expansion"
                ]
            )
            
            // Complete animation
            if newProgress >= 1.0 {
                timer.invalidate()
                self.animationTimers.removeValue(forKey: clusterId)
                self.animationProgress.removeValue(forKey: clusterId)
                self.activeClusterAnimations[clusterId] = .expanded
                
                print("DEBUG: Completed expansion animation for cluster \(clusterId)")
                completion()
            }
        }
        
        animationTimers[clusterId] = timer
    }
    
    private func startSmoothContractionAnimation(
        clusterId: String,
        friendIds: [String],
        startPositions: [String: CLLocationCoordinate2D],
        targetCenter: CLLocationCoordinate2D,
        configuration: ClusterAnimationConfiguration,
        completion: @escaping () -> Void
    ) {
        animationProgress[clusterId] = 0.0
        frameRateTracker[clusterId] = []
        
        let frameInterval: TimeInterval = 0.016
        var lastFrameTime = Date()
        
        let timer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            // Track frame rate
            let now = Date()
            let frameTime = now.timeIntervalSince(lastFrameTime)
            self.frameRateTracker[clusterId]?.append(frameTime)
            lastFrameTime = now
            
            // Update progress
            let currentProgress = self.animationProgress[clusterId] ?? 0.0
            let newProgress = min(1.0, currentProgress + frameInterval / configuration.duration)
            
            // Apply easing function
            let easedProgress = configuration.easingFunction.apply(newProgress)
            
            // Calculate current positions for all friends
            var currentPositions: [String: CLLocationCoordinate2D] = [:]
            
            for friendId in friendIds {
                guard let startPos = startPositions[friendId] else { continue }
                
                // Interpolate position back to center
                let lat = startPos.latitude + (targetCenter.latitude - startPos.latitude) * easedProgress
                let lon = startPos.longitude + (targetCenter.longitude - startPos.longitude) * easedProgress
                
                currentPositions[friendId] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            
            // Update animation state
            self.activeClusterAnimations[clusterId] = .animating(type: .contraction, progress: easedProgress)
            self.animationProgress[clusterId] = newProgress
            
            // Notify about position updates
            NotificationCenter.default.post(
                name: NSNotification.Name("ClusterAnimationUpdate"),
                object: nil,
                userInfo: [
                    "clusterId": clusterId,
                    "positions": currentPositions,
                    "progress": easedProgress,
                    "type": "contraction"
                ]
            )
            
            // Complete animation
            if newProgress >= 1.0 {
                timer.invalidate()
                self.animationTimers.removeValue(forKey: clusterId)
                self.animationProgress.removeValue(forKey: clusterId)
                self.activeClusterAnimations[clusterId] = .contracted
                
                print("DEBUG: Completed contraction animation for cluster \(clusterId)")
                completion()
            }
        }
        
        animationTimers[clusterId] = timer
    }
    
    // MARK: - Animation Type Effects
    
    private func applyAnimationTypeEffect(
        progress: Double,
        animationType: ClusterAnimationType,
        friendIndex: Int,
        totalFriends: Int
    ) -> Double {
        switch animationType {
        case .explosion:
            // Faster at the beginning, dramatic expansion
            return min(1.0, progress * 1.2)
            
        case .ripple:
            // Staggered animation based on friend index
            let delay = Double(friendIndex) / Double(totalFriends) * 0.3
            let adjustedProgress = max(0, progress - delay) / (1.0 - delay)
            return min(1.0, adjustedProgress)
            
        case .smooth, .expansion, .contraction:
            // Standard smooth animation
            return progress
            
        case .implosion:
            // Slower start, faster finish
            return pow(progress, 0.5)
        }
    }
    
    // MARK: - Performance Monitoring
    
    private func updatePerformanceMetrics() {
        let activeCount = activeClusterAnimations.count
        let memoryUsage = calculateMemoryUsage()
        let (avgFrameRate, droppedFrames) = calculatePerformanceStats()
        
        let metrics = PerformanceMetrics(
            activeAnimations: activeCount,
            memoryUsage: memoryUsage,
            averageFrameRate: avgFrameRate,
            droppedFrames: droppedFrames
        )
        
        performanceMetricsSubject.send(metrics)
    }
    
    private func calculateMemoryUsage() -> Int {
        return animationTimers.count * MemoryLayout<Timer>.size +
               animationProgress.count * MemoryLayout<Double>.size +
               clusterCenters.count * MemoryLayout<CLLocationCoordinate2D>.size +
               targetPositions.values.reduce(0) { $0 + $1.count * MemoryLayout<CLLocationCoordinate2D>.size }
    }
    
    private func calculatePerformanceStats() -> (avgFrameRate: Double, droppedFrames: Int) {
        guard !frameRateTracker.isEmpty else {
            return (60.0, 0)
        }
        
        var totalFrameTime: TimeInterval = 0
        var totalFrames: Int = 0
        var droppedFrames: Int = 0
        
        for frameTimes in frameRateTracker.values {
            for frameTime in frameTimes {
                totalFrameTime += frameTime
                totalFrames += 1
                
                // Consider frame dropped if > 20ms (below 50fps)
                if frameTime > 0.02 {
                    droppedFrames += 1
                }
            }
        }
        
        let avgFrameTime = totalFrames > 0 ? totalFrameTime / Double(totalFrames) : 0.016
        let avgFrameRate = avgFrameTime > 0 ? 1.0 / avgFrameTime : 60.0
        
        return (min(60.0, avgFrameRate), droppedFrames)
    }
    
    // MARK: - Utility Methods
    
    /// Check if a specific cluster is being animated
    func isClusterAnimating(_ clusterId: String) -> Bool {
        return activeClusterAnimations[clusterId] != nil
    }
    
    /// Get current animation state for a cluster
    func getClusterAnimationState(_ clusterId: String) -> ClusterAnimationState? {
        return activeClusterAnimations[clusterId]
    }
    
    /// Get current animation progress for a cluster
    func getClusterAnimationProgress(_ clusterId: String) -> Double {
        return animationProgress[clusterId] ?? 0.0
    }
    
    /// Pause all animations
    func pauseAllAnimations() {
        for timer in animationTimers.values {
            timer.fireDate = Date.distantFuture
        }
        print("DEBUG: Paused all cluster animations")
    }
    
    /// Resume all paused animations
    func resumeAllAnimations() {
        for timer in animationTimers.values {
            timer.fireDate = Date()
        }
        print("DEBUG: Resumed all cluster animations")
    }
    
    /// Update default configuration
    func updateDefaultConfiguration(_ config: ClusterAnimationConfiguration) {
        defaultConfiguration = config
        print("DEBUG: Updated default animation configuration")
    }
    
    /// Get animation duration for a cluster
    func getAnimationDuration(for clusterId: String) -> TimeInterval? {
        guard let startTime = animationStartTimes[clusterId] else { return nil }
        return Date().timeIntervalSince(startTime)
    }
    
    deinit {
        cancelAllAnimations()
        print("DEBUG: ClusterAnimationManager deinitialized")
    }
}

// MARK: - Combine Extensions

extension ClusterAnimationManager {
    
    /// Publisher for specific cluster animation state
    func clusterAnimationStatePublisher(for clusterId: String) -> AnyPublisher<ClusterAnimationState?, Never> {
        animationStatePublisher
            .map { $0[clusterId] }
            .removeDuplicates { lhs, rhs in
                switch (lhs, rhs) {
                case (.none, .none):
                    return true
                case (.some(let l), .some(let r)):
                    return String(describing: l) == String(describing: r)
                default:
                    return false
                }
            }
            .eraseToAnyPublisher()
    }
    
    /// Publisher that emits when any cluster animation completes
    func animationCompletionPublisher() -> AnyPublisher<(clusterId: String, finalState: ClusterAnimationState), Never> {
        animationStatePublisher
            .compactMap { state in
                // Find clusters that just completed (expanded or contracted)
                return state.first { _, animState in
                    switch animState {
                    case .expanded, .contracted:
                        return true
                    default:
                        return false
                    }
                }.map { (clusterId: $0.key, finalState: $0.value) }
            }
            .eraseToAnyPublisher()
    }
    
    /// Publisher for animation progress updates
    func animationProgressPublisher(for clusterId: String) -> AnyPublisher<Double, Never> {
        Timer.publish(every: 0.016, on: .main, in: .common)
            .autoconnect()
            .compactMap { [weak self] _ in
                self?.animationProgress[clusterId]
            }
            .removeDuplicates { abs($0 - $1) < 0.01 }
            .eraseToAnyPublisher()
    }
}
