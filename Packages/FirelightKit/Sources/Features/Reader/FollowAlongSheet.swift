import DesignSystem
import PlaybackKit
import ReaderKit
import SwiftUI

/// Where the listener describes their own copy of a book.
///
/// Two numbers are enough for most books: what their reader shows at the
/// start of the text and at the end. The calibration below that is for the
/// ones where the audio and the text do not begin together — a foreword, a
/// publisher's note, an excerpt of the next book bolted on the end.
struct FollowAlongSheet: View {
    let itemID: String
    let title: String

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var firstText = "1"
    @State private var lastText = ""
    @State private var unit: ReadingUnit = .location

    private var follow: FollowAlongController { environment.followAlong }
    private var player: PlaybackController { environment.player }

    /// True when the player is on this very book, which is the only time
    /// calibrating against the current position means anything.
    private var isPlayingThisBook: Bool { player.itemID == itemID }

    private var first: Int { number(firstText) ?? 1 }
    private var last: Int? { number(lastText) }

    private var draft: ReadingEdition? {
        guard let last, last >= first else { return nil }
        return ReadingEdition(
            unit: unit,
            firstPosition: first,
            lastPosition: last,
            startProgress: follow.edition?.startProgress ?? 0,
            endProgress: follow.edition?.endProgress ?? 1
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                copySection
                if follow.edition?.isUsable == true { calibrationSection }
                if follow.edition != nil { removeSection }
            }
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Save")) {
                        guard let draft else { return }
                        follow.save(itemID: itemID, edition: draft)
                        dismiss()
                    }
                    .disabled(draft == nil)
                }
            }
            .onAppear(perform: fill)
        }
        .presentationDetents([.large])
    }

    // MARK: - Your copy

    private var copySection: some View {
        Section {
            if follow.device.offersBothUnits {
                Picker(selection: $unit) {
                    Text(L("Locations")).tag(ReadingUnit.location)
                    Text(L("Pages")).tag(ReadingUnit.page)
                } label: {
                    Text(L("Counted in"))
                }
                .pickerStyle(.segmented)
            }

            LabeledContent {
                TextField(L("1"), text: $firstText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            } label: {
                Text(unit == .location ? L("First location") : L("First page"))
            }

            LabeledContent {
                TextField(L("Required"), text: $lastText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            } label: {
                Text(unit == .location ? L("Last location") : L("Last page"))
            }
        } header: {
            Text(L("Your copy"))
        } footer: {
            Text(whereToLook)
        }
    }

    // MARK: - Calibration

    private var calibrationSection: some View {
        Section {
            calibrationRow(
                label: unit == .location ? L("Text starts at") : L("Page one starts at"),
                progress: follow.edition?.startProgress ?? 0,
                end: .start
            )
            calibrationRow(
                label: unit == .location ? L("Text ends at") : L("Last page ends at"),
                progress: follow.edition?.endProgress ?? 1,
                end: .finish
            )

            if follow.edition?.isCalibrated == true {
                Button(L("Reset to the whole audiobook")) {
                    follow.clearCalibration(itemID: itemID)
                }
            }
        } header: {
            Text(L("Calibration"))
        } footer: {
            Text(isPlayingThisBook
                 ? L("Play until the text actually begins, then set the first one. Firelight holds the page still until that point instead of running ahead through the foreword.")
                 : L("Open this book in the player to calibrate it against where the audio really is."))
        }
    }

    private func calibrationRow(
        label: String,
        progress: Double,
        end: CalibrationEnd
    ) -> some View {
        LabeledContent {
            if isPlayingThisBook {
                Button(L("Set to now")) {
                    follow.calibrate(itemID: itemID, end: end, atProgress: player.bookProgress)
                }
                .font(Typography.duration)
            }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.hair) {
                Text(verbatim: label)
                Text(verbatim: timecode(forProgress: progress))
                    .font(Typography.timecode)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    private var removeSection: some View {
        Section {
            Button(role: .destructive) {
                follow.forget(itemID: itemID)
                dismiss()
            } label: {
                Text(L("Stop following along in this book"))
            }
        }
    }

    // MARK: - Helpers

    private func fill() {
        unit = follow.edition?.unit ?? follow.device.defaultUnit
        if let edition = follow.edition, edition.isUsable {
            firstText = String(edition.firstPosition)
            lastText = String(edition.lastPosition)
        }
    }

    private func number(_ text: String) -> Int? {
        let digits = text.filter(\.isNumber)
        guard let value = Int(digits), value > 0 else { return nil }
        return value
    }

    /// A calibration point is a fraction of the book; a listener thinks in
    /// minutes, so show both ends of that translation.
    private func timecode(forProgress progress: Double) -> String {
        guard isPlayingThisBook, player.duration > 0 else {
            // A percentage is a number, not prose: the system formatter gets
            // the separator and the sign right in every locale.
            return progress.formatted(.percent.precision(.fractionLength(0)))
        }
        return PlaybackController.timecode(progress * player.duration)
    }

    /// Where to find the number, which is different on every device.
    private var whereToLook: String {
        switch follow.device {
        case .kindle:
            unit == .location
                ? follow.kindleModel.whereToLook
                : L("Kindle only shows page numbers when the publisher supplied them. If yours shows none, switch to locations.")
        case .kobo, .nook, .appleBooks:
            L("Open the book on your reader and look at the last page. Change the font later and this number changes with it.")
        case .print:
            L("The first and last numbered pages of the main text.")
        }
    }
}
