import FlowBridgeShared
import SwiftUI

@main
struct FlowBridgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var coordinator = FlowBridgeCoordinator.shared
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: FlowBridgeConstants.onboardingCompletedKey)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .task {
                    await coordinator.bootstrap()
                }
                .onOpenURL { _ in
                    Task { await coordinator.consumePendingCommand() }
                }
                .onChange(of: scenePhase) { _, phase in
                    Task { await coordinator.handleScenePhase(phase) }
                }
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView {
                        showOnboarding = false
                    }
                }
        }
    }
}
