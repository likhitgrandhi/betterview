import SwiftUI

struct SettingsView: View {
    @AppStorage(BVPreferenceKey.developerMode) private var developerMode = false
    @AppStorage(BVPreferenceKey.appearance) private var appearanceRaw = BVAppearance.light.rawValue

    private var appearance: Binding<BVAppearance> {
        Binding(
            get: { BVAppearance(rawValue: appearanceRaw) ?? .light },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: appearance) {
                    ForEach(BVAppearance.allCases) { value in
                        Text(value.label).tag(value)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            }

            Section {
                Toggle("Developer Mode", isOn: $developerMode)
                Text("Show file tree, raw tool labels, model picker, code-aware renderers, and multi-item tabs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Developer")
            }

            Section {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Engine", value: "Local `claude` CLI")
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 380)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        let build   = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
