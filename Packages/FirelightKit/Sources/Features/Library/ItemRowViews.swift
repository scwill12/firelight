import DesignSystem
import Persistence
import SwiftUI

/// Formatting shared by every library screen.
enum Format {
    /// "12h 40m", "48m", "45s", "—". Hours and minutes for anything of real
    /// length, because nobody chooses a book by its seconds — but a short
    /// chapter is a real thing, and rounding an eight-second credits chapter
    /// to "0m" tells the reader nothing.
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        guard total >= 60 else { return "\(total)s" }
        let totalMinutes = total / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    /// ABS calls the field a year but will happily put a whole ISO timestamp
    /// in it, which reached the screen as "2024-07-26T00:00:00". Take the year
    /// and leave the rest.
    static func publicationYear(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let leadingDigits = trimmed.prefix { $0.isNumber }
        return leadingDigits.count >= 4 ? String(leadingDigits.prefix(4)) : trimmed
    }

    /// Spoken form, so VoiceOver says "twelve hours forty minutes".
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        return formatter.string(from: seconds) ?? ""
    }
}

/// A cover with its title underneath, as it appears on a shelf.
struct CoverCard: View {
    let item: LibraryItemSummary
    var width: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            CoverImage(itemID: item.id, title: item.title)
                .frame(width: width, height: CoverArt.height(forWidth: width))
                .overlay(alignment: .bottom) {
                    if item.progressFraction > 0.001 && !item.isFinished {
                        ProgressView(value: item.progressFraction)
                            .tint(Palette.accent)
                            .scaleEffect(x: 1, y: 0.6, anchor: .bottom)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.bottom, Spacing.xs)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if item.isFinished {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white, Palette.accent)
                            .padding(Spacing.xs)
                    }
                }

            Text(verbatim: item.title)
                .font(Typography.itemSubtitle)
                .foregroundStyle(Palette.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let author = item.author {
                Text(verbatim: author)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        var parts = [item.title]
        if let author = item.author { parts.append(L("by \(author)")) }
        if item.isFinished {
            parts.append(L("Finished"))
        } else if item.progressFraction > 0.001 {
            parts.append(L("\(Int(item.progressFraction * 100)) percent through"))
        }
        return parts.joined(separator: ", ")
    }
}

/// A row in a list view.
struct ItemRow: View {
    let item: LibraryItemSummary

    /// The artwork grows with the text. A fixed cover beside Dynamic Type
    /// text is what made these rows look broken at the larger sizes: a
    /// thumbnail the size of a stamp under a title three lines tall.
    @ScaledMetric(relativeTo: .body) private var coverWidth: CGFloat = 56

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            CoverImage(itemID: item.id, title: item.title, cornerRadius: Radius.small)
                .frame(width: coverWidth, height: CoverArt.height(forWidth: coverWidth))

            VStack(alignment: .leading, spacing: Spacing.hair) {
                Text(verbatim: item.title)
                    .font(Typography.itemTitle)
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(3)
                if let author = item.author {
                    Text(verbatim: author)
                        .font(Typography.itemSubtitle)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
                HStack(spacing: Spacing.s) {
                    if item.duration > 0 {
                        Text(verbatim: Format.duration(item.duration))
                    }
                    if item.hasEbook, let format = item.ebookFormat {
                        Text(verbatim: format.uppercased())
                    }
                }
                .font(Typography.duration)
                .foregroundStyle(Palette.secondaryText)
            }

            Spacer(minLength: 0)

            if item.isFinished {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Palette.accent)
            } else if item.progressFraction > 0.001 {
                Text(verbatim: "\(Int(item.progressFraction * 100))%")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

/// One horizontal shelf.
struct ShelfRow: View {
    let title: String
    let items: [LibraryItemSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(verbatim: title)
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.primaryText)
                .padding(.horizontal, Spacing.l)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Spacing.m) {
                    ForEach(items) { item in
                        NavigationLink(value: item.id) {
                            CoverCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.l)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

extension SmartShelfKind {
    var title: String {
        switch self {
        case .recentlyPlayed: L("Recently played")
        case .nextInSeries: L("Next in series")
        case .unfinishedSeries: L("Unfinished series")
        case .recentlyAdded: L("Recently added")
        case .abandoned: L("Picked up, then put down")
        case .shortListens: L("Short listens")
        }
    }
}
