//
//  LocationService.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

import Foundation
import CoreLocation
import Combine
import SwiftUICore

// MARK: - Protocol (Giữ nguyên để tương thích)
protocol LocationServiceProtocol {
    var delegate: LocationServiceDelegate? { get set }
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func requestLocationPermission()
    func requestAlwaysAuthorization()
    
    // New Combine methods
    var locationPublisher: AnyPublisher<CLLocation, LocationError> { get }
    var authorizationStatusPublisher: AnyPublisher<LocationAuthorizationStatus, Never> { get }
    var isUpdatingLocationPublisher: AnyPublisher<Bool, Never> { get }
    var isLocationServicesEnabledPublisher: AnyPublisher<Bool, Never> { get } // ✅ Thêm mới
}

protocol LocationServiceDelegate: AnyObject {
    func locationService(_ service: LocationServiceProtocol, didUpdateLocation location: CLLocation)
    func locationService(_ service: LocationServiceProtocol, didFailWithError error: Error)
    func locationService(_ service: LocationServiceProtocol, didChangeAuthorization status: CLAuthorizationStatus)
}

class LocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {
    
    // MARK: - Properties
    private let locationManager = CLLocationManager()
    weak var delegate: LocationServiceDelegate?
    
    // Combine subjects
    private let locationSubject = PassthroughSubject<CLLocation, LocationError>()
    private let authorizationSubject = CurrentValueSubject<LocationAuthorizationStatus, Never>(.notDetermined)
    private let isUpdatingSubject = CurrentValueSubject<Bool, Never>(false)
    private let isLocationServicesEnabledSubject = CurrentValueSubject<Bool, Never>(false) // ✅ Thêm mới
    
    // Internal state
    private var isRequestingLocation = false
    private var lastKnownLocation: CLLocation?
    private var locationTimeout: Timer?
    private let timeoutInterval: TimeInterval = 15.0
    private var pendingLocationRequest = false
    
    // MARK: - Combine Publishers
    var locationPublisher: AnyPublisher<CLLocation, LocationError> {
        locationSubject
            .filter { [weak self] location in
                // Filter out locations that are too old or inaccurate
                guard let self = self else { return false }
                return self.isLocationValid(location)
            }
            .eraseToAnyPublisher()
    }
    
    var authorizationStatusPublisher: AnyPublisher<LocationAuthorizationStatus, Never> {
        authorizationSubject
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    var isUpdatingLocationPublisher: AnyPublisher<Bool, Never> {
        isUpdatingSubject
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    // Add publisher to check location services status
    var isLocationServicesEnabledPublisher: AnyPublisher<Bool, Never> {
        isLocationServicesEnabledSubject
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupLocationManager()
        
        // Set initial authorization status
        let initialStatus = locationManager.authorizationStatus
        authorizationSubject.send(LocationAuthorizationStatus(from: initialStatus))
        
        // Check initial location services status safely
        updateLocationServicesStatus(for: initialStatus)
    }
    
    // MARK: - Setup
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Update if user moves 10 meters
        
        // Configure for background updates if permission allows
        if Bundle.main.object(forInfoDictionaryKey: "NSLocationAlwaysAndWhenInUseUsageDescription") != nil {
            locationManager.allowsBackgroundLocationUpdates = false // ✅ Set to false initially
        }
        
        locationManager.pausesLocationUpdatesAutomatically = false
    }
    
    // Add method yo update location services status based on authorization
    private func updateLocationServicesStatus(for authStatus: CLAuthorizationStatus) {
        let isEnabled: Bool
        
        switch authStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            // Only check when authorized
            isEnabled = true
        case .denied, .restricted:
            isEnabled = false
        case .notDetermined:
            isEnabled = false
        @unknown default:
            isEnabled = false
        }
        
        isLocationServicesEnabledSubject.send(isEnabled)
    }
    
