//
//  MapboxService.swift
//  Zenlyne
//
//  Created by admin on 14/3/25.
//

// Handle map-related functionalities
import Foundation
import CoreLocation

protocol LocationServiceProtocol {
    var delegate: LocationServiceDelegate? { get set }
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func requestLocationPermission()
}

protocol LocationServiceDelegate: AnyObject {
    func locationService(_ service: LocationServiceProtocol, didUpdateLocation location: CLLocation)
    func locationService(_ service: LocationServiceProtocol, didFailWithError error: Error)
    func locationService(_ service: LocationServiceProtocol, didChangeAuthorization status: CLAuthorizationStatus)
}

class LocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    weak var delegate: LocationServiceDelegate?
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Update if user moves 10 meters
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }
    
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        delegate?.locationService(self, didUpdateLocation: location)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        delegate?.locationService(self, didFailWithError: error)
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        delegate?.locationService(self, didChangeAuthorization: status)
    }
}
