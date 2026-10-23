import Charts
import DesignSystem
import SwiftUI
import SyncEngine

/// How much has been listened to, and when.
struct StatsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var period: ListeningStatsCalculator.Period = .week
    @State private var stats: ListeningStats?
    @State private var isLoading = true

    var body: some View {
        List {
            Section {
                Picker(L("Period"), selection: Binding(
                    get: { PeriodChoice(period) },
                    set: { period = $0.period }
                )) {
                    ForEach(PeriodChoice.allCases, id: \.self) { choice in
                        Text(verbatim: choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if isLoading {
                Section { HStack { ProgressView(); Text(L("Working it out…")) } }
            } else if let stats, !stats.days.isEmpty {
                Section {
                    Chart(stats.days) { day in
                        BarMark(
                            x: .value(L("Day"), day.date, unit: .day),
                            y: .value(L("Hours"), day.seconds / 3600)
                        )
                        .foregroundStyle(Palette.accent)
                    }
                    .frame(height: 180)
                    .accessibilityLabel(L("Listening by day"))
                }

                Section {
                    row(L("Total"), Format.duration(stats.totalSeconds))
                    row(L("Books finished"), String(stats.itemsFinished))
                    row(L("Current streak"), L("\(stats.currentStreak) days"))
                    row(L("Longest streak"), L("\(stats.longestStreak) days"))
                    if stats.averageSecondsPerActiveDay > 0 {
                        row(L("Average on a listening day"),
                            Format.duration(stats.averageSecondsPerActiveDay))
                    }
                    if let best = stats.bestDay {
                        row(L("Best day"),
                            "\(best.date.formatted(date: .abbreviated, time: .omitted)) · \(Format.duration(best.seconds))")
                    }
                }
            } else {
                Section {
                    Text(L("Nothing listened to in this period yet."))
                        .foregroundStyle(Palette.secondaryText)
                }
            }

            if YearInBooks.isAvailable() {
                Section {
                    NavigationLink {
                        YearInBooksView(year: YearInBooks.year())
                    } label: {
                        Label(L("Your Year in Books"), systemImage: "sparkles")
                    }
                } footer: {
                    Text(L("Available through December."))
                }
            }
        }
        .navigationTitle(Text(L("Stats")))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: PeriodChoice(period)) { await load() }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent {
            Text(verbatim: value).foregroundStyle(Palette.secondaryText)
        } label: {
            Text(verbatim: label)
        }
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        isLoading = true
        stats = await environment.sync.stats(for: period)
        isLoading = false
    }

    enum PeriodChoice: Hashable, CaseIterable {
        case week, month, year

        init(_ period: ListeningStatsCalculator.Period) {
            switch period {
            case .week: self = .week
            case .month: self = .month
            default: self = .year
            }
        }

        var period: ListeningStatsCalculator.Period {
            switch self {
            case .week: .week
            case .month: .month
            case .year: .year
            }
        }

        var title: String {
            switch self {
            case .week: L("Week")
            case .month: L("Month")
            case .year: L("Year")
            }
        }
    }
}

/// The December recap, with a card the user can share.
struct YearInBooksView: View {
    let year: Int

    @Environment(AppEnvironment.self) private var environment
    @State private var stats: ListeningStats?
    @State private var shareURL: URL?
    @State private var isAppearing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                card
                    .scaleEffect(isAppearing || reduceMotion ? 1 : 0.92)
                    .opacity(isAppearing || reduceMotion ? 1 : 0)
                    .animation(Motion.animation(reduceMotion: reduceMotion), value: isAppearing)

                Button {
                    shareURL = renderCard()
                } label: {
                    Label(L("Share"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.s)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .padding(.horizontal, Spacing.xl)
                .disabled(stats == nil)

                Text(L("The card is drawn on your device. Nothing is uploaded."))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, Spacing.xl)
        }
        .navigationTitle(Text(verbatim: L("\(year) in Books")))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            stats = await environment.sync.stats(for: .calendarYear(year))
            isAppearing = true
        }
        .sheet(item: Binding(
            get: { shareURL.map { ExportFile(url: $0) } },
            set: { if $0 == nil { shareURL = nil } }
        )) { file in
            ShareSheet(items: [file.url])
        }
    }

    private var card: some View {
        YearInBooksCard(year: year, stats: stats)
            .frame(maxWidth: 340)
            .padding(.horizontal, Spacing.l)
    }

    /// Renders the card to a PNG, on device.
    private func renderCard() -> URL? {
        let renderer = ImageRenderer(content: YearInBooksCard(year: year, stats: stats).frame(width: 1080, height: 1350))
        renderer.scale = 1
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let url = URL.temporaryDirectory.appending(path: "Firelight \(year).png")
        try? data.write(to: url, options: .atomic)
        return url
    }
}

/// The shareable card itself, used for both the on-screen and rendered forms.
struct YearInBooksCard: View {
    let year: Int
    let stats: ListeningStats?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack {
                Image(systemName: "flame.fill")
                Text(verbatim: String(year))
                    .font(.system(.title2, design: .serif, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Palette.accent)

            if let stats {
                stat(L("hours listened"), String(format: "%.0f", stats.totalHours))
                stat(L("books finished"), String(stats.itemsFinished))
                stat(L("day streak"), String(stats.longestStreak))
            } else {
                ProgressView()
            }

            Spacer(minLength: 0)

            Text(L("Firelight"))
                .font(Typography.caption)
                .foregroundStyle(Palette.secondaryText)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(0.8, contentMode: .fit)
        .background(
            LinearGradient(
                colors: [Palette.background, Palette.ember.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: value)
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.primaryText)
            Text(verbatim: label)
                .font(Typography.body)
                .foregroundStyle(Palette.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}
