import SwiftUI

@main
struct DeckLinkApp: App {
    @StateObject private var link = PCLink()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(link)
                .onOpenURL { link.pair(from: $0) }
        }
    }
}
