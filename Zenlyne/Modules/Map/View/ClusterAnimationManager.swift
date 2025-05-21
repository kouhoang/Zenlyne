//
//  ClusterAnimationManager.swift
//  Zenlyne
//
//  Created by admin on 21/5/25.
//

import UIKit
import MapboxMaps
import CoreLocation

class ClusterAnimationManager {
    // Animation timers for each marker
    private var animationTimers: [String: Timer] = [:]
    
    // Animation progress tracking
    private var animationProgress: [String: Double] = [:]
    
    // Reference to the original cluster center
    private var clusterCenters: [String: CLLocationCoordinate2D] = [:]
    
    // Reference to target positions
    private var targetPositions: [String: CLLocationCoordinate2D] = [:]
    
    // MARK: - Animation Lifecycle
    
    // Start expansion animation for a cluster
    func animateClusterExpansion(
        annotationManager: PointAnnotationManager,
        friendAnnotations: [PointAnnotation],
        clusterCenter: CLLocationCoordinate2D,
        clusterId: String,
        duration: TimeInterval = 0.4
    ) {
        // Store the cluster center for reference
        clusterCenters[clusterId] = clusterCenter
        
        // First position all markers at the cluster center
        var initialAnnotations: [PointAnnotation] = []
        
        for annotation in friendAnnotations {
            var newAnnotation = annotation
            
            // Set initial position at cluster center
            newAnnotation.point = Point(clusterCenter)
            
            // Store the target position
            targetPositions[annotation.id] = annotation.point.coordinates
            
            // Set initial size to 0 for grow effect
            newAnnotation.iconSize = 0.1
            
            initialAnnotations.append(newAnnotation)
        }
        
        // Add all annotations at cluster center
        annotationManager.annotations = initialAnnotations
        
        // Start animation for each marker
        for annotation in initialAnnotations {
            // Initialize animation progress
            animationProgress[annotation.id] = 0.0
            
            // Create timer for animation
            let timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                // Update animation progress
                let currentProgress = self.animationProgress[annotation.id] ?? 0.0
                let newProgress = min(1.0, currentProgress + 0.016 / duration)
                
                // Update position and size based on animation curve
                self.updateAnnotationDuringExpansion(
                    annotationManager: annotationManager,
                    annotationId: annotation.id,
                    progress: newProgress
                )
                
                // Store new progress
                self.animationProgress[annotation.id] = newProgress
                
                // Complete animation
                if newProgress >= 1.0 {
                    timer.invalidate()
                    self.animationTimers.removeValue(forKey: annotation.id)
                }
            }
            
            // Store the timer
            animationTimers[annotation.id] = timer
        }
    }
    
    // Start contraction animation for a cluster
    func animateClusterContraction(
        annotationManager: PointAnnotationManager,
        friendAnnotations: [PointAnnotation],
        clusterCenter: CLLocationCoordinate2D,
        clusterId: String,
        duration: TimeInterval = 0.3,
        completion: @escaping () -> Void
    ) {
        // Store the cluster center for reference
        clusterCenters[clusterId] = clusterCenter
        
        // Start animation for each marker
        for annotation in friendAnnotations {
            // Store the starting position
            targetPositions[annotation.id] = annotation.point.coordinates
            
            // Initialize animation progress
            animationProgress[annotation.id] = 0.0
            
            // Create timer for animation
            let timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                // Update animation progress (reverse for contraction)
                let currentProgress = self.animationProgress[annotation.id] ?? 0.0
                let newProgress = min(1.0, currentProgress + 0.016 / duration)
                
                // Update position and size based on animation curve
                self.updateAnnotationDuringContraction(
                    annotationManager: annotationManager,
                    annotationId: annotation.id,
                    progress: newProgress,
                    targetCenter: clusterCenter
                )
                
                // Store new progress
                self.animationProgress[annotation.id] = newProgress
                
                // Complete animation
                if newProgress >= 1.0 {
                    timer.invalidate()
                    self.animationTimers.removeValue(forKey: annotation.id)
                    
                    // Check if all animations are complete
                    if self.animationTimers.isEmpty {
                        // Call completion handler when all markers are done
                        completion()
                    }
                }
            }
            
            // Store the timer
            animationTimers[annotation.id] = timer
        }
    }
    
    // Cancel all animations
    func cancelAnimations() {
        for (_, timer) in animationTimers {
            timer.invalidate()
        }
        
        animationTimers.removeAll()
        animationProgress.removeAll()
        clusterCenters.removeAll()
        targetPositions.removeAll()
    }
    
    // MARK: - Animation Updates
    
    // Update annotation during expansion animation
    private func updateAnnotationDuringExpansion(
        annotationManager: PointAnnotationManager,
        annotationId: String,
        progress: Double
    ) {
        // Find the annotation
        guard let index = annotationManager.annotations.firstIndex(where: { $0.id == annotationId }),
              var annotation = annotationManager.annotations[index] as? PointAnnotation,
              let targetPosition = targetPositions[annotationId] else {
            return
        }
        
        // Get the cluster ID from userInfo dictionary with proper optional unwrapping
        let clusterId: String
        if let userInfoDict = annotation.userInfo, let id = userInfoDict["clusterId"] as? String {
            clusterId = id
        } else {
            clusterId = "default"
        }
        
        // Get the cluster center
        guard let clusterCenter = clusterCenters[clusterId] else {
            return
        }
        
        // Use easing function for smoother animation
        let easedProgress = easeOutCubic(progress)
        
        // Interpolate between cluster center and target position
        let newLat = clusterCenter.latitude + (targetPosition.latitude - clusterCenter.latitude) * easedProgress
        let newLon = clusterCenter.longitude + (targetPosition.longitude - clusterCenter.longitude) * easedProgress
        
        // Create new coordinate
        let newCoordinate = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
        
        // Update position
        annotation.point = Point(newCoordinate)
        
        // Update size (grow from 0.1 to 1.0)
        annotation.iconSize = 0.1 + 0.9 * easedProgress
        
        // Update annotation in manager
        var annotations = annotationManager.annotations
        annotations[index] = annotation
        annotationManager.annotations = annotations
    }
    
    // Update annotation during contraction animation
    private func updateAnnotationDuringContraction(
        annotationManager: PointAnnotationManager,
        annotationId: String,
        progress: Double,
        targetCenter: CLLocationCoordinate2D
    ) {
        // Find the annotation
        guard let index = annotationManager.annotations.firstIndex(where: { $0.id == annotationId }),
              var annotation = annotationManager.annotations[index] as? PointAnnotation,
              let startPosition = targetPositions[annotationId] else {
            return
        }
        
        // Use easing function for smoother animation
        let easedProgress = easeInCubic(progress)
        
        // Interpolate between starting position and cluster center
        let newLat = startPosition.latitude + (targetCenter.latitude - startPosition.latitude) * easedProgress
        let newLon = startPosition.longitude + (targetCenter.longitude - startPosition.longitude) * easedProgress
        
        // Create new coordinate
        let newCoordinate = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
        
        // Update position
        annotation.point = Point(newCoordinate)
        
        // Update size (shrink from 1.0 to 0.1)
        annotation.iconSize = 1.0 - 0.9 * easedProgress
        
        // Update annotation in manager
        var annotations = annotationManager.annotations
        annotations[index] = annotation
        annotationManager.annotations = annotations
    }
    
    // MARK: - Easing Functions
    
    // Cubic ease-out function for smooth acceleration
    private func easeOutCubic(_ x: Double) -> Double {
        return 1 - pow(1 - x, 3)
    }
    
    // Cubic ease-in function for smooth deceleration
    private func easeInCubic(_ x: Double) -> Double {
        return x * x * x
    }
}
