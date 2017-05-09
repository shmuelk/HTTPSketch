import XCTest
@testable import K2SpikeTests

XCTMain([
    testCase(ConnectionListenerTests.allTests),
    testCase(K2SpikeTests.allTests),
    testCase(RouterTests.allTests),
])
