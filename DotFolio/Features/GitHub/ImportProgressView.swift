import SwiftUI

/// Live import screen: GitHub/GitLab → DotFolio animation, progress, running
/// counters, and a terminal-style log of each repository.
struct ImportProgressView: View {
    let model: ConnectionFlowModel
    let done: Int
    let total: Int

    private var fraction: Double { Double(done) / Double(max(total, 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            HStack(spacing: DS.Space.l) {
                TransferGraphic(brand: model.host.brand)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Importing from \(model.host.name)")
                        .font(DS.Font.pageTitle)
                    Text("Reading each repository’s .env.example to list the variables it needs. Values are never imported.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: DS.Space.s) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .animation(.smooth, value: fraction)
                HStack {
                    Text("\(done) of \(total) repositories")
                        .monospacedDigit()
                    Spacer()
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            StatsRow(stats: model.importStats)

            ImportLog(entries: model.importLog, inFlight: model.inFlight)
                .frame(height: 260)

            HStack {
                Label("Projects imported so far are kept if you stop.", systemImage: "checkmark.shield")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Stop Import", action: model.stopImport)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                    .clickableCursor()
            }
        }
    }
}

/// Shown when the import ends (or is stopped).
struct ImportFinishedView: View {
    let model: ConnectionFlowModel
    let summary: ConnectionFlowModel.ImportSummary

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            HStack(spacing: DS.Space.l) {
                Image(systemName: summary.cancelled ? "pause.circle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(summary.cancelled ? AnyShapeStyle(DS.Status.warning) : AnyShapeStyle(DS.Status.success))
                    .symbolEffect(.bounce, value: summary.projects)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(summary.cancelled ? "Import stopped" : "Import complete")
                        .font(DS.Font.pageTitle)
                    Text("\(summary.projects) \(summary.projects == 1 ? "project is" : "projects are") ready. Add values to the variables marked Not set.")
                        .foregroundStyle(.secondary)
                }
            }

            StatsRow(stats: summary)

            ImportLog(entries: model.importLog, inFlight: [])
                .frame(height: 260)

            HStack {
                Spacer()
                Button(action: model.dismiss) {
                    Label("View Projects", systemImage: "arrow.right")
                        .labelStyle(.titleAndIcon)
                }
                .symbolMotion(.wiggleForward)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .clickableCursor()
            }
        }
    }
}

// MARK: - Pieces

/// Host mark (GitHub or GitLab) → animated dots → DotFolio mark.
private struct TransferGraphic: View {
    let brand: BrandMark

    var body: some View {
        HStack(spacing: DS.Space.s) {
            TintedIcon(tint: brand == .github ? DS.Palette.violet : DS.Palette.orange, size: 52) {
                brand.image.resizable().scaledToFit()
            }

            TimelineView(.animation(minimumInterval: 0.25)) { context in
                let phase = Int(context.date.timeIntervalSinceReferenceDate * 4) % 4
                HStack(spacing: DS.Space.xs) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .opacity(i == phase ? 1 : 0.25)
                    }
                }
            }
            .accessibilityHidden(true)

            AppMark(size: 52)
        }
    }
}

private struct StatsRow: View {
    let stats: ConnectionFlowModel.ImportSummary

    var body: some View {
        HStack(spacing: DS.Space.m) {
            StatTile(value: stats.projects, label: "Projects", symbol: "folder.badge.plus", tint: .accentColor)
            StatTile(value: stats.variables, label: "Variables found", symbol: "key.horizontal", tint: DS.Status.success)
            StatTile(value: stats.projects - stats.withEnvExample, label: "No .env.example", symbol: "doc.badge.ellipsis", tint: .secondary)
        }
    }
}

private struct StatTile: View {
    let value: Int
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: DS.Space.m) {
            TintedIcon(tint: tint, size: 34) {
                Image(systemName: symbol)
                    .resizable().scaledToFit().fontWeight(.medium)
                    // Bounces each time the count goes up during an import.
                    .symbolMotion(.bounce, value: value)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(value, format: .number)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText(value: Double(value)))
                    .animation(.smooth, value: value)
                Text(label).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity)
        .panel(radius: DS.Radius.medium, bordered: true)
        .accessibilityElement(children: .combine)
    }
}

/// Terminal-style log; auto-scrolls to the newest line.
private struct ImportLog: View {
    let entries: [ConnectionFlowModel.ImportLogEntry]
    let inFlight: [String]

    private static let background = Color(red: 0.08, green: 0.09, blue: 0.11)
    private static let green = Color(red: 0.38, green: 0.86, blue: 0.53)
    private static let dim = Color.white.opacity(0.45)
    private static let amber = Color(red: 0.98, green: 0.74, blue: 0.30)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("$ dotfolio import --from github")
                        .foregroundStyle(Self.dim)
                    ForEach(entries) { entry in
                        line(entry).id(entry.id)
                    }
                    ForEach(inFlight, id: \.self) { repo in
                        HStack(spacing: DS.Space.s) {
                            Spinner().foregroundStyle(Color.accentColor)
                            Text("fetching \(repo)/.env.example").foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.m)
            }
            .onChange(of: entries.count) { _, _ in
                withAnimation(.smooth) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .background(Self.background, in: RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: DS.Space.s) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.7)).frame(width: 8, height: 8) }
            }
            .padding(DS.Space.m)
            .accessibilityHidden(true)
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func line(_ entry: ConnectionFlowModel.ImportLogEntry) -> some View {
        HStack(spacing: DS.Space.s) {
            switch entry.outcome {
            case .keys(let count):
                Text("✓").foregroundStyle(Self.green)
                Text(entry.repo).foregroundStyle(.white)
                Text("\(count) \(count == 1 ? "key" : "keys")").foregroundStyle(Self.green)
            case .noEnvExample:
                Text("–").foregroundStyle(Self.dim)
                Text(entry.repo).foregroundStyle(.white.opacity(0.75))
                Text("no .env.example").foregroundStyle(Self.dim)
            case .unreadable:
                Text("!").foregroundStyle(Self.amber)
                Text(entry.repo).foregroundStyle(.white)
                Text("couldn’t read .env.example").foregroundStyle(Self.amber)
            }
        }
        .lineLimit(1)
        .truncationMode(.middle)
    }
}

/// Braille spinner, like CLI tools.
private struct Spinner: View {
    private static let frames = Array("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            let i = Int(context.date.timeIntervalSinceReferenceDate * 12.5) % Self.frames.count
            Text(String(Self.frames[i]))
        }
    }
}
