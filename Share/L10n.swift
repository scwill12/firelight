import Foundation

/// Localises a string from the share extension's own String Catalog.
///
/// The extension has its own bundle and its own `Localizable.xcstrings`; the
/// `L` in `Features` reads that module's catalog and is not visible here.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key)
}
