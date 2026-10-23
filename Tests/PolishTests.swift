import Foundation
import Testing
@testable import DesignSystem
@testable import Features

@Suite("Tip jar")
struct TipJarTests {
    @Test("Four tips, in the order the spec lists them")
    func products() {
        #expect(TipProduct.allCases.count == 4)
        #expect(TipProduct.ordered.map(\.displayName) == ["Coffee", "Snack", "Lunch", "Dinner"])
        #expect(TipProduct.ordered.map(\.nominalPrice) == [0.99, 2.99, 4.99, 9.99])
    }

    @Test("Product identifiers match what App Store Connect will hold")
    func identifiers() {
        for product in TipProduct.allCases {
            #expect(product.rawValue.hasPrefix("com.colewilliams.firelight.tip."))
        }
        #expect(TipProduct.coffee.rawValue == "com.colewilliams.firelight.tip.coffee")
    }

    @Test("Every tip has an icon, so none looks unfinished")
    func symbols() {
        for product in TipProduct.allCases {
            #expect(!product.symbolName.isEmpty)
        }
    }

    @Test("The StoreKit test configuration matches the code")
    func storeKitConfigurationMatches() throws {
        // A mismatch here means the tip jar is empty in the simulator and
        // nobody finds out until they try to test it.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "App/Firelight.storekit")
        let data = try Data(contentsOf: url)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try #require(json["products"] as? [[String: Any]])

        let configuredIDs = Set(products.compactMap { $0["productID"] as? String })
        #expect(configuredIDs == Set(TipProduct.allCases.map(\.rawValue)))

        for product in products {
            #expect(product["type"] as? String == "Consumable", "tips must be consumable")
        }
    }
}

@Suite("Diagnostics report")
struct DiagnosticsTests {
    private var input: DiagnosticsReport.Input {
        DiagnosticsReport.Input(
            appVersion: "0.1.0",
            build: "1",
            systemVersion: "26.0",
            deviceModel: "iPhone",
            serverCount: 2,
            serverVersions: ["2.26.0"],
            activeAddressKind: "local",
            isOffline: false,
            libraryItemCount: 412,
            queuedProgressCount: 3,
            downloadCount: 5,
            downloadBytes: 1_234_567,
            appGroupAvailable: true,
            keychainAvailable: true,
            databaseAvailable: true
        )
    }

    @Test("Says what is wrong without saying who you are")
    func containsUsefulFacts() {
        let report = DiagnosticsReport.text(from: input)
        #expect(report.contains("0.1.0"))
        #expect(report.contains("2.26.0"))
        #expect(report.contains("412"))
        #expect(report.contains("Progress queued  3"))
    }

    @Test("Carries no address, username or token")
    func carriesNoSecrets() {
        let report = DiagnosticsReport.text(from: input)
        // The most likely destination for this file is a public issue tracker.
        #expect(!DiagnosticsReport.containsSensitiveData(
            report,
            knownSecrets: ["books.example.com", "cole", "eyJhbGciOiJIUzI1NiJ9"]
        ))
        #expect(!report.contains("http"))
    }

    @Test("The leak check actually catches a leak")
    func leakCheckWorks() {
        #expect(DiagnosticsReport.containsSensitiveData(
            "Server: https://books.example.com",
            knownSecrets: ["books.example.com"]
        ))
        #expect(DiagnosticsReport.containsSensitiveData(
            "User: Cole",
            knownSecrets: ["cole"]
        ))
    }

    @Test("A broken foundation is reported plainly")
    func reportsFailures() {
        var broken = input
        broken = DiagnosticsReport.Input(
            appVersion: broken.appVersion, build: broken.build,
            systemVersion: broken.systemVersion, deviceModel: broken.deviceModel,
            serverCount: 0, serverVersions: [], activeAddressKind: nil, isOffline: true,
            libraryItemCount: 0, queuedProgressCount: 0, downloadCount: 0, downloadBytes: 0,
            appGroupAvailable: false, keychainAvailable: false, databaseAvailable: false
        )
        let report = DiagnosticsReport.text(from: broken)
        #expect(report.contains("not working"))
        #expect(report.contains("Active address   none"))
    }
}

@Suite("Privacy manifest")
struct PrivacyManifestTests {
    @Test("Declares no tracking and no collected data")
    func declaresNothingCollected() throws {
        // The spec's promise is an App Store label reading "Data Not
        // Collected". That is this file.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "App/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: url)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
        #expect((plist["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)

        let apis = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        #expect(!apis.isEmpty, "required-reason APIs must be declared or the build is rejected")
        for api in apis {
            let reasons = try #require(api["NSPrivacyAccessedAPITypeReasons"] as? [String])
            #expect(!reasons.isEmpty)
        }
    }
}
