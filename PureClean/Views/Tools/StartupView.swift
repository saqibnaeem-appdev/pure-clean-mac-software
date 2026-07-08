import SwiftUI

struct StartupView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            if app.startup.items.isEmpty {
                ContentUnavailableView(
                    "No user launch agents",
                    systemImage: "power",
                    description: Text("Apps you install can add launch agents here. Modern background items live in System Settings."))
                .frame(maxHeight: .infinity)
            } else {
                List(app.startup.items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label)
                                .font(.system(size: 11.5, weight: .medium))
                                .lineLimit(1)
                            Text(item.programPath)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { item.isEnabled },
                            set: { app.startup.setEnabled($0, for: item) }))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                }
                .listStyle(.plain)
            }

            Divider()
            HStack {
                Text("Login items added by apps are managed by macOS.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open System Settings…") {
                    app.startup.openSystemLoginItems()
                }
                .controlSize(.small)
            }
            .padding(10)
        }
        .navigationTitle("Startup Items")
        .onAppear { app.startup.scan() }
    }
}
