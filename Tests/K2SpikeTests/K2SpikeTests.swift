import XCTest
import HeliumLogger

@testable import K2Spike

class K2SpikeTests: XCTestCase {
    func testResponseOK() {
        let request = HTTPRequest(method: .GET, target:"/echo", httpVersion: (1, 1), headers: HTTPHeaders([("X-foo", "bar")]))
        let resolver = TestResponseResolver(request: request, requestBody: Data())
        let coordinator = RequestHandlingCoordinator.init(router: Router(map: [Path(path:"/echo", verb:.GET): EchoWebApp()]))
        resolver.resolveHandler(coordinator.handle)
        XCTAssertNotNil(resolver.response)
        XCTAssertNotNil(resolver.responseBody)
        XCTAssertEqual(HTTPResponseStatus.ok.code, resolver.response?.status.code ?? 0)
    }

    func testEcho() {
        let testString="This is a test"
        let request = HTTPRequest(method: .POST, target:"/echo", httpVersion: (1, 1), headers: HTTPHeaders([("X-foo", "bar")]))
        let resolver = TestResponseResolver(request: request, requestBody: testString.data(using: .utf8)!)
        let coordinator = RequestHandlingCoordinator.init(router: Router(map: [Path(path:"/echo", verb:.POST): EchoWebApp()]))
        resolver.resolveHandler(coordinator.handle)
        XCTAssertNotNil(resolver.response)
        XCTAssertNotNil(resolver.responseBody)
        XCTAssertEqual(HTTPResponseStatus.ok.code, resolver.response?.status.code ?? 0)
        XCTAssertEqual(testString, String(data: resolver.responseBody ?? Data(), encoding: .utf8) ?? "Nil")
    }
    
    func testHello() {
        let request = HTTPRequest(method: .GET, target:"/helloworld", httpVersion: (1, 1), headers: HTTPHeaders([("X-foo", "bar")]))
        let resolver = TestResponseResolver(request: request, requestBody: Data())
        let coordinator = RequestHandlingCoordinator.init(router: Router(map: [Path(path:"/helloworld", verb:.GET): HelloWorldWebApp()]))
        resolver.resolveHandler(coordinator.handle)
        XCTAssertNotNil(resolver.response)
        XCTAssertNotNil(resolver.responseBody)
        XCTAssertEqual(HTTPResponseStatus.ok.code, resolver.response?.status.code ?? 0)
        XCTAssertEqual("Hello, World!", String(data: resolver.responseBody ?? Data(), encoding: .utf8) ?? "Nil")
    }
    
    func testSimpleHello() {
        let request = HTTPRequest(method: .GET, target:"/helloworld", httpVersion: (1, 1), headers: HTTPHeaders([("X-foo", "bar")]))
        let resolver = TestResponseResolver(request: request, requestBody: Data())
        let simpleHelloWebApp = SimpleResponseCreator { (request, context, body) -> (reponse: HTTPResponse, responseBody: Data) in
            return (HTTPResponse(httpVersion: request.httpVersion,
                                 status: .ok,
                                 transferEncoding: .chunked,
                                 headers: HTTPHeaders([("X-foo", "bar")])),
                    "Hello, World!".data(using: .utf8)!)
            
        }
        let coordinator = RequestHandlingCoordinator.init(router: Router(map: [Path(path:"/helloworld", verb:.GET): simpleHelloWebApp]))
        resolver.resolveHandler(coordinator.handle)
        XCTAssertNotNil(resolver.response)
        XCTAssertNotNil(resolver.responseBody)
        XCTAssertEqual(HTTPResponseStatus.ok.code, resolver.response?.status.code ?? 0)
        XCTAssertEqual("Hello, World!", String(data: resolver.responseBody ?? Data(), encoding: .utf8) ?? "Nil")
    }

