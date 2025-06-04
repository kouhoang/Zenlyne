//
//  ReverseGeocodingService.swift
//  Zenlyne
//
//  Created by admin on 4/6/25.
//

import Foundation
import CoreLocation
import Combine

// MARK: - Location Info Model
struct LocationInfo {
    let coordinate: CLLocationCoordinate2D
    let name: String
    let administrativeArea: String?
    let locality: String?
    let subLocality: String?
    let thoroughfare: String?
    
    var displayName: String {
        if let subLocality = subLocality, !subLocality.isEmpty {
            return subLocality
        } else if let locality = locality, !locality.isEmpty {
            return locality
        } else if let administrativeArea = administrativeArea, !administrativeArea.isEmpty {
            return administrativeArea
        } else {
            return name
        }
    }
    
    var fullAddress: String {
        var components: [String] = []
        
        if let thoroughfare = thoroughfare, !thoroughfare.isEmpty {
            components.append(thoroughfare)
        }
        if let subLocality = subLocality, !subLocality.isEmpty {
            components.append(subLocality)
        }
        if let locality = locality, !locality.isEmpty {
            components.append(locality)
        }
        if let administrativeArea = administrativeArea, !administrativeArea.isEmpty {
            components.append(administrativeArea)
        }
        
        return components.isEmpty ? name : components.joined(separator: ", ")
    }
}

// MARK: - Reverse Geocoding Service
class ReverseGeocodingService: ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var currentLocationInfo: LocationInfo?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?
    
    // MARK: - Private Properties
    private let geocoder = CLGeocoder()
    private var cancellables = Set<AnyCancellable>()
    private var currentGeocodingTask: Task<Void, Never>?
    
    // Cache for frequently accessed locations
    private var locationCache: [String: LocationInfo] = [:]
    private let cacheRadius: Double = 100.0 // 100 meters
    private let maxCacheSize = 50
    
    // Debouncing and throttling
    private let coordinateSubject = PassthroughSubject<CLLocationCoordinate2D, Never>()
    private let debounceInterval: TimeInterval = 0.8
    private let minimumRequestInterval: TimeInterval = 0.5
    private var lastRequestTime: Date = Date.distantPast
    
    // MARK: - Combine Publishers
    var locationInfoPublisher: AnyPublisher<LocationInfo?, Never> {
        $currentLocationInfo
            .removeDuplicates { lhs, rhs in
                guard let lhs = lhs, let rhs = rhs else {
                    return lhs == nil && rhs == nil
                }
                return lhs.coordinate.latitude == rhs.coordinate.latitude &&
                       lhs.coordinate.longitude == rhs.coordinate.longitude
            }
            .eraseToAnyPublisher()
    }
    
    var isLoadingPublisher: AnyPublisher<Bool, Never> {
        $isLoading
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    init() {
        setupCoordinateProcessing()
    }
    
    private func setupCoordinateProcessing() {
        coordinateSubject
            .debounce(for: .seconds(debounceInterval), scheduler: DispatchQueue.main)
            .sink { [weak self] coordinate in
                self?.performReverseGeocode(for: coordinate)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Request reverse geocoding for a coordinate
    func reverseGeocode(coordinate: CLLocationCoordinate2D) {
        // Validate coordinate
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude != 0,
              coordinate.longitude != 0 else {
            print("DEBUG: Invalid coordinate for reverse geocoding")
            return
        }
        
        // Check cache first
        if let cachedInfo = getCachedLocationInfo(for: coordinate) {
            print("DEBUG: Using cached location info: \(cachedInfo.displayName)")
            currentLocationInfo = cachedInfo
            return
        }
        
        // Send to debounced processing
        coordinateSubject.send(coordinate)
    }
    
    /// Clear current location info
    func clearLocationInfo() {
        currentLocationInfo = nil
        lastError = nil
    }
    
    /// Clear cache
    func clearCache() {
        locationCache.removeAll()
        print("DEBUG: Reverse geocoding cache cleared")
    }
    
    // MARK: - Private Methods
    
    private func performReverseGeocode(for coordinate: CLLocationCoordinate2D) {
        // Rate limiting
        let now = Date()
        guard now.timeIntervalSince(lastRequestTime) >= minimumRequestInterval else {
            print("DEBUG: Rate limiting reverse geocoding request")
            return
        }
        lastRequestTime = now
        
        // Cancel any existing task
        currentGeocodingTask?.cancel()
        
        // Check cache again (might have been populated since last check)
        if let cachedInfo = getCachedLocationInfo(for: coordinate) {
            currentLocationInfo = cachedInfo
            return
        }
        
        isLoading = true
        lastError = nil
        
        print("DEBUG: Starting reverse geocoding for: \(coordinate.latitude), \(coordinate.longitude)")
        
        currentGeocodingTask = Task { [weak self] in
            await self?.geocodeCoordinate(coordinate)
        }
    }
    
    @MainActor
    private func geocodeCoordinate(_ coordinate: CLLocationCoordinate2D) async {
        do {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            guard let placemark = placemarks.first else {
                print("DEBUG: No placemark found for coordinate")
                self.isLoading = false
                return
            }
            
            let locationInfo = LocationInfo(
                coordinate: coordinate,
                name: placemark.name ?? "Unknown Location",
                administrativeArea: placemark.administrativeArea,
                locality: placemark.locality,
                subLocality: placemark.subLocality,
                thoroughfare: placemark.thoroughfare
            )
            
            print("DEBUG: Reverse geocoding successful: \(locationInfo.displayName)")
            print("DEBUG: Full address: \(locationInfo.fullAddress)")
            
            // Cache the result
            self.cacheLocationInfo(locationInfo)
            
            // Update published properties
            self.currentLocationInfo = locationInfo
            self.isLoading = false
            self.lastError = nil
            
        } catch {
            print("DEBUG: Reverse geocoding failed: \(error.localizedDescription)")
            self.isLoading = false
            self.lastError = error
        }
    }
    
    // MARK: - Cache Management
    
    private func getCachedLocationInfo(for coordinate: CLLocationCoordinate2D) -> LocationInfo? {
        for (_, cachedInfo) in locationCache {
            let distance = coordinate.distance(to: cachedInfo.coordinate)
            if distance <= cacheRadius {
                return cachedInfo
            }
        }
        return nil
    }
    
    private func cacheLocationInfo(_ locationInfo: LocationInfo) {
        let key = cacheKey(for: locationInfo.coordinate)
        locationCache[key] = locationInfo
        
        // Trim cache if needed
        if locationCache.count > maxCacheSize {
            let keysToRemove = Array(locationCache.keys.prefix(locationCache.count - maxCacheSize))
            for key in keysToRemove {
                locationCache.removeValue(forKey: key)
            }
        }
    }
    
    private func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        return "\(String(format: "%.5f", coordinate.latitude))_\(String(format: "%.5f", coordinate.longitude))"
    }
    
    // MARK: - Utility Methods
    
    /// Get current cache size
    var cacheSize: Int {
        return locationCache.count
    }
    
    /// Check if service is currently geocoding
    var isGeocoding: Bool {
        return isLoading
    }
    
    deinit {
        currentGeocodingTask?.cancel()
        geocoder.cancelGeocode()
    }
}
