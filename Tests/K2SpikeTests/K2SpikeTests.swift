import XCTest
@testable import K2Spike

class K2SpikeTests: XCTestCase {
    func testResponseOK() {
        let request = HTTPRequest(method: .GET, target:"/echo", httpVersion: (1, 1), headers: HTTPHeaders([("X-foo", "bar")]))
        let resolver = TestResponseResolver(request: request, requestBody: Data())
        let creator = ResponseCreator()
        let chunkHandler = creator.serve(req: resolver.request, res: resolver)
        var stop=false
        var finished=false
        while !stop && !finished {
            switch chunkHandler {
            case .processBody(let handler):
                    handler(.chunk(data: resolver.requestBody, finishedProcessing: {
                        finished=true
                    }), &stop)
            case .discardBody:
                finished=true
            }
        }
        XCTAssertNotNil(resolver.response)
        XCTAssertNotNil(resolver.responseBody)
        XCTAssertEqual(HTTPResponseStatus.ok.rawValue, resolver.response?.status.rawValue ?? 0)
    }

    func testEcho() {
        let testString="This is a test"
        let request = HTTPRequest(method: .GET, target:"/echo", httpVersion: (1, 1), headers: HTTPHeaders([("X-foo", "bar")]))
        let resolver = TestResponseResolver(request: request, requestBody: testString.data(using: .utf8)!)
        let creator = ResponseCreator()
        let chunkHandler = creator.serve(req: resolver.request, res: resolver)
        var stop=false
        var finished=false
        while !stop && !finished {
            switch chunkHandler {
            case .processBody(let handler):
                handler(.chunk(data: resolver.requestBody, finishedProcessing: {
                    finished=true
                }), &stop)
            case .discardBody:
                finished=true
            }
        }
        XCTAssertNotNil(resolver.response)
        XCTAssertNotNil(resolver.responseBody)
        XCTAssertEqual(HTTPResponseStatus.ok.rawValue, resolver.response?.status.rawValue ?? 0)
        XCTAssertEqual(testString, String(data: resolver.responseBody ?? Data(), encoding: .utf8) ?? "Nil")
    }

    static var allTests = [
        ("testEcho", testEcho),
        ("testResponseOK", testResponseOK),
    ]
}
