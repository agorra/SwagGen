#if !canImport(ObjectiveC)
import XCTest

extension ParsingTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__ParsingTests = [
        ("testParsing", testParsing),
    ]
}

extension SpecTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__SpecTests = [
        ("testSpecs", testSpecs),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(ParsingTests.__allTests__ParsingTests),
        testCase(SpecTests.__allTests__SpecTests),
    ]
}
#endif
