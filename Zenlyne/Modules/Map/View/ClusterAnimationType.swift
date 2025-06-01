//
//  ClusterAnimationType.swift
//  Zenlyne
//
//  Created by kou on 2/6/25.
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
}

// MARK: - Animation State
enum ClusterAnimationState {
    case idle
    case expanding
    case contracting
    case expanded
    case contracted
}

// MARK: - Cluster Animation Configuration
struct ClusterAnimationConfiguration {
    let duration: TimeInterval
    let expansionRadius: Double
    let easingFunction: EasingFunction
    let delayBetweenMarkers: TimeInterval
    let maxSimultaneousAnimations: Int
    
    static let `default` = ClusterAnimationConfiguration(
        duration: 0.4,
        expansionRadius: 30.0,
        easingFunction: .easeOutCubic,
        delayBetweenMarkers: 0.05,
        maxSimultaneousAnimations: 10
    )
    
    static let fast = ClusterAnimationConfiguration(
        duration: 0.2,
        expansionRadius: 25.0,
        easingFunction: .easeOutQuart,
        delayBetweenMarkers: 0.02,
        maxSimultaneousAnimations: 15
    )
    
    static let smooth = ClusterAnimationConfiguration(
        duration: 0.6,
        expansionRadius: 35.0,
        easingFunction: .easeInOutCubic,
        delayBetweenMarkers: 0.08,
        maxSimultaneousAnimations: 8
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
    
    func apply(_ progress: Double) -> Double {
        switch self {
        case .linear:
            return progress
        case .easeInCubic:
            return progress * progress * progress
        case .easeOutCubic:
            return 1 - pow(1 - progress, 3)
        case .easeInOutCubic:
            return progress < 0.5 ? 4 * progress * progress * progress : 1 - pow(-2 * progress + 2, 3) / 2
        case .easeInQuart:
            return progress * progress * progress * progress
        case .easeOutQuart:
            return 1 - pow(1 - progress, 4)
        case .easeInBack:
            let c1 = 1.70158
            let c3 = c1 + 1
            return c3 * progress * progress * progress - c1 * progress * progress
        case .easeOutBack:
            let c1 = 1.70158
            let c3 = c1 + 1
            return 1 + c3 * pow(progress - 1, 3) + c1 * pow(progress - 1, 2)
        case .bounceOut:
            let n1 = 7.5625
            let d1 = 2.75
            
            if progress < 1 / d1 {
                return n1 * progress * progress
            } else if progress < 2 / d1 {
                let adjustedProgress = progress - 1.5 / d1
                return n1 * adjustedProgress * adjustedProgress + 0.75
            } else if progress < 2.5 / d1 {
                let adjustedProgress = progress - 2.25 / d1
                return n1 * adjustedProgress * adjustedProgress + 0.9375
            } else {
                let adjustedProgress = progress - 2.625 / d1
                return n1 * adjustedProgress * adjustedProgress + 0.984375
            }
        }
    }
}

class ClusterAnimationManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var activeClusterAnimations: [String: ClusterAnimationState] = [:]
    @Published private(set) var animationCount: Int = 0
    
    // MARK: - Private Properties
    private var animationTimers: [String: Timer] = [:]
    private var animationProgress: [String: Double] = [:]
    private var clusterCenters: [String: CLLocationCoordinate2D] = [:]
    private var targetPositions: [String: CLLocationCoordinate2D] = [:]
    private var animationConfigurations: [String: ClusterAnimationConfiguration] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // Combine subjects
    private let animationStateSubject = CurrentValueSubject<[String: ClusterAnimationState], Never>([:])
    private let performanceMetricsSubject = CurrentValueSubject<PerformanceMetrics, Never>(PerformanceMetrics())
    
    struct PerformanceMetrics {
        let activeAnimations: Int
        let memoryUsage: Int
        let averageFrameRate: Double
        
        init() {
            self.activeAnimations = 0
            self.memoryUsage = 0
            self.averageFrameRate = 60.0
        }
        
