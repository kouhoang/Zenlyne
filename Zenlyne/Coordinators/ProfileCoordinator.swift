//
//  ProfileCoordinator 2.swift
//  Zenlyne
//
//  Created by admin on 2/6/25.
//

import SwiftUI
import Combine

// MARK: - Profile Coordinator
class ProfileCoordinator: ObservableObject {
    @Published var isShowingProfile = false
    @Published var isShowingSettings = false
    @Published var currentSettingsView: SettingsView?
    
    private var cancellables = Set<AnyCancellable>()
    
    enum SettingsView {
        case privacy
        case notifications
        case help
    }
    
    func showProfile() {
        isShowingProfile = true
    }
    
    func hideProfile() {
        isShowingProfile = false
    }
    
    func showSettings(_ view: SettingsView) {
        currentSettingsView = view
        isShowingSettings = true
    }
    
    func hideSettings() {
        isShowingSettings = false
        currentSettingsView = nil
    }
    
    @ViewBuilder
    func settingsDestination() -> some View {
        switch currentSettingsView {
        case .privacy:
            PrivacySettingsView()
        case .notifications:
            NotificationSettingsView()
        case .help:
            HelpSupportView()
        case .none:
            EmptyView()
        }
    }
}
