import Foundation
import Dispatch

class ResponseWriter: HTTPResponseWriter {
    private static let bufferSize = 8192

    private let httpParser: HTTPParser
    private let request: HTTPRequest
    private let socketHandler: IncomingSocketHandler
    private var requestBodyBuffer: Data
    private var headersWritten = false

    init(httpParser: HTTPParser, request: HTTPRequest, socketHandler: IncomingSocketHandler) {
        self.httpParser = httpParser
        self.request = request
        self.socketHandler = socketHandler
        self.requestBodyBuffer = Data(capacity: ResponseWriter.bufferSize)
    }

    func resolveHandler(_ handler:WebApp) {
        let chunkHandler = handler(request, self)
        var stop=false
        while !stop {
            switch chunkHandler {
            case .processBody(let handler):
                let count = httpParser.bodyChunk.fill(data: &requestBodyBuffer)
                let data = requestBodyBuffer.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> DispatchData in
                    DispatchData(bytes: UnsafeBufferPointer<UInt8>(start: ptr, count: count))
                }
                handler(.chunk(data: data, finishedProcessing: { }), &stop)
            case .discardBody:
                stop=true
            }
        }
    }

    func writeContinue(headers: HTTPHeaders?) /* to send an HTTP `100 Continue` */ {
        fatalError("Not implemented")
    }

    func writeResponse(_ response: HTTPResponse) {
        guard !headersWritten else {
            return
        }

        var headerData = "HTTP/1.1 \(response.status.rawValue) \(response.status)\r\n"

        for (_, entry) in headers.headers {
            for value in entry.value {
                headerData.append(entry.key)
                headerData.append(": ")
                headerData.append(value)
                headerData.append("\r\n")
            }
        }

        let upgrade = processor?.isUpgrade ?? false
        let keepAlive = processor?.isKeepAlive ?? false
        if !upgrade {
            if  keepAlive {
                headerData.append("Connection: Keep-Alive\r\n")
                headerData.append("Keep-Alive: timeout=\(Int(IncomingHTTPSocketProcessor.keepAliveTimeout)), max=\((processor?.numberOfRequests ?? 1) - 1)\r\n")
            }
            else {
                headerData.append("Connection: Close\r\n")
            }
        }
        headerData.append("\r\n")

        // TODO use requested encoding if specified
        if let responseHeaders = headerData.data(using: String.Encoding.utf8) {
            responseHeaders.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
                try socketHandler.write(from: ptr, length: headerData.utf8.count)
            }
            headersWritten = true
        } else {
            //TODO handle encoding error
        }
    }

    func writeTrailer(key: String, value: String) {
        fatalError("Not implemented")
    }

    func writeBody(data: DispatchData, completion: @escaping (Result<POSIXError, ()>) -> Void) {
        guard headersWritten else {
            //TODO
            return
        }
        //TODO
        completion(Result(completion: ()))
    }

    func writeBody(data: DispatchData) /* convenience */ {
        writeBody(data: data) { _ in

        }
    }

    func writeBody(data: Data, completion: @escaping (Result<POSIXError, ()>) -> Void) {
        guard headersWritten else {
            //TODO
            return
        }
        //TODO
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