        init(activeAnimations: Int, memoryUsage: Int, averageFrameRate: Double) {
            self.activeAnimations = activeAnimations
            self.memoryUsage = memoryUsage
            self.averageFrameRate = averageFrameRate
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
    
    /// Start expansion animation for a cluster
    func animateClusterExpansion(
        annotationManager: PointAnnotationManager,
        friendAnnotations: [PointAnnotation],
        clusterCenter: CLLocationCoordinate2D,
        clusterId: String,
        configuration: ClusterAnimationConfiguration = .default
    ) {
        print("DEBUG: Starting cluster expansion animation for \(clusterId)")
        
        // Cancel any existing animation for this cluster
        cancelClusterAnimation(clusterId: clusterId)
        
        // Store configuration and state
        animationConfigurations[clusterId] = configuration
        clusterCenters[clusterId] = clusterCenter
        activeClusterAnimations[clusterId] = .expanding
        
        // Position all markers at cluster center initially
        var initialAnnotations: [PointAnnotation] = []
        
        for annotation in friendAnnotations {
            var newAnnotation = annotation
            newAnnotation.point = Point(clusterCenter)
            newAnnotation.iconSize = 0.1 // Start small
            
            // Store target position
            targetPositions[annotation.id] = annotation.point.coordinates
            
            initialAnnotations.append(newAnnotation)
        }
        
        // Add annotations to manager
        annotationManager.annotations.append(contentsOf: initialAnnotations)
        
        // Start individual marker animations with staggered timing
        for (index, annotation) in initialAnnotations.enumerated() {
            let delay = Double(index) * configuration.delayBetweenMarkers
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.startMarkerExpansionAnimation(
                    annotationManager: annotationManager,
                    annotationId: annotation.id,
                    clusterId: clusterId,
                    configuration: configuration
                )
            }
        }
        
        // Set completion timer
        let totalDuration = configuration.duration + Double(friendAnnotations.count) * configuration.delayBetweenMarkers
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            self.activeClusterAnimations[clusterId] = .expanded
        }
    }
    
    /// Start contraction animation for a cluster
    func animateClusterContraction(
        annotationManager: PointAnnotationManager,
        friendAnnotations: [PointAnnotation],
        clusterCenter: CLLocationCoordinate2D,
        clusterId: String,
        duration: TimeInterval = 0.3,
        completion: @escaping () -> Void
    ) {
        print("DEBUG: Starting cluster contraction animation for \(clusterId)")
        
        activeClusterAnimations[clusterId] = .contracting
        clusterCenters[clusterId] = clusterCenter
        
        // Store starting positions
        for annotation in friendAnnotations {
            targetPositions[annotation.id] = annotation.point.coordinates
        }
        
        // Start contraction animations for each marker
        var completedAnimations = 0
        let totalAnimations = friendAnnotations.count
        
        for annotation in friendAnnotations {
            startMarkerContractionAnimation(
                annotationManager: annotationManager,
                annotationId: annotation.id,
                targetCenter: clusterCenter,
                duration: duration
            ) {
                completedAnimations += 1
                if completedAnimations == totalAnimations {
                    self.activeClusterAnimations[clusterId] = .contracted
                    completion()
                }
            }
        }
    }
    
    /// Cancel all animations for a specific cluster
    func cancelClusterAnimation(clusterId: String) {
        // Remove from active animations
        activeClusterAnimations.removeValue(forKey: clusterId)
        
        // Cancel any running timers for this cluster
        let clusterTimers = animationTimers.filter { key, _ in
            key.hasPrefix(clusterId)
        }
        
        for (timerKey, timer) in clusterTimers {
            timer.invalidate()
            animationTimers.removeValue(forKey: timerKey)
        }
        
        // Clean up stored data
        animationProgress = animationProgress.filter { !$0.key.hasPrefix(clusterId) }
        clusterCenters.removeValue(forKey: clusterId)
        animationConfigurations.removeValue(forKey: clusterId)
        
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
    
    private func startMarkerExpansionAnimation(
        annotationManager: PointAnnotationManager,
        annotationId: String,
        clusterId: String,
        configuration: ClusterAnimationConfiguration
    ) {
        let timerKey = "\(clusterId)_\(annotationId)"
        animationProgress[timerKey] = 0.0
        
        guard let clusterCenter = clusterCenters[clusterId],
              let targetPosition = targetPositions[annotationId] else {
            return
        }
        
        let timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            let currentProgress = self.animationProgress[timerKey] ?? 0.0
            let newProgress = min(1.0, currentProgress + 0.016 / configuration.duration)
            
            self.updateMarkerDuringExpansion(
                annotationManager: annotationManager,
                annotationId: annotationId,
                progress: newProgress,
                clusterCenter: clusterCenter,
                targetPosition: targetPosition,
                easingFunction: configuration.easingFunction
            )
            
            self.animationProgress[timerKey] = newProgress
            
            if newProgress >= 1.0 {
                timer.invalidate()
                self.animationTimers.removeValue(forKey: timerKey)
                self.animationProgress.removeValue(forKey: timerKey)
            }
        }
        
        animationTimers[timerKey] = timer
    }
    
