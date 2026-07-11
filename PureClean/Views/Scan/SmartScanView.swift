import SwiftUI

/// The Smart Scan experience: an idle hero, a live animated scanner with
/// real counters and ETA, a reviewable results screen, and a completion
/// celebration. All numbers come straight from the scan engine.
struct SmartScanView: View {
    @Environment(AppState.self) private var app
    @State private var showCleanConfirm = false

    private var engine: ScanEngine { app.scanner }

    var body: some View {
        Group {
            switch engine.progress.phase {
            case .idle:
                idleView
            case .scanning:
                scanningView
            case .results, .cleaning:
                resultsView
            case .finished:
                finishedView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: engine.progress.phase)
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 26) {
            Spacer()
            ScannerRing(fraction: 0, idle: true) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.brandGradient)
            }
            VStack(spacing: 8) {
                Text("Smart Scan")
                    .font(.system(size: 26, weight: .bold))
                Text("Inspects caches, logs, temporary files, app leftovers,\nbroken links and more. Personal files are never touched.")
                    .font(Theme.body())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            PrimaryGradientButton(title: "Start Smart Scan", icon: "sparkles", fullWidth: false) {
                app.runSmartScan()
            }
            if let last = engine.lastScanDate {
                Text("Last scan \(last.formatted(date: .abbreviated, time: .shortened))")
                    .font(Theme.footnote())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Spacer()
        }
        .padding(Theme.pagePadding)
    }

    // MARK: - Scanning

    private var scanningView: some View {
        let progress = engine.progress
        return VStack(spacing: 24) {
            Spacer()

            ScannerRing(fraction: progress.fraction, idle: false) {
                VStack(spacing: 2) {
                    Text("\(Int((progress.fraction * 100).rounded()))%")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .animatedNumber(Int(progress.fraction * 100))
                    Text("\(progress.filesScanned.formatted()) files")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .animatedNumber(progress.filesScanned)
                }
            }

            VStack(spacing: 6) {
                Text(progress.currentCategory.isEmpty ? "Preparing…" : progress.currentCategory)
                    .font(.system(size: 15, weight: .semibold))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: progress.currentCategory)
                Text(progress.currentPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 460)
                    .frame(height: 14)
            }

            HStack(spacing: 12) {
                scanStat(icon: "doc.text.magnifyingglass", label: "Files scanned",
                         value: progress.filesScanned.formatted())
                scanStat(icon: "trash", label: "Junk found",
                         value: progress.bytesFound.bytesFormatted)
                scanStat(icon: "clock", label: "Remaining",
                         value: progress.etaSeconds.map { $0.etaFormatted } ?? "estimating…")
            }

            Button("Cancel Scan") {
                engine.cancelScan()
            }
            .controlSize(.large)

            Spacer()
            Spacer()
        }
        .padding(Theme.pagePadding)
    }

    private func scanStat(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(Theme.footnote())
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .animatedNumber(value)
        }
        .frame(width: 150)
        .glassCard(padding: 12)
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.gridSpacing) {
                    PageHeader("Scan Complete",
                               subtitle: "\(engine.recoverableTotal.bytesFormatted) can be recovered across \(engine.categories.filter { $0.size > 0 || !$0.items.isEmpty }.count) categories.") {
                        Button {
                            app.runSmartScan()
                        } label: {
                            Label("Rescan", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.large)
                        .disabled(engine.isCleaning)
                    }

                    HStack(alignment: .top, spacing: Theme.gridSpacing) {
                        VStack(spacing: 8) {
                            ForEach(categoryBinding) { $category in
                                CategoryResultRow(category: $category,
                                                  disabled: engine.isCleaning)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        if !engine.insights.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel(title: "Insights")
                                ForEach(engine.insights) { insight in
                                    InsightRow(insight: insight)
                                }
                            }
                            .frame(width: 290)
                        }
                    }
                }
                .padding(Theme.pagePadding)
                .padding(.bottom, 8)
            }

            Divider().opacity(0.5)
            footer
        }
        .confirmationDialog(
            "Clean \(engine.recoverableSelected.bytesFormatted)?",
            isPresented: $showCleanConfirm, titleVisibility: .visible
        ) {
            Button("Clean Selected Items", role: .destructive) {
                Task { _ = await engine.clean() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Items are moved to the Trash whenever possible so you can restore them. Personal files are never touched.")
        }
    }

    private var categoryBinding: Binding<[ScanCategory]> {
        Bindable(app.scanner).categories
    }

    private var footer: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(engine.recoverableSelected.bytesFormatted)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .animatedNumber(engine.recoverableSelected)
                Text("selected to recover")
                    .font(Theme.footnote())
                    .foregroundStyle(.secondary)
            }
            if engine.isCleaning {
                ProgressView(value: engine.progress.fraction)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 260)
            }
            Spacer()
            PrimaryGradientButton(
                title: engine.isCleaning ? "Cleaning…" : "Clean",
                icon: "sparkles",
                isBusy: engine.isCleaning,
                fullWidth: false
            ) {
                showCleanConfirm = true
            }
            .disabled(engine.recoverableSelected == 0 && !engine.isCleaning)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 14)
        .background(.bar)
    }

    // MARK: - Finished

    private var finishedView: some View {
        VStack(spacing: 20) {
            Spacer()
            SuccessSeal()
            VStack(spacing: 6) {
                Text("Recovered \((engine.lastResult?.freedBytes ?? 0).bytesFormatted)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("\(engine.lastResult?.removedItems ?? 0) items cleaned\((engine.lastResult?.failedItems ?? 0) > 0 ? " · \(engine.lastResult!.failedItems) skipped" : "") — restorable from the Trash.")
                    .font(Theme.body())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button("Done") {
                    engine.reset()
                    withAnimation { app.route = .dashboard }
                }
                .controlSize(.large)
                PrimaryGradientButton(title: "Scan Again", icon: "sparkles", fullWidth: false) {
                    app.runSmartScan()
                }
            }
            Spacer()
            Spacer()
        }
        .padding(Theme.pagePadding)
    }
}

