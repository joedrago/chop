import Foundation
import Testing

@testable import Chop

@Suite("smoke")
struct SmokeTests {
    @Test("Bundle identifier is correct")
    func bundleIdentifier() {
        #expect(Bundle(for: ChopDocument.self).bundleIdentifier != nil)
    }
}
