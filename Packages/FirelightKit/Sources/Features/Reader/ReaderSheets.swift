import DesignSystem
import ReaderKit
import SwiftUI
import UIKit

/// Typography and theme.
struct ReaderSettingsSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    private var reader: ReaderController { environment.reader }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L("Typeface"), selection: Binding(
                        get: { reader.settings.font },
                        set: { reader.settings.font = $0 }
                    )) {
                        ForEach(ReaderFont.allCases, id: \.self) { font in
                            Text(verbatim: font.displayName).tag(font)
                        }
                    }

                    Stepper(value: Binding(
                        get: { reader.settings.fontScale },
                        set: { reader.settings.fontScale = $0 }
                    ), in: 0.5...3.0, step: 0.1) {
                        Text(L("Text size \(Int(reader.settings.fontScale * 100))%"))
                    }

                    Stepper(value: Binding(
                        get: { reader.settings.lineHeight },
                        set: { reader.settings.lineHeight = $0 }
                    ), in: 1.0...3.0, step: 0.1) {
                        Text(L("Line spacing \(String(format: "%.1f", reader.settings.lineHeight))"))
                    }

                    Stepper(value: Binding(
                        get: { reader.settings.margin },
                        set: { reader.settings.margin = $0 }
                    ), in: 0...80, step: 4) {
                        Text(L("Margins \(Int(reader.settings.margin))"))
                    }
                } header: {
                    Text(L("Type and spacing"))
                } footer: {
                    Text(L("Atkinson Hyperlegible and OpenDyslexic are designed for easier reading."))
                }

                Section {
                    Toggle(L("Justify text"), isOn: Binding(
                        get: { reader.settings.isJustified },
                        set: { reader.settings.isJustified = $0 }
                    ))
                    Toggle(L("Hyphenate"), isOn: Binding(
                        get: { reader.settings.isHyphenated },
                        set: { reader.settings.isHyphenated = $0 }
                    ))
                    Toggle(L("Two pages in landscape"), isOn: Binding(
                        get: { reader.settings.allowsTwoColumns },
                        set: { reader.settings.allowsTwoColumns = $0 }
                    ))
                }

                Section {
                    Picker(L("Theme"), selection: Binding(
                        get: { reader.settings.theme },
                        set: { reader.settings.theme = $0 }
                    )) {
                        ForEach(ReaderTheme.allCases, id: \.self) { theme in
                            Text(verbatim: theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section {
                    Picker(L("Page turns"), selection: Binding(
                        get: { reader.settings.pageTurn },
                        set: { reader.settings.pageTurn = $0 }
                    )) {
                        ForEach(PageTurnStyle.allCases, id: \.self) { style in
                            Text(verbatim: style.displayName).tag(style)
                        }
                    }
                }
            }
            .navigationTitle(Text(L("Reading")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(L("Done")) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Saving a passage.
struct AddHighlightSheet: View {
    let text: String
    let onSave: (HighlightColor, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var color: HighlightColor = .yellow
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: text)
                        .font(Typography.body)
                        .lineLimit(8)
                } header: {
                    Text(L("Passage"))
                }

                Section {
                    HStack(spacing: Spacing.m) {
                        ForEach(HighlightColor.allCases, id: \.self) { candidate in
                            Button {
                                color = candidate
                                Haptics.selection()
                            } label: {
                                Circle()
                                    .fill(Color(
                                        .sRGB,
                                        red: candidate.components.r,
                                        green: candidate.components.g,
                                        blue: candidate.components.b
                                    ))
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if candidate == color {
                                            Circle().strokeBorder(Palette.primaryText, lineWidth: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(candidate.displayName)
                            .accessibilityAddTraits(candidate == color ? [.isSelected] : [])
                        }
                    }
                } header: {
                    Text(L("Colour"))
                }

                Section {
                    TextField(L("Note (optional)"), text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section {
                    Button {
                        lookUp(text)
                    } label: {
                        Label(L("Look up"), systemImage: "character.book.closed")
                    }
                }
            }
            .navigationTitle(Text(L("Highlight")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Save")) {
                        onSave(color, note.isEmpty ? nil : note)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// The system dictionary, which is what people expect from a long press.
    private func lookUp(_ term: String) {
        let word = term.split(separator: " ").first.map(String.init) ?? term
        let controller = UIReferenceLibraryViewController(term: word)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.keyWindow?.rootViewController
        else { return }
        root.presentedViewController?.present(controller, animated: true)
            ?? root.present(controller, animated: true)
    }
}

/// The highlights in this book, and the export.
struct HighlightsSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?

    private var reader: ReaderController { environment.reader }

    var body: some View {
        NavigationStack {
            Group {
                if reader.highlights.isEmpty {
                    EmptyStateView(
                        systemImage: "highlighter",
                        title: Text(L("No highlights yet")),
                        message: Text(L("Select a passage while reading to save it."))
                    )
                } else {
                    List {
                        ForEach(reader.highlights) { highlight in
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                HStack(spacing: Spacing.s) {
                                    Circle()
                                        .fill(Color(
                                            .sRGB,
                                            red: highlight.color.components.r,
                                            green: highlight.color.components.g,
                                            blue: highlight.color.components.b
                                        ))
                                        .frame(width: 10, height: 10)
                                    Text(verbatim: "\(Int(highlight.progression * 100))%")
                                        .font(Typography.caption)
                                        .foregroundStyle(Palette.secondaryText)
                                }
                                Text(verbatim: highlight.text)
                                    .font(Typography.body)
                                    .lineLimit(5)
                                if let note = highlight.note {
                                    Text(verbatim: note)
                                        .font(Typography.caption)
                                        .foregroundStyle(Palette.secondaryText)
                                }
                            }
                            .padding(.vertical, Spacing.hair)
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await reader.removeHighlight(id: highlight.id) }
                                } label: {
                                    Label(L("Delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(Text(L("Highlights")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        exportURL = reader.exportHighlights()
                    } label: {
                        Label(L("Export"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(reader.highlights.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) { Button(L("Done")) { dismiss() } }
            }
            .sheet(item: Binding(
                get: { exportURL.map { ExportFile(url: $0) } },
                set: { if $0 == nil { exportURL = nil } }
            )) { file in
                ShareSheet(items: [file.url])
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// The system share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
