import DesignSystem
import StoreKit
import SwiftUI

/// The tip jar.
///
/// It says plainly that tipping unlocks nothing, because a tip jar that reads
/// like a paywall is a paywall.
struct TipJarView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isPurchasing: String?

    private var tipJar: TipJar { environment.tipJar }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(L("Firelight is free, and stays free."))
                        .font(Typography.sectionTitle)
                        .foregroundStyle(Palette.primaryText)
                    Text(L("Every feature is included for everyone. There is nothing to unlock, and a tip doesn't change anything in the app — it just says thank you."))
                        .font(Typography.body)
                        .foregroundStyle(Palette.secondaryText)
                }
                .padding(.vertical, Spacing.xs)
                .accessibilityElement(children: .combine)
            }

            Section {
                if tipJar.isLoading {
                    HStack(spacing: Spacing.s) {
                        ProgressView()
                        Text(L("Loading…")).foregroundStyle(Palette.secondaryText)
                    }
                } else if tipJar.products.isEmpty {
                    Text(L("The App Store isn't reachable right now."))
                        .foregroundStyle(Palette.secondaryText)
                } else {
                    ForEach(tipJar.products, id: \.id) { product in
                        Button {
                            Task {
                                isPurchasing = product.id
                                await tipJar.purchase(product)
                                isPurchasing = nil
                            }
                        } label: {
                            LabeledContent {
                                if isPurchasing == product.id {
                                    ProgressView()
                                } else {
                                    Text(verbatim: product.displayPrice)
                                        .foregroundStyle(Palette.accent)
                                }
                            } label: {
                                Label {
                                    Text(verbatim: product.displayName)
                                        .foregroundStyle(Palette.primaryText)
                                } icon: {
                                    Image(systemName: TipProduct(rawValue: product.id)?.symbolName ?? "heart")
                                        .foregroundStyle(Palette.accent)
                                }
                            }
                        }
                        .disabled(isPurchasing != nil)
                    }
                }
            } header: {
                Text(L("Tip jar"))
            } footer: {
                if let failure = tipJar.failure {
                    Text(verbatim: failure).foregroundStyle(Palette.destructive)
                }
            }

            if tipJar.hasTipped {
                Section {
                    Label(L("Tip received — thank you"), systemImage: "heart.fill")
                        .foregroundStyle(Palette.accent)
                }
            }
        }
        .navigationTitle(Text(L("Support Firelight")))
        .navigationBarTitleDisplayMode(.inline)
        .task { await tipJar.load() }
        .sheet(isPresented: Binding(
            get: { tipJar.lastThankedProduct != nil },
            set: { if !$0 { tipJar.clearThanks() } }
        )) {
            ThankYouView()
        }
    }
}

/// What a tip buys: this screen, and nothing else.
struct ThankYouView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isGlowing = false

    var body: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: "flame.fill")
                .font(.system(size: 72))
                .foregroundStyle(Palette.accent)
                .scaleEffect(isGlowing && !reduceMotion ? 1.08 : 1.0)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                    value: isGlowing
                )

            Text(L("Thank you"))
                .font(Typography.screenTitle)
                .foregroundStyle(Palette.primaryText)

            Text(L("Firelight is built in spare hours and given away. Your tip pays for none of it and means a great deal."))
                .font(Typography.body)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)

            Button(L("You're welcome")) { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .onAppear { isGlowing = true }
        .presentationDetents([.medium])
        .accessibilityElement(children: .combine)
    }
}

/// Picking an alternate icon.
struct AppIconPicker: View {
    @State private var current = UIApplication.shared.alternateIconName

    private struct Option: Identifiable {
        let id: String
        let name: String?
        let displayName: String
        let assetName: String
    }

    private let options: [Option] = [
        Option(id: "default", name: nil, displayName: "Ember", assetName: "AppIcon"),
        Option(id: "Hearth", name: "AppIcon-Hearth", displayName: "Hearth", assetName: "AppIcon-Hearth"),
        Option(id: "Moonlight", name: "AppIcon-Moonlight", displayName: "Moonlight", assetName: "AppIcon-Moonlight"),
    ]

    var body: some View {
        List {
            Section {
                ForEach(options) { option in
                    Button {
                        set(option.name)
                    } label: {
                        LabeledContent {
                            if current == option.name {
                                Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                            }
                        } label: {
                            Label {
                                Text(verbatim: option.displayName)
                                    .foregroundStyle(Palette.primaryText)
                            } icon: {
                                Image(uiImage: UIImage(named: option.assetName) ?? UIImage())
                                    .resizable()
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                    .accessibilityAddTraits(current == option.name ? [.isSelected] : [])
                }
            } footer: {
                Text(L("Every icon is free, like everything else here."))
            }
        }
        .navigationTitle(Text(L("App icon")))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func set(_ name: String?) {
        UIApplication.shared.setAlternateIconName(name) { error in
            guard error == nil else { return }
            Task { @MainActor in current = name }
        }
        Haptics.selection()
    }
}
