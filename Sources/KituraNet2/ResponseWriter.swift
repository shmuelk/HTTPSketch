import Foundation
import Dispatch

class ResponseWriter: HTTPResponseWriter {
    private static let bufferSize = 8192

    let httpParser: HTTPParser
    let request: HTTPRequest
    var requestBodyChunk: Data

    var response: HTTPResponse?
    var responseBody: Data?

    init(httpParser: HTTPParser, request: HTTPRequest, requestBody: Data) {
        self.httpParser = httpParser
        self.request = request
        self.requestBodyChunk = Data(capacity: ResponseWriter.bufferSize)
    }

    func resolveHandler(_ handler:WebApp) {
        let chunkHandler = handler(request, self)
        var stop=false
        while !stop {
            switch chunkHandler {
            case .processBody(let handler):
                let count = httpParser.bodyChunk.fill(data: &requestBodyChunk)
                let dispatchData = requestBodyChunk.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> DispatchData in
                    DispatchData(bytes: UnsafeBufferPointer<UInt8>(start: ptr, count: count))
                }
                handler(.chunk(data: dispatchData, finishedProcessing: { }), &stop)
            case .discardBody:
                stop=true
            }
        }
    }

    func writeContinue(headers: HTTPHeaders?) /* to send an HTTP `100 Continue` */ {
        fatalError("Not implemented")
    }

    func writeResponse(_ response: HTTPResponse) {
        self.response=response
    }

    func writeTrailer(key: String, value: String) {
        fatalError("Not implemented")
    }

    func writeBody(data: DispatchData, completion: @escaping (Result<POSIXError, ()>) -> Void) {
        self.responseBody = Data(data)
        completion(Result(completion: ()))
    }
    func writeBody(data: DispatchData) /* convenience */ {
        writeBody(data: data) { _ in

        }
    }

    func writeBody(data: Data, completion: @escaping (Result<POSIXError, ()>) -> Void) {
        self.responseBody = data
        completion(Result(completion: ()))
    }

    func writeBody(data: Data) /* convenience */ {
        writeBody(data: data) { _ in

        }
    }

    func done(completion: @escaping (Result<POSIXError, ()>) -> Void) {
        completion(Result(completion: ()))
    }
    func done() /* convenience */ {
        done() { _ in
        }
    }

    func abort() {
        fatalError("abort called, not sure what to do with it")
    }

}
