//
//  StreamingParser.swift
//  K2Spike
//
//  Created by Carl Brown on 5/4/17.
//
//

import Foundation
import Dispatch

import LoggerAPI

import CHttpParser

public class StreamingParser: HTTPResponseWriter {

    let webapp : WebApp
    
    static let keepAliveTimeout: TimeInterval = 5
    var clientRequestedKeepAlive = false
    
    private let _keepAliveUntilLock = DispatchSemaphore(value: 1)
    private var _keepAliveUntil: TimeInterval?
    var keepAliveUntil: TimeInterval? {
        get {
            _keepAliveUntilLock.wait()
            defer {
                 _keepAliveUntilLock.signal()
            }
            return _keepAliveUntil
        }
        set {
            _keepAliveUntilLock.wait()
            defer {
                _keepAliveUntilLock.signal()
            }
            _keepAliveUntil = newValue
        }
    }

    let maxRequests = 100

    var parserBuffer: Data?

    ///HTTP Parser
    var httpParser = http_parser()
    var httpParserSettings = http_parser_settings()
    
    var httpBodyProcessingCallback: HTTPBodyProcessing?
    
    weak var parserConnector: ParserConnecting?
    
    var lastCallBack = CallbackRecord.idle
    var lastHeaderName: String?
    var parsedHeaders = HTTPHeaders()
    var parsedHTTPMethod: HTTPMethod?
    var parsedHTTPVersion: HTTPVersion?
    var parsedURL: URL?
    var dummyString: String?


    public init(webapp: @escaping WebApp) {
        self.webapp = webapp
        
        httpParserSettings.on_message_begin = {
            parser -> Int32 in
            guard let listener = StreamingParser.getSelf(parser: parser) else {
                return Int32(0)
            }
            return listener.messageBegan()
        }
        
        httpParserSettings.on_message_complete = {
            parser -> Int32 in
            guard let listener = StreamingParser.getSelf(parser: parser) else {
                return Int32(0)
            }
            return listener.messageCompleted()
        }
        
        httpParserSettings.on_headers_complete = {
            parser -> Int32 in
            guard let listener = StreamingParser.getSelf(parser: parser) else {
                return Int32(0)
            }
            return listener.headersCompleted()
        }
        
        httpParserSettings.on_header_field = {
            (parser, chunk, length) -> Int32 in
            guard let listener = StreamingParser.getSelf(parser: parser) else {
                return Int32(0)
            }
            return listener.headerFieldReceived(data: chunk, length: length)
        }
        
        httpParserSettings.on_header_value = {
            (parser, chunk, length) -> Int32 in
            guard let listener = StreamingParser.getSelf(parser: parser) else {
                return Int32(0)
            }
            return listener.headerValueReceived(data: chunk, length: length)
        }
        
        httpParserSettings.on_body = {
            (parser, chunk, length) -> Int32 in
            guard let listener = StreamingParser.getSelf(parser: parser) else {
                return Int32(0)
            }
            return listener.bodyReceived(data: chunk, length: length)
        }
        
        httpParserSettings.on_url = {
            (parser, chunk, length) -> Int32 in
            guard let listener = StreamingParser.getSelf(parser: parser) else {
                return Int32(0)
            }
            return listener.urlReceived(data: chunk, length: length)
        }
        http_parser_init(&httpParser, HTTP_REQUEST)
        
        self.httpParser.data = Unmanaged.passUnretained(self).toOpaque()
        
    }
    
    public func readStream(data:Data) -> Int {
        return data.withUnsafeBytes { (ptr) -> Int in
            return http_parser_execute(&self.httpParser, &self.httpParserSettings, ptr, data.count)
        }
    }
    
    enum CallbackRecord {
        case idle, messageBegan, messageCompleted, headersCompleted, headerFieldReceived, headerValueReceived, bodyReceived, urlReceived
    }
    
