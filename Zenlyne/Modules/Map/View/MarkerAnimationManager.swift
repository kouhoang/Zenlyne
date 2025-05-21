//
//  MarkerAnimationManager.swift
//  Zenlyne
//
//  Created by admin on 20/5/25.
//


import UIKit
import MapboxMaps

class MarkerAnimationManager {
    private var animationTimers: [String: Timer] = [:]
    private var animationValues: [String: Double] = [:]
    
    // Start bouncing animation for a marker
    func startMarkerBounce(
        annotationManager: PointAnnotationManager,
        annotationId: String,
        duration: Double = 0.5,
        amplitude: Double = 0.1,
        repeat: Bool = true
    ) {
        // Skip if already animating
        if animationTimers[annotationId] != nil {
            return
        }
        
        // Store initial state
        animationValues[annotationId] = 0.0
        
        // Create timer for animation
        let timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            // Update animation value
            let currentValue = self.animationValues[annotationId] ?? 0.0
            let newValue = currentValue + 0.03
            
            // Calculate bounce effect using sine wave
            let bounceOffset = amplitude * sin(newValue * 2 * .pi / duration)
            
            // Apply to marker
            self.applyBounceToMarker(
                annotationManager: annotationManager,
                annotationId: annotationId,
                bounceValue: bounceOffset + 1.0
            )
            
            // Update stored value
            self.animationValues[annotationId] = newValue
            
            // Reset if not repeating
            if !`repeat` && newValue >= duration {
                self.stopMarkerBounce(
                    annotationManager: annotationManager,
                    annotationId: annotationId
                )
            }
        }
        
        // Store timer
        animationTimers[annotationId] = timer
    }
    
    // Stop bouncing animation
    func stopMarkerBounce(
        annotationManager: PointAnnotationManager,
        annotationId: String
    ) {
        // Stop timer
        if let timer = animationTimers[annotationId] {
            timer.invalidate()
            animationTimers.removeValue(forKey: annotationId)
        }
        
        // Reset marker
        applyBounceToMarker(
            annotationManager: annotationManager,
            annotationId: annotationId,
            bounceValue: 1.0
        )
        
        animationValues.removeValue(forKey: annotationId)
    }
    
    // Apply bounce animation to marker
    private func applyBounceToMarker(
        annotationManager: PointAnnotationManager,
        annotationId: String,
        bounceValue: Double
    ) {
        // Find the annotation
        guard let annotationIndex = annotationManager.annotations.firstIndex(where: { $0.id == annotationId }),
              var annotation = annotationManager.annotations[annotationIndex] as? PointAnnotation else {
            return
        }
        
        // Update annotation size
        annotation.iconSize = bounceValue
        
        // Update annotation in manager
        var annotations = annotationManager.annotations
        annotations[annotationIndex] = annotation
        annotationManager.annotations = annotations
    }
    
    // Start simultaneous pulse animation for multiple markers (for friends in a group)
    func startGroupPulseAnimation(
        annotationManager: PointAnnotationManager,
        annotationIds: [String],
        duration: Double = 2.0,
        startOffsets: [Double]? = nil
    ) {
        // Create offsets for markers in group to give a wave effect
        let offsets: [Double]
        if let startOffsets = startOffsets, startOffsets.count == annotationIds.count {
            offsets = startOffsets
        } else {
            // Create sequential offsets if none provided
            offsets = (0..<annotationIds.count).map { 
                Double($0) * (duration / Double(annotationIds.count)) 
            }
        }
        
        // Start animation for each marker with its offset
        for (index, annotationId) in annotationIds.enumerated() {
            let offset = offsets[index]
            
            // Set initial value with offset
            animationValues[annotationId] = offset
            
            // Start timer for this marker
            let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                // Update animation value
                var currentValue = self.animationValues[annotationId] ?? 0.0
                currentValue += 0.05
                
                // Loop animation
                if currentValue > duration {
                    currentValue = 0.0
                }
                
                // Calculate pulse value (0.9 to 1.1)
                let progress = currentValue / duration
                let pulseValue = 1.0 + 0.1 * sin(progress * 2 * .pi)
                
                // Apply to marker
                self.applyBounceToMarker(
                    annotationManager: annotationManager,
                    annotationId: annotationId,
                    bounceValue: pulseValue
                )
                
                // Update stored value
                self.animationValues[annotationId] = currentValue
            }
            
            // Store timer
            animationTimers[annotationId] = timer
        }
    }
    
    // Stop all animations
    func stopAllAnimations(annotationManager: PointAnnotationManager) {
        for (annotationId, timer) in animationTimers {
            timer.invalidate()
            
            // Reset marker
            applyBounceToMarker(
                annotationManager: annotationManager,
                annotationId: annotationId,
                bounceValue: 1.0
            )
        }
        
        animationTimers.removeAll()
        animationValues.removeAll()
    }
}
