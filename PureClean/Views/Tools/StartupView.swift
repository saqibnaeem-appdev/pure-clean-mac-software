import SwiftUI

struct StartupView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.gridSpacing) {
                PageHeader("Login Items",
                           subtitle: "User launch agents PureClean can manage. Disabling is fully reversible.") {
                    Button {
                        app.startup.openSystemLoginItems()
                    } label: {
                        Label("System Login Items…", systemImage: "gearshape.arrow.triangle.2.circlepath")
                    }
                    .controlSize(.large)
                }
            }
            .padding(Theme.pagePadding)

            if app.startup.items.isEmpty {
                ContentUnavailableView(
                    "No user launch agents",
                    systemImage: "power",
                    description: Text("Apps you install can add launch agents here. Modern background items live in System Settings → General → Login Items."))
                .frame(maxHeight: .infinity)
            } else {
                List(app.startup.items) { item in
                    HStack(spacing: 10) {
                        IconBadge(systemName: "power",
                                  tint: item.isEnabled ? .green : .gray, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label)
                                .font(.system(size: 12.5, weight: .medium))
                                .lineLimit(1)
                            Text(item.programPath)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Badge(text: item.isEnabled ? "Runs at login" : "Disabled",
                              color: item.isEnabled ? .green : .secondary)
                        Toggle("", isOn: Binding(
                            get: { item.isEnabled },
                            set: { app.startup.setEnabled($0, for: item) }))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                    .padding(.vertical, 3)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .onAppear { app.startup.scan() }
    }
}