// MARK: - Category row

private struct CategoryResultRow: View {
    @Binding var category: ScanCategory
    let disabled: Bool
    @State private var expanded = false
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                CheckCircle(isOn: $category.isSelected)
                    .disabled(disabled || category.items.isEmpty)
                IconBadge(systemName: category.icon,
                          tint: category.safety == .safe ? .blue : .orange, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(category.name)
                            .font(.system(size: 12.5, weight: .semibold))
                        if category.safety == .review {
                            Badge(text: "Review", color: .orange)
                        }
                    }
                    Text(category.detail)
                        .font(Theme.footnote())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(category.size.bytesFormatted)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(category.size > 0 ? .primary : .tertiary)
                        .animatedNumber(category.size)
                    if category.fileCount > 0 {
                        Text("\(category.fileCount.formatted()) files")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                    }
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .opacity(category.items.isEmpty ? 0 : 1)
            }
            .padding(11)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !category.items.isEmpty else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    expanded.toggle()
                }
            }

            if expanded {
                VStack(spacing: 4) {
                    ForEach(category.items.prefix(6)) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "doc")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text(item.url.lastPathComponent)
                                .font(.system(size: 10.5))
                                .lineLimit(1)
                            Text(item.url.deletingLastPathComponent().abbreviatedPath)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(item.size.bytesFormatted)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if category.items.count > 6 {
                        Text("+ \(category.items.count - 6) more items")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 11)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.primary.opacity(hovering ? 0.1 : 0.05)))
        .onHover { hovering = $0 }
        .opacity(category.items.isEmpty && category.size == 0 ? 0.55 : 1)
    }
}

private struct CheckCircle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isOn.toggle() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(isOn ? .clear : Color.secondary.opacity(0.5), lineWidth: 1.5)
                    .background(Circle().fill(isOn ? AnyShapeStyle(Theme.brandGradient)
                                                   : AnyShapeStyle(.clear)))
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
    }
}

struct InsightRow: View {
    @Environment(AppState.self) private var app
    let insight: Insight
    @State private var hovering = false

    var body: some View {
        Button {
            if let route = insight.route {
                withAnimation { app.route = route }
            }
        } label: {
            HStack(alignment: .top, spacing: 9) {
                IconBadge(systemName: insight.icon, tint: insight.tint, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .multilineTextAlignment(.leading)
                    Text(insight.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if insight.route != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
            .padding(11)
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(hovering ? 0.1 : 0.05)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Scanner animation

/// The animated radial scanner: a soft breathing glow, expanding pulse
/// rings, a continuously orbiting comet sweep and the real progress arc.
struct ScannerRing<Center: View>: View {
    let fraction: Double
    let idle: Bool
    @ViewBuilder let center: () -> Center

    @State private var pulse = false

    var body: some View {
        ZStack {
            // Breathing glow.
            Circle()
                .fill(RadialGradient(colors: [.purple.opacity(0.35), .blue.opacity(0.12), .clear],
                                     center: .center, startRadius: 10, endRadius: 150))
                .frame(width: 300, height: 300)
                .scaleEffect(pulse ? 1.08 : 0.92)
                .blur(radius: 18)

            // Expanding pulse rings while scanning.
            if !idle {
                PulseRings()
            }

            // Track.
            Circle()
                .stroke(.quaternary.opacity(0.55), lineWidth: 10)
                .frame(width: 210, height: 210)

            // Real progress arc.
            Circle()
                .trim(from: 0, to: max(idle ? 0 : 0.004, min(1, fraction)))
                .stroke(
                    AngularGradient(colors: [.blue, .purple],
                                    center: .center,
                                    startAngle: .degrees(0),
                                    endAngle: .degrees(360 * max(0.004, fraction))),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 210, height: 210)
                .animation(.easeOut(duration: 0.45), value: fraction)
                .shadow(color: .purple.opacity(0.5), radius: 6)

            // Orbiting comet sweep.
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                let angle = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: idle ? 9 : 1.6) / (idle ? 9 : 1.6) * 360
                Circle()
                    .trim(from: 0, to: 0.16)
                    .stroke(
                        AngularGradient(colors: [.clear, idle ? .blue.opacity(0.6) : .cyan],
                                        center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(58)),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 210, height: 210)
                    .rotationEffect(.degrees(angle))
            }

            center()
        }
        .frame(width: 300, height: 300)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

/// Two staggered rings that expand and fade forever while scanning.
private struct PulseRings: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ring(delay: 0)
            ring(delay: 1.1)
        }
        .onAppear { animate = true }
    }

    private func ring(delay: Double) -> some View {
        Circle()
            .stroke(Theme.brandGradientHorizontal, lineWidth: 1.5)
            .frame(width: 210, height: 210)
            .scaleEffect(animate ? 1.45 : 1)
            .opacity(animate ? 0 : 0.7)
            .animation(
                .easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(delay),
                value: animate)
    }
}

/// Springy success checkmark for the finished state.
private struct SuccessSeal: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.green.opacity(0.3), .clear],
                                     center: .center, startRadius: 5, endRadius: 90))
                .frame(width: 180, height: 180)
                .blur(radius: 10)
            Circle()
                .fill(.green.gradient)
                .frame(width: 96, height: 96)
                .shadow(color: .green.opacity(0.45), radius: 16, y: 6)
            Image(systemName: "checkmark")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.white)
        }
        .scaleEffect(appeared ? 1 : 0.4)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                appeared = true
            }
        }
    }
}
