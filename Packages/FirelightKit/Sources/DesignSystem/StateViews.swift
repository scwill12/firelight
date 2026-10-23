import SwiftUI

/// The shape every non-content state takes: an icon, a short title, an
/// explanation, and at most one action.
///
/// One view for all four states so they cannot drift apart, and so the
/// accessibility behaviour is written once: the whole state reads as a single
/// element, and the action stays a separate, focusable button.
public struct StatusStateView: View {
    private let systemImage: String
    private let tint: Color
    private let title: Text
    private let message: Text?
    private let actionLabel: Text?
    private let action: (() -> Void)?
    private let isIndeterminate: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 44

    public init(
        systemImage: String,
        tint: Color = Palette.secondaryText,
        title: Text,
        message: Text? = nil,
        actionLabel: Text? = nil,
        isIndeterminate: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.isIndeterminate = isIndeterminate
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Spacing.m) {
            if isIndeterminate {
                ProgressView()
                    .controlSize(.large)
                    .tint(Palette.accent)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: Spacing.xs) {
                title
                    .font(Typography.sectionTitle)
                    .foregroundStyle(Palette.primaryText)
                    .multilineTextAlignment(.center)

                if let message {
                    message
                        .font(Typography.body)
                        .foregroundStyle(Palette.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .accessibilityElement(children: .combine)

            if let actionLabel, let action {
                Button(action: action) {
                    actionLabel
                        .font(Typography.emphasisedBody)
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.s)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .padding(.top, Spacing.xs)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}

/// Shown while the first load is in flight and there is nothing cached to show.
public struct LoadingStateView: View {
    private let title: Text?

    public init(title: Text? = nil) {
        self.title = title
    }

    public var body: some View {
        StatusStateView(
            systemImage: "hourglass",
            title: title ?? Text("Loading…", bundle: .module),
            isIndeterminate: true
        )
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Shown when the load succeeded and there is genuinely nothing to show.
public struct EmptyStateView: View {
    private let systemImage: String
    private let title: Text?
    private let message: Text?
    private let actionLabel: Text?
    private let action: (() -> Void)?

    public init(
        systemImage: String = "books.vertical",
        title: Text? = nil,
        message: Text? = nil,
        actionLabel: Text? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.action = action
    }

    public var body: some View {
        StatusStateView(
            systemImage: systemImage,
            tint: Palette.accent,
            title: title ?? Text("Nothing here yet", bundle: .module),
            message: message,
            actionLabel: actionLabel,
            action: action
        )
    }
}

/// Shown when something failed and retrying is worth offering.
public struct ErrorStateView: View {
    private let title: Text?
    private let message: Text?
    private let retry: (() -> Void)?

    public init(
        title: Text? = nil,
        message: Text? = nil,
        retry: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        StatusStateView(
            systemImage: "exclamationmark.triangle",
            tint: Palette.destructive,
            title: title ?? Text("Something went wrong", bundle: .module),
            message: message,
            actionLabel: retry == nil ? nil : Text("Try Again", bundle: .module),
            action: retry
        )
    }
}

/// Shown when the server is unreachable. Deliberately not an error: offline is
/// a normal state for this app, and the wording says so.
public struct OfflineStateView: View {
    private let message: Text?
    private let retry: (() -> Void)?

    public init(
        message: Text? = nil,
        retry: (() -> Void)? = nil
    ) {
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        StatusStateView(
            systemImage: "wifi.slash",
            tint: Palette.notice,
            title: Text("You're offline", bundle: .module),
            message: message ?? Text("Firelight will keep working with whatever you've downloaded.", bundle: .module),
            actionLabel: retry == nil ? nil : Text("Try Again", bundle: .module),
            action: retry
        )
    }
}

#Preview("Loading") { LoadingStateView() }
#Preview("Empty") {
    EmptyStateView(
        message: Text(verbatim: "Add your Audiobookshelf server to see your library here."),
        actionLabel: Text(verbatim: "Add a Server"),
        action: {}
    )
}
#Preview("Error") {
    ErrorStateView(message: Text(verbatim: "Can't reach the server."), retry: {})
}
#Preview("Offline") { OfflineStateView(retry: {}) }
