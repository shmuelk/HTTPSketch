//
//  NewServerTests.swift
//  K2Spike
//
//  Created by Carl Brown on 5/2/17.
//
//

import XCTest
import HeliumLogger

@testable import K2Spike

class NewServerTests: XCTestCase {
    
    func testDiscard() {
        HeliumLogger.use(.info)
        let receivedExpectation = self.expectation(description: "Received web response")
        let simpleHelloWebApp = SimpleResponseCreator { (request, context, body) -> (reponse: HTTPResponse, responseBody: Data) in
            return (HTTPResponse(httpVersion: request.httpVersion,
                                 status: .ok,
                                 transferEncoding: .chunked,
                                 headers: HTTPHeaders([("X-foo", "bar")])),
                    "Hello, World!".data(using: .utf8)!)
            
        }
        
        let coordinator = RequestHandlingCoordinator.init(router: Router(map: [Path(path:"/helloworld", verb:.GET): simpleHelloWebApp]))
        let server = HTTPSimpleServer()
        do {
            try server.start(port: 0, webapp: coordinator.handle)
            XCTAssertTrue(server.port > 0)
            let session = URLSession(configuration: URLSessionConfiguration.default)
            let url = URL(string: "http://localhost:\(server.port)/helloworld")!
            let dataTask = session.dataTask(with: url) { (responseBody, rawResponse, error) in
                let response = rawResponse as? HTTPURLResponse
                XCTAssertNil(error, "\(error!.localizedDescription)")
                XCTAssertNotNil(response)
                XCTAssertNotNil(responseBody)
                XCTAssertEqual(Int(HTTPResponseStatus.ok.code), response?.statusCode ?? 0)
                XCTAssertEqual("Hello, World!", String(data: responseBody ?? Data(), encoding: .utf8) ?? "Nil")
                receivedExpectation.fulfill()
            }
            dataTask.resume()
            self.waitForExpectations(timeout: 10) { (error) in
                if let error = error {
                    XCTFail("\(error)")
                }
            }
            server.stop()
        } catch {
            XCTFail("Error listening on port \(0): \(error). Use server.failed(callback:) to handle")
        }
    }

    static var allTests = [
        ("testDiscard", testDiscard),
        ]

}
