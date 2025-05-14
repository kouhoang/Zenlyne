//
// ZenlyneApp.swift
// Zenlyne
//
// Created by admin on 14/3/25.
//

import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseMessaging
import BackgroundTasks
import CoreLocation
import UIKit

@main
struct ZenlyneApp: App {
    @StateObject var viewModel = AuthViewModel()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    if Auth.auth().currentUser != nil {
                        appDelegate.setUserOnline()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    if Auth.auth().currentUser != nil {
                        appDelegate.updateLastSeen()
                    }
                }
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, UIApplicationDelegate {
    let locationManager = CLLocationManager()
    var firebaseService = FirebaseService()
    private var userActivityTimer: Timer?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Set up Firebase Messaging
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        
        // Request permission for notifications
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            print("DEBUG: Notification permission granted: \(granted)")
            if let error = error {
                print("DEBUG: Notification permission error: \(error.localizedDescription)")
            }
        }
        
        // Register for remote notifications
        application.registerForRemoteNotifications()
        
        // Configure background tasks
        registerBackgroundTasks()
        
        scheduleLocationCleanUp()
        
        return true
    }
    
//    func applicationWillTerminate(_ application: UIApplication) {
//        // Set user as offline when app terminates
//        if let userId = Auth.auth().currentUser?.uid {
//            firebaseService.setUserOnlineStatus(userId: userId, isOnline: false)
//        }
//    }
//    
//    func applicationDidEnterBackground(_ application: UIApplication) {
//        scheduleAppRefresh()
//        scheduleBGProcessingTask()
//    }
    
    // MARK: - Background Tasks
    
    func registerBackgroundTasks() {
        // Register background location update task
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.zenlyne.locationUpdate", using: nil) { task in
            self.handleLocationUpdateTask(task: task as! BGProcessingTask)
        }
        
        // Register background app refresh task
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.zenlyne.appRefresh", using: nil) { task in
            self.handleAppRefreshTask(task: task as! BGAppRefreshTask)
        }
    }
    
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.zenlyne.appRefresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("DEBUG: Background app refresh scheduled")
        } catch {
            print("DEBUG: Could not schedule app refresh: \(error.localizedDescription)")
        }
    }
    
    func scheduleBGProcessingTask() {
        let request = BGProcessingTaskRequest(identifier: "com.zenlyne.locationUpdate")
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("DEBUG: Background processing task scheduled")
        } catch {
            print("DEBUG: Could not schedule processing task: \(error.localizedDescription)")
        }
    }
    
    func handleAppRefreshTask(task: BGAppRefreshTask) {
        // Create a task that updates user location
        scheduleAppRefresh() // Schedule the next refresh
        
        // Update location if user is logged in
        if let userId = Auth.auth().currentUser?.uid {
            updateLocationInBackground(userId: userId) {
                task.setTaskCompleted(success: true)
            }
        } else {
            task.setTaskCompleted(success: false)
        }
        
        // Set up a timeout
        let timeoutWorkItem = DispatchWorkItem {
            task.setTaskCompleted(success: false)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeoutWorkItem)
        
        // Cancel timeout if task completes successfully
        task.expirationHandler = {
            timeoutWorkItem.cancel()
        }
    }
    
    func handleLocationUpdateTask(task: BGProcessingTask) {
        // Schedule the next task
        scheduleBGProcessingTask()
        
        // Update location if user is logged in
        if let userId = Auth.auth().currentUser?.uid {
            updateLocationInBackground(userId: userId) {
                task.setTaskCompleted(success: true)
            }
        } else {
            task.setTaskCompleted(success: false)
        }
        
        // Set up a timeout
        let timeoutWorkItem = DispatchWorkItem {
            task.setTaskCompleted(success: false)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeoutWorkItem)
        
        // Cancel timeout if task completes successfully
        task.expirationHandler = {
            timeoutWorkItem.cancel()
        }
    }
    
    func updateLocationInBackground(userId: String, completion: @escaping () -> Void) {
        // Get the current location
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters // Lower accuracy for background
        locationManager.requestLocation()
        
        // Create a timeout
        let timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
            completion()
        }
        
        // Set up location manager callback
        locationManager.delegate = BackgroundLocationDelegate(userId: userId, firebaseService: firebaseService) {
            timer.invalidate()
            completion()
        }
    }
    
    func scheduleLocationCleanUp() {
        let timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.firebaseService.cleanupExpiredLocations()
        }
        timer.tolerance = 5 * 60
    }
    
    func setUserOnline() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        print("DEBUG: Setting user online: \(userId)")
        
        firebaseService.setUserOnlineStatus(userId: userId, isOnline: true)
        
        setupPeriodicStatusUpdates()
    }

    // Update lastSeen timestamp but keep user online
    func updateLastSeen() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        print("DEBUG: Updating user last seen: \(userId)")
        
        // Update in Firestore
        let db = Firestore.firestore()
        db.collection("users").document(userId).updateData([
            "lastSeen": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("DEBUG: Error updating lastSeen: \(error.localizedDescription)")
            }
        }
    }

    // Set user as offline
    func setUserOffline() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        print("DEBUG: Setting user offline: \(userId)")
        
        // Use your existing firebaseService
        firebaseService.setUserOnlineStatus(userId: userId, isOnline: false)
    }

    func setupPeriodicStatusUpdates() {
        // Cancel any existing timer
        stopPeriodicStatusUpdates()
        
        // Create a timer that updates the lastSeen time every minute
        userActivityTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self, Auth.auth().currentUser != nil else { return }
            
            self.updateLastSeen()
        }
    }

    func stopPeriodicStatusUpdates() {
        userActivityTimer?.invalidate()
        userActivityTimer = nil
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        setUserOnline()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        setUserOnline()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        updateLastSeen()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        updateLastSeen()
        scheduleAppRefresh()
        scheduleBGProcessingTask()
        
        stopPeriodicStatusUpdates()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        setUserOffline()
        stopPeriodicStatusUpdates()
    }
}

// MARK: - Firebase Messaging Delegate
extension AppDelegate: MessagingDelegate, UNUserNotificationCenterDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("DEBUG: Firebase registration token: \(fcmToken ?? "nil")")
        
        if let token = fcmToken {
            // Store token in Firestore if user is logged in
            if let userId = Auth.auth().currentUser?.uid {
                let db = Firestore.firestore()
                db.collection("users").document(userId).updateData([
                    "fcmToken": token
                ]) { error in
                    if let error = error {
                        print("DEBUG: Error updating FCM token: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .badge, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

// MARK: - Background Location Delegate
class BackgroundLocationDelegate: NSObject, CLLocationManagerDelegate {
    private let userId: String
    private let firebaseService: FirebaseServiceProtocol
    private let completion: () -> Void
    
    init(userId: String, firebaseService: FirebaseServiceProtocol, completion: @escaping () -> Void) {
        self.userId = userId
        self.firebaseService = firebaseService
        self.completion = completion
        super.init()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            completion()
            return
        }
        
        let userLocation = UserLocation(coordinate: location.coordinate)
        firebaseService.saveUserLocation(userId: userId, location: userLocation)
        firebaseService.setUserOnlineStatus(userId: userId, isOnline: true)
        completion()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("DEBUG: Background location error: \(error.localizedDescription)")
        completion()
    }
}
