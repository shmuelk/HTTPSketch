import Foundation
import Dispatch

class ResponseWriter: HTTPResponseWriter {
    private static let bufferSize = 8192

    private let httpParser: HTTPParser
    private let request: HTTPRequest
    private let socketHandler: IncomingSocketHandler
    private let isUpgrade: Bool
    private let isKeepAlive: Bool
    private let maxRequests: Int

    private var isChunked = false
    private var requestBodyBuffer: Data
    private var headersWritten = false

    init(httpParser: HTTPParser, request: HTTPRequest, socketHandler: IncomingSocketHandler, isUpgrade: Bool, isKeepAlive: Bool, maxRequests: Int) {
        self.httpParser = httpParser
        self.request = request
        self.socketHandler = socketHandler
        self.isUpgrade = isUpgrade
        self.isKeepAlive = isKeepAlive
        self.maxRequests = maxRequests
        self.requestBodyBuffer = Data(capacity: ResponseWriter.bufferSize)
    }

    func resolveHandler(_ handler:WebApp) {
        let chunkHandler = handler(request, self)
        var stop = false
        var finished = false
        while !stop && !finished {
            switch chunkHandler {
            case .processBody(let handler):
                let count = httpParser.bodyChunk.fill(data: &requestBodyBuffer)
                let data = requestBodyBuffer.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> DispatchData in
                    DispatchData(bytes: UnsafeBufferPointer<UInt8>(start: ptr, count: count))
                }
                handler(.chunk(data: data, finishedProcessing: {
                    if count <= 0 {
                        finished = true
                        handler(.end, &stop)
                    }
                }), &stop)
            case .discardBody:
                finished=true
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

        var headers = "HTTP/1.1 \(response.status.code) \(response.status.reasonPhrase)\r\n"

        switch(response.transferEncoding) {
        case .chunked:
            headers += "Transfer-Encoding: chunked\r\n"
            isChunked = true
        case .identity(let contentLength):
            headers += "Content-Length: \(contentLength)\r\n"
        }

        for (key, value) in response.headers.makeIterator() {
            headers += "\(key): \(value)\r\n"
        }

        if !isUpgrade {
            if  isKeepAlive {
                headers.append("Connection: Keep-Alive\r\n")
                headers.append("Keep-Alive: timeout=\(Int(IncomingSocketHandler.keepAliveTimeout)), max=\(maxRequests)\r\n")
            }
            else {
                headers.append("Connection: Close\r\n")
            }
        }
        headers.append("\r\n")

        // TODO use requested encoding if specified
        if let headersData = headers.data(using: String.Encoding.utf8) {
            headersData.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
                socketHandler.write(from: ptr, length: headers.utf8.count)
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
            //TODO error or default headers?
            return
        }

        guard data.count > 0 else {
            // TODO fix Result
            completion(Result(completion: ()))
            return
        }

        if isChunked {
            let chunkStart = (String(data.count, radix: 16) + "\r\n").data(using: .utf8)!
            chunkStart.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
                socketHandler.write(from: ptr, length: chunkStart.count)
            }
        }

        data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
            socketHandler.write(from: ptr, length: data.count)
        }

        if isChunked {
            let chunkEnd = "\r\n".data(using: .utf8)!
            chunkEnd.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
                socketHandler.write(from: ptr, length: chunkEnd.count)
            }
        }

        completion(Result(completion: ()))
    }

    func writeBody(data: DispatchData) /* convenience */ {
        writeBody(data: data) { _ in

        }
    }

    func writeBody(data: Data, completion: @escaping (Result<POSIXError, ()>) -> Void) {
        guard headersWritten else {
            //TODO error or default headers?
            return
        }

        guard data.count > 0 else {
            // TODO fix Result
            completion(Result(completion: ()))
            return
        }

        if isChunked {
            let chunkStart = (String(data.count, radix: 16) + "\r\n").data(using: .utf8)!
            chunkStart.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
                socketHandler.write(from: ptr, length: chunkStart.count)
            }
        }

        data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
            socketHandler.write(from: ptr, length: data.count)
        }

        if isChunked {
            let chunkEnd = "\r\n".data(using: .utf8)!
            chunkEnd.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
                socketHandler.write(from: ptr, length: chunkEnd.count)
            }
        }

        completion(Result(completion: ()))
    }

    func writeBody(data: Data) /* convenience */ {
        writeBody(data: data) { _ in

        }
    }

    func done(completion: @escaping (Result<POSIXError, ()>) -> Void) {
        if isChunked {
            let chunkTerminate = "0\r\n\r\n".data(using: .utf8)!
            chunkTerminate.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
                socketHandler.write(from: ptr, length: chunkTerminate.count)
            }
        }

        socketHandler.prepareToClose()
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
