import SwiftUI

@main
struct TowerDefenseApp: App {
    /// Paylaşımlı tekil: GameSession init'i de aynı örnekten RunModifiers üretir.
    @StateObject private var catalogClient = CatalogClient.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(catalogClient)
                .task { await catalogClient.refresh() }
        }
        #if os(macOS)
        .defaultSize(width: 1320, height: 800)
        #endif
    }
}
