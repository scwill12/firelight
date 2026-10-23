import Foundation

/// The rules for sending a book to a Kindle.
///
/// Amazon's Send to Kindle is email, with real limits: it accepts a short list
/// of formats, caps the attachment, and silently discards anything from an
/// address the account has not approved. Every one of those produces a book
/// that simply never arrives, so each is checked before the compose sheet
/// opens rather than after.
public enum KindleDelivery {
    /// Amazon's documented attachment ceiling.
    public static let maximumAttachmentBytes: Int64 = 50 * 1024 * 1024

    public enum Refusal: Sendable, Hashable {
        case noAddressSaved
        case addressNotKindle(String)
        case formatNotAccepted(EbookFormat)
        case tooLarge(bytes: Int64)
        case mailUnavailable

        /// What the user is told, and what they can do about it.
        public var message: String {
            switch self {
            case .noAddressSaved:
                "Add your Kindle email address in Settings first."
            case .addressNotKindle:
                "That doesn't look like a Kindle address. It should end in @kindle.com."
            case .formatNotAccepted(let format):
                "Kindle doesn't accept \(format.displayName) files. Use the share sheet instead."
            case .tooLarge:
                "This file is over Amazon's 50 MB email limit. Use the share sheet instead."
            case .mailUnavailable:
                "This device isn't set up to send email."
            }
        }
    }

    /// Whether a book can be sent, and why not when it can't.
    public static func check(
        format: EbookFormat?,
        fileSizeBytes: Int64,
        kindleAddress: String?,
        canSendMail: Bool
    ) -> Refusal? {
        guard canSendMail else { return .mailUnavailable }

        guard let address = kindleAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty
        else { return .noAddressSaved }
        guard isValidKindleAddress(address) else { return .addressNotKindle(address) }

        guard let format else { return .formatNotAccepted(.epub) }
        guard format.isAcceptedByKindle else { return .formatNotAccepted(format) }

        guard fileSizeBytes <= maximumAttachmentBytes else { return .tooLarge(bytes: fileSizeBytes) }
        return nil
    }

    /// `name@kindle.com`, case-insensitively. Amazon also issues
    /// `@free.kindle.com`, which delivers only over Wi-Fi but is still valid.
    public static func isValidKindleAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let atIndex = trimmed.firstIndex(of: "@") else { return false }
        let local = trimmed[trimmed.startIndex..<atIndex]
        let domain = String(trimmed[trimmed.index(after: atIndex)...])
        guard !local.isEmpty, !local.contains(" ") else { return false }
        return domain == "kindle.com" || domain == "free.kindle.com"
    }

    /// The subject line. Amazon ignores it, but it is what the user sees in
    /// their sent mail, so it may as well say what was sent.
    public static func subject(forBookTitle title: String) -> String {
        title.isEmpty ? "Sent from Firelight" : title
    }

    /// Shown once, because an unapproved sender fails silently at Amazon's end
    /// and looks exactly like the app being broken.
    public static let approvedSenderNotice = """
        Amazon only accepts books from email addresses you have approved. \
        Add the address you send from to your Approved Personal Document \
        E-mail List in your Amazon account, or the book will never arrive.
        """
}
