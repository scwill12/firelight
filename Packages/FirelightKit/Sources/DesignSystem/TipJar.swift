import Foundation
import StoreKit

/// The tip jar.
///
/// Four consumables that unlock nothing — the spec is explicit, and so is the
/// UI. A tip jar that quietly gates a feature is a paywall with better
/// manners, and this app does not have one.
public enum TipProduct: String, Sendable, Hashable, CaseIterable, Identifiable {
    case coffee = "com.colewilliams.firelight.tip.coffee"
    case snack = "com.colewilliams.firelight.tip.snack"
    case lunch = "com.colewilliams.firelight.tip.lunch"
    case dinner = "com.colewilliams.firelight.tip.dinner"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .coffee: "Coffee"
        case .snack: "Snack"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        }
    }

    public var symbolName: String {
        switch self {
        case .coffee: "cup.and.saucer"
        case .snack: "carrot"
        case .lunch: "takeoutbag.and.cup.and.straw"
        case .dinner: "fork.knife"
        }
    }

    /// Only for the StoreKit test configuration and for showing something
    /// sensible before the store answers. The real price always comes from
    /// StoreKit, which localises and handles tax.
    public var nominalPrice: Decimal {
        switch self {
        case .coffee: 0.99
        case .snack: 2.99
        case .lunch: 4.99
        case .dinner: 9.99
        }
    }

    /// Smallest first, which is also the order they are offered in.
    public static var ordered: [TipProduct] {
        allCases.sorted { $0.nominalPrice < $1.nominalPrice }
    }
}

/// Loads the products and handles a purchase.
@MainActor
@Observable
public final class TipJar {
    public private(set) var products: [Product] = []
    public private(set) var isLoading = false
    public private(set) var hasTipped = false
    /// Set after a successful purchase, so the thank-you can be shown.
    public private(set) var lastThankedProduct: TipProduct?
    public private(set) var failure: String?

    private static let hasTippedKey = "firelight.hasTipped"

    public init() {
        hasTipped = UserDefaults.standard.bool(forKey: Self.hasTippedKey)
    }

    public func load() async {
        guard products.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: TipProduct.allCases.map(\.rawValue))
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            // A store that will not answer is not worth an error banner on a
            // screen nobody has to use.
            failure = nil
        }
    }

    public func purchase(_ product: Product) async {
        failure = nil
        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    // Consumables must be finished or StoreKit replays them.
                    await transaction.finish()
                    hasTipped = true
                    UserDefaults.standard.set(true, forKey: Self.hasTippedKey)
                    lastThankedProduct = TipProduct(rawValue: product.id)
                case .unverified:
                    failure = "That purchase couldn't be verified."
                }
            case .userCancelled:
                break
            case .pending:
                failure = "That purchase is waiting for approval."
            @unknown default:
                break
            }
        } catch {
            failure = "The purchase didn't go through."
        }
    }

    public func clearThanks() {
        lastThankedProduct = nil
    }
}