    func testHelloEndToEnd() {
        HeliumLogger.use(.info)
        let receivedExpectation = self.expectation(description: "Received web response \(#function)")
        
        let coordinator = RequestHandlingCoordinator.init(router: Router(map: [Path(path:"/helloworld", verb:.GET): HelloWorldWebApp()]))
        let server = HTTPSimpleServer()
        do {
            try server.start(port: 0, webapp: coordinator.handle)
            let session = URLSession(configuration: URLSessionConfiguration.default)
            let url = URL(string: "http://localhost:\(server.port)/helloworld")!
            print("Test \(#function) on port \(server.port)")
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
    
    func testSimpleHelloEndToEnd() {
        HeliumLogger.use(.info)
        let receivedExpectation = self.expectation(description: "Received web response \(#function)")
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
            let session = URLSession(configuration: URLSessionConfiguration.default)
            let url = URL(string: "http://localhost:\(server.port)/helloworld")!
            print("Test \(#function) on port \(server.port)")
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

    
    func testRequestEchoEndToEnd() {
        HeliumLogger.use(.info)
        let receivedExpectation = self.expectation(description: "Received web response \(#function)")
        let testString="This is a test"

        let coordinator = RequestHandlingCoordinator.init(router: Router(map: [Path(path:"/echo", verb:.POST): EchoWebApp()]))
        let server = HTTPSimpleServer()
        do {
            try server.start(port: 0, webapp: coordinator.handle)
            let session = URLSession(configuration: URLSessionConfiguration.default)
            let url = URL(string: "http://localhost:\(server.port)/echo")!
            print("Test \(#function) on port \(server.port)")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = testString.data(using: .utf8)
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            
            let dataTask = session.dataTask(with: request) { (responseBody, rawResponse, error) in
                let response = rawResponse as? HTTPURLResponse
                XCTAssertNil(error, "\(error!.localizedDescription)")
                XCTAssertNotNil(response)
                XCTAssertNotNil(responseBody)
                XCTAssertEqual(Int(HTTPResponseStatus.ok.code), response?.statusCode ?? 0)
                XCTAssertEqual(testString, String(data: responseBody ?? Data(), encoding: .utf8) ?? "Nil")
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

    func testRequestLargeEchoEndToEnd() {
        HeliumLogger.use(.info)
        let receivedExpectation = self.expectation(description: "Received web response \(#function)")
        //Get a file we know exists
        //let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let executableUrl = URL(fileURLWithPath: CommandLine.arguments[0])
        
        let testExecutableData = try! Data(contentsOf: executableUrl)
        
        var testDataLong = testExecutableData + testExecutableData + testExecutableData + testExecutableData
        let length = testDataLong.count
        let keep = 16385
        let remove = length - keep
        if (remove > 0) {
            testDataLong.removeLast(remove)
        }
        
        let testData = Data(testDataLong)
        
        let coordinator = RequestHandlingCoordinator.init(router: Router(map: [Path(path:"/echo", verb:.POST): EchoWebApp()]))
        
        let server = HTTPSimpleServer()
        do {
            try server.start(port: 0, webapp: coordinator.handle)
            let session = URLSession(configuration: URLSessionConfiguration.default)
            let url = URL(string: "http://localhost:\(server.port)/echo")!
            print("Test \(#function) on port \(server.port)")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = testData
            let dataTask = session.dataTask(with: request) { (responseBody, rawResponse, error) in
                let response = rawResponse as? HTTPURLResponse
                XCTAssertNil(error, "\(error!.localizedDescription)")
                XCTAssertNotNil(response)
                XCTAssertNotNil(responseBody)
                XCTAssertEqual(Int(HTTPResponseStatus.ok.code), response?.statusCode ?? 0)
                XCTAssertEqual(testData, responseBody ?? Data())
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

    func testWithCookieHelloEndToEnd() {
        HeliumLogger.use(.info)
        let receivedExpectation = self.expectation(description: "Received web response \(#function)")
        
        let coordinator = RequestHandlingCoordinator.init(router: Router(map: [Path(path:"/helloworld", verb:.GET): HelloWorldWebApp()]))
        let badCookieHandler = BadCookieWritingMiddleware(cookieName: "OurCookie")
        
        coordinator.addPreProcessor(badCookieHandler.preProcess)
        coordinator.addPostProcessor(badCookieHandler.postProcess)
        
        let server = HTTPSimpleServer()
        do {
            try server.start(port: 0, webapp: coordinator.handle)
            let session = URLSession(configuration: URLSessionConfiguration.default)
            let url = URL(string: "http://localhost:\(server.port)/helloworld")!
            print("Test \(#function) on port \(server.port)")
            let dataTask = session.dataTask(with: url) { (responseBody, rawResponse, error) in
                let response = rawResponse as? HTTPURLResponse
                XCTAssertNil(error, "\(error!.localizedDescription)")
                XCTAssertNotNil(response)
                XCTAssertNotNil(responseBody)
                XCTAssertEqual(Int(HTTPResponseStatus.ok.code), response?.statusCode ?? 0)
                XCTAssertEqual("Hello, World!", String(data: responseBody ?? Data(), encoding: .utf8) ?? "Nil")
                #if os(Linux)
                    //print("\(response!.allHeaderFields.debugDescription)")
                    XCTAssertNotNil(response?.allHeaderFields["Set-Cookie"])
                    let ourCookie = response?.allHeaderFields["Set-Cookie"] as? String
                    let ourCookieString = ourCookie ?? ""
                    let index = ourCookieString.index(ourCookieString.startIndex, offsetBy: 10)
                    XCTAssertTrue(ourCookieString.substring(to: index) == "OurCookie=")
                #else
                    let fields = response?.allHeaderFields as? [String : String] ?? [:]
                    let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
                    XCTAssertNotNil(cookies)
                    print("\(cookies.debugDescription)")
                    var ourCookie: HTTPCookie? = nil
                    var missingCookie: HTTPCookie? = nil //We should not find this
                    for cookie in cookies {
                        if cookie.name == "OurCookie" {
                            ourCookie = cookie
                        }
                        if cookie.name == "MissingCookie" {
                            missingCookie = cookie
                        }
                    }
                    
                    XCTAssertNotNil(ourCookie)
                    XCTAssertNil(missingCookie)
                #endif
                receivedExpectation.fulfill()
            }
            dataTask.resume()
            self.waitForExpectations(timeout: 30) { (error) in
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
        ("testEcho", testEcho),
        ("testHello", testHello),
        ("testSimpleHello", testSimpleHello),
        ("testResponseOK", testResponseOK),
        ("testHelloEndToEnd", testHelloEndToEnd),
        ("testSimpleHelloEndToEnd", testSimpleHelloEndToEnd),
        ("testRequestEchoEndToEnd", testRequestEchoEndToEnd),
        ("testWithCookieHelloEndToEnd", testWithCookieHelloEndToEnd),
        ]
}
