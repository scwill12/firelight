import Foundation
import Testing
@testable import ReaderKit

@Suite("Send to Kindle")
struct KindleDeliveryTests {
    private let address = "cole@kindle.com"

    @Test("A valid EPUB under the limit can be sent")
    func allowed() {
        let refusal = KindleDelivery.check(
            format: .epub, fileSizeBytes: 5_000_000,
            kindleAddress: address, canSendMail: true
        )
        #expect(refusal == nil)
    }

    @Test("Kindle takes EPUB and PDF, and nothing else Firelight holds")
    func acceptedFormats() {
        #expect(EbookFormat.epub.isAcceptedByKindle)
        #expect(EbookFormat.pdf.isAcceptedByKindle)
        for format in [EbookFormat.cbz, .cbr, .mobi, .azw3] {
            #expect(!format.isAcceptedByKindle, "\(format) is not accepted by Send to Kindle")
        }
    }

    @Test("A comic is refused with an explanation, not a silent failure")
    func refusesComics() {
        let refusal = KindleDelivery.check(
            format: .cbz, fileSizeBytes: 1_000,
            kindleAddress: address, canSendMail: true
        )
        #expect(refusal == .formatNotAccepted(.cbz))
        #expect(refusal?.message.contains("share sheet") == true)
    }

    @Test("Amazon's 50 MB ceiling is enforced before the compose sheet opens")
    func sizeLimit() {
        let justUnder = KindleDelivery.check(
            format: .epub, fileSizeBytes: KindleDelivery.maximumAttachmentBytes,
            kindleAddress: address, canSendMail: true
        )
        #expect(justUnder == nil)

        let justOver = KindleDelivery.check(
            format: .epub, fileSizeBytes: KindleDelivery.maximumAttachmentBytes + 1,
            kindleAddress: address, canSendMail: true
        )
        guard case .tooLarge = justOver else {
            Issue.record("Expected a size refusal, got \(String(describing: justOver))")
            return
        }
    }

    @Test("No saved address is caught before anything else")
    func missingAddress() {
        #expect(KindleDelivery.check(
            format: .epub, fileSizeBytes: 1, kindleAddress: nil, canSendMail: true
        ) == .noAddressSaved)
        #expect(KindleDelivery.check(
            format: .epub, fileSizeBytes: 1, kindleAddress: "   ", canSendMail: true
        ) == .noAddressSaved)
    }

    @Test("Only real Kindle addresses are accepted")
    func addressValidation() {
        #expect(KindleDelivery.isValidKindleAddress("cole@kindle.com"))
        #expect(KindleDelivery.isValidKindleAddress("Cole@Kindle.COM"))
        // Amazon's Wi-Fi-only variant is valid too.
        #expect(KindleDelivery.isValidKindleAddress("cole@free.kindle.com"))

        #expect(!KindleDelivery.isValidKindleAddress("cole@gmail.com"))
        #expect(!KindleDelivery.isValidKindleAddress("@kindle.com"))
        #expect(!KindleDelivery.isValidKindleAddress("cole"))
        #expect(!KindleDelivery.isValidKindleAddress("co le@kindle.com"))
        #expect(!KindleDelivery.isValidKindleAddress("cole@kindle.com.evil.example"))
    }

    @Test("A device with no mail account is told so")
    func mailUnavailable() {
        #expect(KindleDelivery.check(
            format: .epub, fileSizeBytes: 1, kindleAddress: address, canSendMail: false
        ) == .mailUnavailable)
    }

    @Test("Every refusal explains itself")
    func messagesAreUseful() {
        let refusals: [KindleDelivery.Refusal] = [
            .noAddressSaved, .addressNotKindle("x"), .formatNotAccepted(.mobi),
            .tooLarge(bytes: 99), .mailUnavailable,
        ]
        for refusal in refusals {
            #expect(!refusal.message.isEmpty)
        }
    }

    @Test("The subject is the book, or something rather than nothing")
    func subject() {
        #expect(KindleDelivery.subject(forBookTitle: "The Hobbit") == "The Hobbit")
        #expect(!KindleDelivery.subject(forBookTitle: "").isEmpty)
    }

    @Test("The approved-sender warning names the thing that silently fails")
    func senderNotice() {
        #expect(KindleDelivery.approvedSenderNotice.contains("Approved"))
    }
}