    private func startMarkerContractionAnimation(
        annotationManager: PointAnnotationManager,
        annotationId: String,
        targetCenter: CLLocationCoordinate2D,
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        let timerKey = "contraction_\(annotationId)"
        animationProgress[timerKey] = 0.0
        
        guard let startPosition = targetPositions[annotationId] else {
            completion()
            return
        }
        
        let timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            let currentProgress = self.animationProgress[timerKey] ?? 0.0
            let newProgress = min(1.0, currentProgress + 0.016 / duration)
            
            self.updateMarkerDuringContraction(
                annotationManager: annotationManager,
                annotationId: annotationId,
                progress: newProgress,
                startPosition: startPosition,
                targetCenter: targetCenter
            )
            
            self.animationProgress[timerKey] = newProgress
            
            if newProgress >= 1.0 {
                timer.invalidate()
                self.animationTimers.removeValue(forKey: timerKey)
                self.animationProgress.removeValue(forKey: timerKey)
                completion()
            }
        }
        
        animationTimers[timerKey] = timer
    }
    
    // MARK: - Animation Updates
    
    private func updateMarkerDuringExpansion(
        annotationManager: PointAnnotationManager,
        annotationId: String,
        progress: Double,
        clusterCenter: CLLocationCoordinate2D,
        targetPosition: CLLocationCoordinate2D,
        easingFunction: EasingFunction
    ) {
        guard let index = annotationManager.annotations.firstIndex(where: { $0.id == annotationId }),
              var annotation = annotationManager.annotations[index] as? PointAnnotation else {
            return
        }
        
        let easedProgress = easingFunction.apply(progress)
        
        // Interpolate position
        let newLat = clusterCenter.latitude + (targetPosition.latitude - clusterCenter.latitude) * easedProgress
        let newLon = clusterCenter.longitude + (targetPosition.longitude - clusterCenter.longitude) * easedProgress
        let newCoordinate = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
        
        // Update position and size
        annotation.point = Point(newCoordinate)
        annotation.iconSize = 0.1 + 0.9 * easedProgress // Grow from 0.1 to 1.0
        
        // Update annotation in manager
        var annotations = annotationManager.annotations
        annotations[index] = annotation
        annotationManager.annotations = annotations
    }
    
    private func updateMarkerDuringContraction(
        annotationManager: PointAnnotationManager,
        annotationId: String,
        progress: Double,
        startPosition: CLLocationCoordinate2D,
        targetCenter: CLLocationCoordinate2D
    ) {
        guard let index = annotationManager.annotations.firstIndex(where: { $0.id == annotationId }),
              var annotation = annotationManager.annotations[index] as? PointAnnotation else {
            return
        }
        
        let easedProgress = EasingFunction.easeInCubic.apply(progress)
        
        // Interpolate position
        let newLat = startPosition.latitude + (targetCenter.latitude - startPosition.latitude) * easedProgress
        let newLon = startPosition.longitude + (targetCenter.longitude - startPosition.longitude) * easedProgress
        let newCoordinate = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
        
        // Update position and size
        annotation.point = Point(newCoordinate)
        annotation.iconSize = 1.0 - 0.9 * easedProgress // Shrink from 1.0 to 0.1
        
        // Update annotation in manager
        var annotations = annotationManager.annotations
        annotations[index] = annotation
        annotationManager.annotations = annotations
    }
    
    // MARK: - Performance Monitoring
    
    private func updatePerformanceMetrics() {
        let activeCount = activeClusterAnimations.count
        let memoryUsage = calculateMemoryUsage()
        let frameRate = calculateAverageFrameRate()
        
        let metrics = PerformanceMetrics(
            activeAnimations: activeCount,
            memoryUsage: memoryUsage,
            averageFrameRate: frameRate
        )
        
        performanceMetricsSubject.send(metrics)
    }
    
    private func calculateMemoryUsage() -> Int {
        return animationTimers.count * MemoryLayout<Timer>.size +
               animationProgress.count * MemoryLayout<Double>.size +
               clusterCenters.count * MemoryLayout<CLLocationCoordinate2D>.size +
               targetPositions.count * MemoryLayout<CLLocationCoordinate2D>.size
    }
    
    private func calculateAverageFrameRate() -> Double {
        // Simplified frame rate calculation
        // In a real implementation, you would track actual frame times
        return activeClusterAnimations.isEmpty ? 60.0 : max(30.0, 60.0 - Double(activeClusterAnimations.count) * 2.0)
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
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    /// Publisher that emits when any cluster animation completes
    func animationCompletionPublisher() -> AnyPublisher<String, Never> {
        animationStatePublisher
            .compactMap { state in
                // Find clusters that just completed (expanded or contracted)
                return state.first { _, animState in
                    animState == .expanded || animState == .contracted
                }?.key
            }
            .eraseToAnyPublisher()
    }
}
