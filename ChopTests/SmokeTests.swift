import Foundation
import Testing

@testable import Chop

@Suite("Phase 0 smoke")
struct SmokeTests {
    @Test("Bundle identifier is correct")
    func bundleIdentifier() {
        #expect(Bundle(for: ChopDocument.self).bundleIdentifier != nil)
    }
}
