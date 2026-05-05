import SwiftUI

@main
struct BetterViewApp: App {
    @State private var env = AppEnvironment()
    @AppStorage(BVPreferenceKey.appearance) private var appearanceRaw = BVAppearance.light.rawValue

    init() {
        BVFont.register()
    }

    private var preferredScheme: ColorScheme? {
        BVAppearance(rawValue: appearanceRaw)?.preferred
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .preferredColorScheme(preferredScheme)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Item") {
                    Task { @MainActor in
                        if let id = env.activeWorkspaceID {
                            await env.newItem(in: id)
                        }
                    }
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open Command Palette") {
                    Task { @MainActor in
                        env.commandPaletteOpen = true
                    }
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Back to List") {
                    Task { @MainActor in env.backToList() }
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }

        Settings {
            SettingsView()
                .preferredColorScheme(preferredScheme)
        }
    }
}
