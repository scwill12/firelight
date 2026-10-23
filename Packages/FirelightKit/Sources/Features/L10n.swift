import Foundation

/// Localises a string from this module's String Catalog.
///
/// SwiftUI's `Text("…")` and `TextField("…", text:)` look a `LocalizedStringKey`
/// up in `Bundle.main`, which for a package module is the *app's* bundle — so
/// a bare literal here would silently never be translated. Passing an
/// already-localised `String` instead is unambiguous, reads cleanly at the call
/// site, and keeps every string in `Localizable.xcstrings`.
///
///     Text(L("Sign In"))
///     TextField(L("Username"), text: $username)
///
/// Interpolation works as usual and becomes a `%@` placeholder in the catalog.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