    // MARK: - Public Methods (Refactored)
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }
    
    func startUpdatingLocation() {
        
        let status = locationManager.authorizationStatus
        
        // Check authorization status thay vì direct locationServicesEnabled
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("DEBUG: Starting location updates")
            isRequestingLocation = true
            isUpdatingSubject.send(true)
            
            locationManager.startUpdatingLocation()
            setupLocationTimeout()
            
        case .denied, .restricted:
            print("DEBUG: Location permission denied")
            locationSubject.send(completion: .failure(.permissionDenied))
            return
            
        case .notDetermined:
            print("DEBUG: Location permission not determined, requesting...")
            pendingLocationRequest = true
            requestLocationPermission()
            return
            
        @unknown default:
            print("DEBUG: Unknown authorization status")
            locationSubject.send(completion: .failure(.permissionDenied))
            return
        }
    }
    
    func stopUpdatingLocation() {
        print("DEBUG: Stopping location updates")
        locationManager.stopUpdatingLocation()
        isRequestingLocation = false
        pendingLocationRequest = false
        isUpdatingSubject.send(false)
        
        cancelLocationTimeout()
    }
    
    // MARK: - New Combine Methods
    
    /// Get a single location update
    func requestSingleLocationUpdate() -> AnyPublisher<CLLocation, LocationError> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(.unknown(NSError(domain: "LocationService", code: -1))))
                return
            }
            
            // Check if we have a recent location
            if let lastLocation = self.lastKnownLocation,
               abs(lastLocation.timestamp.timeIntervalSinceNow) < 30 {
                promise(.success(lastLocation))
                return
            }
            
            // Request new location
            let cancellable = self.locationPublisher
                .first()
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            promise(.failure(error))
                        }
                    },
                    receiveValue: { location in
                        promise(.success(location))
                    }
                )
            
            self.startUpdatingLocation()
            
            // Auto-stop after getting location
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                cancellable.cancel()
                self.stopUpdatingLocation()
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Check if location services are available and authorized
    func checkLocationAvailability() -> AnyPublisher<Bool, Never> {
        // Combine both 2 publishers without direct check
        return Publishers.CombineLatest(
            authorizationStatusPublisher,
            isLocationServicesEnabledPublisher
        )
        .map { authStatus, isEnabled in
            return isEnabled && (authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways)
        }
        .eraseToAnyPublisher()
    }
    
    /// Get current authorization status
    var currentAuthorizationStatus: LocationAuthorizationStatus {
        return authorizationSubject.value
    }
    
    // MARK: - Private Methods
    
    private func setupLocationTimeout() {
        cancelLocationTimeout()
        
        locationTimeout = Timer.scheduledTimer(withTimeInterval: timeoutInterval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            if self.isRequestingLocation {
                print("DEBUG: Location request timed out")
                self.locationSubject.send(completion: .failure(.timeout))
                self.stopUpdatingLocation()
            }
        }
    }
    
    private func cancelLocationTimeout() {
        locationTimeout?.invalidate()
        locationTimeout = nil
    }
    
    private func isLocationValid(_ location: CLLocation) -> Bool {
        // Check location age (not older than 5 seconds)
        let locationAge = abs(location.timestamp.timeIntervalSinceNow)
        guard locationAge < 5.0 else {
            print("DEBUG: Location too old: \(locationAge) seconds")
            return false
        }
        
        // Check horizontal accuracy
        guard location.horizontalAccuracy < 100 && location.horizontalAccuracy > 0 else {
            print("DEBUG: Location accuracy too low: \(location.horizontalAccuracy)")
            return false
        }
        
        return true
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        print("DEBUG: Received location update: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        
        // Store last known location
        lastKnownLocation = location
        
        // Validate location
        guard isLocationValid(location) else {
            return
        }
        
        // Cancel timeout since we got a valid location
        cancelLocationTimeout()
        
        // Send to delegate (original interface)
        delegate?.locationService(self, didUpdateLocation: location)
        
        // Send to Combine subscribers
        locationSubject.send(location)
        
        print("DEBUG: Valid location update sent: \(location.coordinate.latitude), \(location.coordinate.longitude)")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("DEBUG: Location manager failed with error: \(error.localizedDescription)")
        
        // Cancel timeout
        cancelLocationTimeout()
        
        // Send to delegate (original interface)
        delegate?.locationService(self, didFailWithError: error)
        
        // Send to Combine subscribers
        let locationError: LocationError
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                locationError = .permissionDenied
            case .locationUnknown:
                locationError = .locationUnavailable
            case .network:
                locationError = .locationUnavailable
            default:
                locationError = .unknown(error)
            }
        } else {
            locationError = .unknown(error)
        }
        
        locationSubject.send(completion: .failure(locationError))
        
        // Stop updating on error
        stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("DEBUG: Location authorization status changed: \(status.rawValue)")
        
        let authStatus = LocationAuthorizationStatus(from: status)
        
        // Send to delegate (original interface)
        delegate?.locationService(self, didChangeAuthorization: status)
        
        // Send to Combine subscribers
        authorizationSubject.send(authStatus)
        
        // Update location services status based on authorization
        updateLocationServicesStatus(for: status)
        
        // Handle authorization changes
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            // Enable background location updates if authorized always
            if status == .authorizedAlways {
                locationManager.allowsBackgroundLocationUpdates = true
            }
            
            // Auto-start if there was a pending request
            if pendingLocationRequest {
                pendingLocationRequest = false
                startUpdatingLocation()
            } else if isRequestingLocation {
                locationManager.startUpdatingLocation()
            }
            
        case .denied, .restricted:
            stopUpdatingLocation()
            locationSubject.send(completion: .failure(.permissionDenied))
            
        case .notDetermined:
            // Wait for user decision
            break
            
        @unknown default:
            break
        }
    }
    
    // MARK: - Utility Methods
    
    /// Calculate distance between two coordinates
    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation)
    }
    
    /// Check if coordinate is valid
    static func isValidCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        return CLLocationCoordinate2DIsValid(coordinate) &&
               coordinate.latitude != 0 &&
               coordinate.longitude != 0
    }
}

// MARK: - Extensions (Giữ nguyên)
extension CLLocationCoordinate2D {
    var isValid: Bool {
        return LocationService.isValidCoordinate(self)
    }
    
    func toUserLocation(timestamp: TimeInterval = Date().timeIntervalSince1970) -> UserLocation {
        return UserLocation(coordinate: self, timestamp: timestamp)
    }
    
    var formattedString: String {
        return String(format: "%.5f, %.5f", latitude, longitude)
    }
}

extension UserLocation {
    func isExpired(expirationTime: TimeInterval = 72 * 60 * 60) -> Bool {
        let currentTime = Date().timeIntervalSince1970
        return (currentTime - self.timestamp) >= expirationTime
    }
    
    var ageString: String {
        let age = self.age
        
        if age < 60 {
            return "Vừa xong"
        } else if age < 3600 {
            let minutes = Int(age / 60)
            return "\(minutes) phút trước"
        } else if age < 86400 {
            let hours = Int(age / 3600)
            return "\(hours) giờ trước"
        } else {
            let days = Int(age / 86400)
            return "\(days) ngày trước"
        }
    }
}

extension CLLocation {
    var coordinateString: String {
        return coordinate.formattedString
    }
    
    func isRecent(within timeInterval: TimeInterval = 300) -> Bool {
        return abs(timestamp.timeIntervalSinceNow) <= timeInterval
    }
}

extension View {
    func backdrop(_ color: Color) -> some View {
        self.background(color.opacity(0.1))
    }
}