    @discardableResult
    func processCurrentCallback(_ currentCallBack:CallbackRecord) -> Bool {
        Log.verbose("\(#function) called from \(lastCallBack) to \(currentCallBack)")

        if lastCallBack == currentCallBack {
            return false
        }
        switch lastCallBack {
        case .headerFieldReceived:
            if let parserBuffer = self.parserBuffer {
                self.lastHeaderName = String(data: parserBuffer, encoding: .utf8)
                self.parserBuffer=nil
            } else {
                Log.error("Missing parserBuffer after \(lastCallBack)")
            }
        case .headerValueReceived:
            if let parserBuffer = self.parserBuffer, let lastHeaderName = self.lastHeaderName, let headerValue = String(data:parserBuffer, encoding: .utf8) {
                self.parsedHeaders.append(newHeader: (lastHeaderName, headerValue))
                self.lastHeaderName = nil
                self.parserBuffer=nil
            } else {
                Log.error("Missing parserBuffer after \(lastCallBack)")
            }
        case .headersCompleted:
            let methodId = self.httpParser.method
            if let methodName = http_method_str(http_method(rawValue: methodId)) {
                self.parsedHTTPMethod = HTTPMethod(rawValue: String(validatingUTF8: methodName) ?? "GET")
            }
            self.parsedHTTPVersion = (Int(self.httpParser.http_major), Int(self.httpParser.http_minor))
            
            self.parserBuffer=nil
            let request = HTTPRequest(method: self.parsedHTTPMethod!, target:self.parsedURL!.path, httpVersion: self.parsedHTTPVersion!, headers: self.parsedHeaders)
            
            self.httpBodyProcessingCallback = self.webapp(request, self)
        case .urlReceived:
            if let parserBuffer = self.parserBuffer {
                //Eat a byte
                parserBuffer.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> Void in
                    let dummyData = Data(bytes: ptr, count: 1)
                    self.dummyString = String(data:dummyData, encoding: .utf8)
                }
                if let urlString = String(data:parserBuffer, encoding: .utf8) {
                    self.parsedURL = URL(string: urlString)
                }
                self.parserBuffer=nil
            } else {
                Log.error("Missing parserBuffer after \(lastCallBack)")
            }
        case .idle:
            break
        case .messageBegan:
            break
        case .messageCompleted:
            break
        case .bodyReceived:
            break
        }
        lastCallBack = currentCallBack
        return true
    }
    
    func messageBegan() -> Int32 {
        processCurrentCallback(.messageBegan)
        return 0
    }
    
    func messageCompleted() -> Int32 {
        Log.debug("\(#function) called")
        
        let didChangeState = processCurrentCallback(.messageCompleted)
        if let chunkHandler = self.httpBodyProcessingCallback, didChangeState {
            var stop=false
            switch chunkHandler {
            case .processBody(let handler):
                handler(.end, &stop)
            case .discardBody:
                break
            }
        }
        return 0
    }
    
    func headersCompleted() -> Int32 {
        processCurrentCallback(.headersCompleted)
        //This needs to be set here and not messageCompleted if it's going to work here
        self.clientRequestedKeepAlive = (http_should_keep_alive(&httpParser) == 1)
        self.keepAliveUntil = Date(timeIntervalSinceNow: StreamingParser.keepAliveTimeout).timeIntervalSinceReferenceDate
        return 0
    }
    
    func headerFieldReceived(data: UnsafePointer<Int8>?, length: Int) -> Int32 {
        processCurrentCallback(.headerFieldReceived)
        guard let data = data else { return 0 }
        data.withMemoryRebound(to: UInt8.self, capacity: length) { (ptr) -> Void in
            self.parserBuffer == nil ? self.parserBuffer = Data(bytes:data, count:length) : self.parserBuffer?.append(ptr, count:length)
        }
        return 0
    }
    
    func headerValueReceived(data: UnsafePointer<Int8>?, length: Int) -> Int32 {
        processCurrentCallback(.headerValueReceived)
        guard let data = data else { return 0 }
        data.withMemoryRebound(to: UInt8.self, capacity: length) { (ptr) -> Void in
            self.parserBuffer == nil ? self.parserBuffer = Data(bytes:data, count:length) : self.parserBuffer?.append(ptr, count:length)
        }
        return 0
    }
    
    func bodyReceived(data: UnsafePointer<Int8>?, length: Int) -> Int32 {
        Log.info("\(#function) called")
        processCurrentCallback(.bodyReceived)
        guard let data = data else { return 0 }
        data.withMemoryRebound(to: UInt8.self, capacity: length) { (ptr) -> Void in
            let buff = UnsafeBufferPointer<UInt8>(start: ptr, count: length)
            let chunk = DispatchData(bytes:buff)
            if let chunkHandler = self.httpBodyProcessingCallback {
                var stop=false
                var finished=false
                while !stop && !finished {
                    switch chunkHandler {
                    case .processBody(let handler):
                        handler(.chunk(data: chunk, finishedProcessing: {
                            finished=true
                        }), &stop)
                    case .discardBody:
                        finished=true
                    }
                }
            }
        }
        return 0
    }
    
    func urlReceived(data: UnsafePointer<Int8>?, length: Int) -> Int32 {
        processCurrentCallback(.urlReceived)
        guard let data = data else { return 0 }
        data.withMemoryRebound(to: UInt8.self, capacity: length) { (ptr) -> Void in
            self.parserBuffer == nil ? self.parserBuffer = Data(bytes:data, count:length) : self.parserBuffer?.append(ptr, count:length)
        }
        return 0
    }
    
    static func getSelf(parser: UnsafeMutablePointer<http_parser>?) -> StreamingParser? {
        guard let pointee = parser?.pointee.data else { return nil }
        return Unmanaged<StreamingParser>.fromOpaque(pointee).takeUnretainedValue()
    }
    
    var headersWritten = false
    var isChunked = false
    
    public func writeContinue(headers: HTTPHeaders?) /* to send an HTTP `100 Continue` */ {
        var status = "HTTP/1.1 \(HTTPResponseStatus.continue.code) \(HTTPResponseStatus.continue.reasonPhrase)\r\n"
        if let headers = headers {
            for (key, value) in headers.makeIterator() {
                status += "\(key): \(value)\r\n"
            }
        }
        status += "\r\n"
        
        // TODO use requested encoding if specified
        if let data = status.data(using: .utf8) {
            self.parserConnector?.queueSocketWrite(data)
        } else {
            //TODO handle encoding error
        }
    }
    
    public func writeResponse(_ response: HTTPResponse) {
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
        
            if  clientRequestedKeepAlive {
                headers.append("Connection: Keep-Alive\r\n")
                headers.append("Keep-Alive: timeout=\(Int(StreamingParser.keepAliveTimeout)), max=\(maxRequests)\r\n")
            }
            else {
                headers.append("Connection: Close\r\n")
            }
        headers.append("\r\n")
        
        Log.debug("\(#function) about to write '\(headers)'")

        // TODO use requested encoding if specified
        if let data = headers.data(using: .utf8) {
            self.parserConnector?.queueSocketWrite(data)
            headersWritten = true
        } else {
            //TODO handle encoding error
        }
    }
    
    public func writeTrailer(key: String, value: String) {
        fatalError("Not implemented")
    }
    
    public func writeBody(data: DispatchData, completion: @escaping (Result<POSIXError, ()>) -> Void) {
        writeBody(data: Data(data), completion: completion)
    }
    
    
    public func writeBody(data: DispatchData) /* convenience */ {
        writeBody(data: data) { _ in
            
        }
    }
    
    public func writeBody(data: Data, completion: @escaping (Result<POSIXError, ()>) -> Void) {
        if Log.isLogging(.debug) {
            let bodyString=String(data:Data(data),encoding:.utf8)!
            Log.debug("\(#function) called with '\(bodyString)'")
        }

        guard headersWritten else {
            //TODO error or default headers?
            return
        }
        
        guard data.count > 0 else {
            // TODO fix Result
            completion(Result(completion: ()))
            return
        }
        
        var dataToWrite: Data!
        if isChunked {
            let chunkStart = (String(data.count, radix: 16) + "\r\n").data(using: .utf8)!
            dataToWrite = Data(chunkStart)
            dataToWrite.append(data)
            let chunkEnd = "\r\n".data(using: .utf8)!
            dataToWrite.append(chunkEnd)
        } else {
            dataToWrite = data
        }
        
        if Log.isLogging(.debug) {
            let bodyString2=String(data:Data(dataToWrite),encoding:.utf8)!
            Log.debug("\(#function) called with '\(bodyString2)'")
        }
        self.parserConnector?.queueSocketWrite(dataToWrite)
        
        completion(Result(completion: ()))
    }
    
    public func writeBody(data: Data) /* convenience */ {
        writeBody(data: data) { _ in
            
        }
    }
    
    public func done(completion: @escaping (Result<POSIXError, ()>) -> Void) {
        if isChunked {
            let chunkTerminate = "0\r\n\r\n".data(using: .utf8)!
            self.parserConnector?.queueSocketWrite(chunkTerminate)
        }
        
        self.parsedHTTPMethod = nil
        self.parsedURL=nil
        self.parsedHeaders = HTTPHeaders()
        self.lastHeaderName = nil
        self.parserBuffer = nil
        self.parsedHTTPMethod = nil
        self.parsedHTTPVersion = nil
        self.lastCallBack = .idle
        self.headersWritten = false
        self.httpBodyProcessingCallback = nil
        
        if clientRequestedKeepAlive {
            keepAliveUntil = Date(timeIntervalSinceNow:StreamingParser.keepAliveTimeout).timeIntervalSinceReferenceDate
        } else {
            self.parserConnector?.queueSocketClose()
        }
        
        let closeAfter = {
            if self.clientRequestedKeepAlive {
                self.keepAliveUntil = Date(timeIntervalSinceNow:StreamingParser.keepAliveTimeout).timeIntervalSinceReferenceDate
            } else {
                self.parserConnector?.queueSocketClose()
            }
        }
        
        completion(Result(completion: closeAfter()))
    }
    
    public func done() /* convenience */ {
        done() { _ in
        }
    }
    
    public func abort() {
        fatalError("abort called, not sure what to do with it")
    }
    
    deinit {
        httpParser.data = nil
    }

}

protocol ParserConnecting: class {
    func queueSocketWrite(_ from: Data) -> Void
    func queueSocketClose() -> Void
}
