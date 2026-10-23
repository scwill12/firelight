import CoreSpotlight
import Foundation
import Persistence
import UniformTypeIdentifiers

/// Puts library items into Spotlight so they can be found from the home screen.
///
/// The spec asks for downloaded items; downloads arrive in Phase 5, so for now
/// the cached library is indexed — which is strictly more useful and is
/// narrowed, not rewritten, once there is a download state to filter on.
public struct SpotlightIndexer: Sendable {
    public static let domainIdentifier = "com.colewilliams.firelight.library"

    public init() {}

    /// Indexing is best-effort: a failure here must never surface to the user
    /// or interrupt a library refresh.
    public func index(_ items: [LibraryItemSummary], coverData: @Sendable (String) async -> Data? = { _ in nil }) async {
        guard CSSearchableIndex.isIndexingAvailable(), !items.isEmpty else { return }

        var searchableItems: [CSSearchableItem] = []
        searchableItems.reserveCapacity(items.count)

        for item in items {
            let attributes = CSSearchableItemAttributeSet(contentType: .audio)
            attributes.title = item.title
            attributes.contentDescription = [item.author, item.seriesName]
                .compactMap { $0 }
                .joined(separator: " · ")
            attributes.artist = item.author
            attributes.comment = item.summary
            attributes.keywords = [item.author, item.narrator, item.seriesBaseName]
                .compactMap { $0 } + item.genres
            if item.duration > 0 {
                attributes.duration = NSNumber(value: item.duration)
            }
            attributes.thumbnailData = await coverData(item.id)

            searchableItems.append(CSSearchableItem(
                uniqueIdentifier: Self.identifier(for: item),
                domainIdentifier: Self.domainIdentifier,
                attributeSet: attributes
            ))
        }

        try? await CSSearchableIndex.default().indexSearchableItems(searchableItems)
    }

    public func removeAll() async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        try? await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier])
    }

    /// `serverID/itemID`, so two servers holding the same book do not collide.
    public static func identifier(for item: LibraryItemSummary) -> String {
        "\(item.serverID.uuidString)/\(item.id)"
    }

    /// Reads back what `identifier(for:)` wrote.
    public static func parse(identifier: String) -> (serverID: UUID, itemID: String)? {
        let parts = identifier.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let serverID = UUID(uuidString: parts[0]) else { return nil }
        return (serverID, parts[1])
    }
}
