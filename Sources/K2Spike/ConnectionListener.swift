//
//  ConnectionListener.swift
//  K2Spike
//
//  Created by Carl Brown on 5/2/17.
//
//

import Dispatch
import Foundation

import LoggerAPI
import Socket

import CHttpParser

#if os(Linux)
    import Signals
#if !GCD_ASYNCH
    import Glibc
    import CEpoll
#endif
#endif


// MARK: HTTPServer

/// An HTTP server that listens for connections on a socket.
public class ConnectionListener: HTTPResponseWriter {
    let socket : Socket
    let webapp : WebApp
    
    let socketReaderQueue = DispatchQueue(label: "Socket Reader")
    let socketWriterQueue = DispatchQueue(label: "Socket Writer")
    let readBuffer = NSMutableData()
    var readBufferPosition = 0
    
    let writeBuffer = NSMutableData()
    var writeBufferPosition = 0
    let keepAliveTimeout: TimeInterval = 15
    var clientRequestedKeepAlive = false
    
    var parserBuffer: DispatchData?
    
    /// The socket if idle will be kep alive until...
    var keepAliveUntil: TimeInterval = 0.0
    ///HTTP Parser
    var httpParser = http_parser()
    var httpParserSettings = http_parser_settings()
    
    var httpBodyProcessingCallback: HTTPBodyProcessing?
    
    #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
    private var readerSource: DispatchSourceRead?
    private var writerSource: DispatchSourceWrite?
    #endif
    
    public func process() {
        do {
            try socket.setBlocking(mode: false)
            
            #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
                readerSource = DispatchSource.makeReadSource(fileDescriptor: socket.socketfd,
                                                                 queue: socketReaderQueue)
                
                readerSource?.setEventHandler() {
                    // The event handler gets called with readerSource.data == 0 continually even when there
                    // is no incoming data. Till we figure out how to set the dispatch event mask to filter out
                    // this condition, we just add a check for it.
                    if self.readerSource?.data != 0 {
                        guard self.socket.isConnected && self.socket.socketfd > -1 else {
                            self.socket.close()
                            return
                        }
                        
                        do {
                            var length = 1
                            while  length > 0  {
                                length = try self.socket.read(into: self.readBuffer)
                            }
                            if  self.readBuffer.length > 0  {
                                let bytes = self.readBuffer.bytes.assumingMemoryBound(to: Int8.self) + self.readBufferPosition
                                let numberParsed = http_parser_execute(&self.httpParser, &self.httpParserSettings, bytes, self.readBuffer.length - self.readBufferPosition)

                                self.readBufferPosition += numberParsed
                                
                            }
                        }
                        catch let error as Socket.Error {
                            if error.errorCode == Int32(Socket.SOCKET_ERR_CONNECTION_RESET) {
                                Log.debug("Read from socket (file descriptor \(self.socket.socketfd)) reset. Error = \(error).")
                            } else {
                                Log.error("Read from socket (file descriptor \(self.socket.socketfd)) failed. Error = \(error).")
                            }
                        } catch {
                            Log.error("Unexpected error...")
                        }
                    }
                }
                readerSource?.setCancelHandler() {
                    if self.socket.socketfd > -1 {
                        self.socket.close()
                    }
                }
                readerSource?.resume()
            #endif
            
        } catch let error {
            Log.error("Error listening to client socket: \(error)")
        }
        
    }
    
    
    public init(socket: Socket, webapp: @escaping WebApp) {
        self.socket = socket
        self.webapp = webapp
        
        httpParserSettings.on_message_begin = {
            parser -> Int32 in
            guard let listener = ConnectionListener.getSelf(parser: parser) else {
                return Int32(0)
            }
            return listener.messageBegan()
        }
        
        httpParserSettings.on_message_complete = {
            parser -> Int32 in
            guard let listener = ConnectionListener.getSelf(parser: parser) else {
                return Int32(0)
            }
            return listener.messageCompleted()
        }
        
        httpParserSettings.on_headers_complete = {
            parser -> Int32 in
            guard let listener = ConnectionListener.getSelf(parser: parser) else {
                return Int32(0)
            }
            return listener.headersCompleted()
        }
        
        httpParserSettings.on_header_field = {
            (parser, chunk, length) -> Int32 in
            guard let listener = ConnectionListener.getSelf(parser: parser) else {
                return Int32(0)
            }
            return listener.headerFieldReceived(data: chunk, length: length)
        }
        
        httpParserSettings.on_header_value = {
            (parser, chunk, length) -> Int32 in
            guard let listener = ConnectionListener.getSelf(parser: parser) else {
                return Int32(0)
            }
            return listener.headerValueReceived(data: chunk, length: length)
        }
        
        httpParserSettings.on_body = {
            (parser, chunk, length) -> Int32 in
            guard let listener = ConnectionListener.getSelf(parser: parser) else {
                return Int32(0)
            }
            return listener.bodyReceived(data: chunk, length: length)
        }
        
        httpParserSettings.on_url = {
            (parser, chunk, length) -> Int32 in
            guard let listener = ConnectionListener.getSelf(parser: parser) else {
                return Int32(0)
            }
            return listener.urlReceived(data: chunk, length: length)
        }
        http_parser_init(&httpParser, HTTP_REQUEST)
        
        self.httpParser.data = Unmanaged.passUnretained(self).toOpaque()
        
    }

    enum CallbackRecord {
        case idle, messageBegan, messageCompleted, headersCompleted, headerFieldReceived, headerValueReceived, bodyReceived, urlReceived
    }
    var lastCallBack = CallbackRecord.idle
    var lastHeaderName: String?
    var parsedHeaders = HTTPHeaders()
    var parsedHTTPMethod: HTTPMethod?
    var parsedHTTPVersion: HTTPVersion?
    var parsedURL: URL?

    func processCurrentCallback(_ currentCallBack:CallbackRecord) {
        if lastCallBack == currentCallBack {
            return
        }
        switch lastCallBack {
        case .headerFieldReceived:
            if let parserBuffer = self.parserBuffer {
                self.lastHeaderName = String(data: Data(parserBuffer), encoding: .utf8)
                self.parserBuffer=nil
            } else {
                Log.error("Missing parserBuffer after \(lastCallBack)")
            }
        case .headerValueReceived:
            if let parserBuffer = self.parserBuffer, let lastHeaderName = self.lastHeaderName, let headerValue = String(data: Data(parserBuffer), encoding: .utf8) {
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
                if let urlString = String(data: Data(parserBuffer), encoding: .utf8) {
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
    }

    func messageBegan() -> Int32 {
        processCurrentCallback(.messageBegan)
        return 0
    }
    
    func messageCompleted() -> Int32 {
        processCurrentCallback(.messageCompleted)
        self.parsedHTTPMethod = nil
        self.parsedURL=nil
        self.parsedHeaders = HTTPHeaders()
        self.lastHeaderName = nil
        self.parserBuffer = nil
        self.parsedHTTPMethod = nil
        self.parsedHTTPVersion = nil
        if let chunkHandler = self.httpBodyProcessingCallback {
            var stop=false
            var finished=false
            while !stop && !finished {
                switch chunkHandler {
                case .processBody(let handler):
                    handler(.end, &stop)
                case .discardBody:
                    finished=true
                }
            }
        }
        return 0
    }
    
    func headersCompleted() -> Int32 {
        processCurrentCallback(.headersCompleted)
        return 0
    }
    
    func headerFieldReceived(data: UnsafePointer<Int8>?, length: Int) -> Int32 {
        processCurrentCallback(.headerFieldReceived)
        guard let data = data else { return 0 }
        data.withMemoryRebound(to: UInt8.self, capacity: length) { (ptr) -> Void in
            let buff = UnsafeBufferPointer<UInt8>(start: ptr, count: length)
            self.parserBuffer == nil ? self.parserBuffer = DispatchData(bytes:buff) : self.parserBuffer?.append(buff)
        }
        return 0
    }
    
    func headerValueReceived(data: UnsafePointer<Int8>?, length: Int) -> Int32 {
        processCurrentCallback(.headerValueReceived)
        guard let data = data else { return 0 }
        data.withMemoryRebound(to: UInt8.self, capacity: length) { (ptr) -> Void in
            let buff = UnsafeBufferPointer<UInt8>(start: ptr, count: length)
            self.parserBuffer == nil ? self.parserBuffer = DispatchData(bytes:buff) : self.parserBuffer?.append(buff)
        }
        return 0
    }
    
    func bodyReceived(data: UnsafePointer<Int8>?, length: Int) -> Int32 {
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
            let buff = UnsafeBufferPointer<UInt8>(start: ptr, count: length)
            self.parserBuffer == nil ? self.parserBuffer = DispatchData(bytes:buff) : self.parserBuffer?.append(buff)
        }
        return 0
    }
    
    static func getSelf(parser: UnsafeMutablePointer<http_parser>?) -> ConnectionListener? {
        guard let pointee = parser?.pointee.data else { return nil }
        return Unmanaged<ConnectionListener>.fromOpaque(pointee).takeUnretainedValue()
    }
    
    var headersWritten = false
    var isChunked = false

    public func writeContinue(headers: HTTPHeaders?) /* to send an HTTP `100 Continue` */ {
        fatalError("Not implemented")
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
        
        let maxRequests = 10
        
            if  clientRequestedKeepAlive {
                headers.append("Connection: Keep-Alive\r\n")
                headers.append("Keep-Alive: timeout=\(Int(keepAliveTimeout)), max=\(maxRequests)\r\n")
            }
            else {
                headers.append("Connection: Close\r\n")
            }
        headers.append("\r\n")
        
        // TODO use requested encoding if specified
        if let headersData = headers.data(using: String.Encoding.utf8) {
            headersData.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
                socketWrite(from: ptr, length: headers.utf8.count)
            }
            headersWritten = true
        } else {
            //TODO handle encoding error
        }
    }
    
    public func writeTrailer(key: String, value: String) {
        fatalError("Not implemented")
    }
    
    public func writeBody(data: DispatchData, completion: @escaping (Result<POSIXError, ()>) -> Void) {
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
                socketWrite(from: ptr, length: chunkStart.count)
            }
        }
        
        data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
            socketWrite(from: ptr, length: data.count)
        }
        
        if isChunked {
            let chunkEnd = "\r\n".data(using: .utf8)!
            chunkEnd.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
                socketWrite(from: ptr, length: chunkEnd.count)
            }
        }
        
        completion(Result(completion: ()))
    }
    
    public func writeBody(data: DispatchData) /* convenience */ {
        writeBody(data: data) { _ in
            
        }
    }
    
    public func writeBody(data: Data, completion: @escaping (Result<POSIXError, ()>) -> Void) {
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
                socketWrite(from: ptr, length: chunkStart.count)
            }
        }
        
        data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
            socketWrite(from: ptr, length: data.count)
        }
        
        if isChunked {
            let chunkEnd = "\r\n".data(using: .utf8)!
            chunkEnd.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
                socketWrite(from: ptr, length: chunkEnd.count)
            }
        }
        
        completion(Result(completion: ()))
    }
    
    public func writeBody(data: Data) /* convenience */ {
        writeBody(data: data) { _ in
            
        }
    }
    
    public func done(completion: @escaping (Result<POSIXError, ()>) -> Void) {
        if isChunked {
            let chunkTerminate = "0\r\n\r\n".data(using: .utf8)!
            chunkTerminate.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
                socketWrite(from: ptr, length: chunkTerminate.count)
            }
        }
        
        if clientRequestedKeepAlive {
            keepAliveUntil = Date(timeIntervalSinceNow:keepAliveTimeout).timeIntervalSinceReferenceDate
        } else {
            self.socket.close()
        }
        
        completion(Result(completion: ()))
    }
    
    public func done() /* convenience */ {
        done() { _ in
        }
    }
    
    public func abort() {
        fatalError("abort called, not sure what to do with it")
    }

    func socketWrite(from bytes: UnsafeRawPointer, length: Int) {
        guard self.socket.isActive && socket.socketfd > -1 else {
            //FIXME: Log.warning("Socket write() called after socket \(socket.socketfd) closed")
            self.socket.close() // flag the function defer clause to cleanup if needed
            return
        }
        
        do {
            let written: Int
            
            if  writeBuffer.length == 0 {
                written = try socket.write(from: bytes, bufSize: length)
            }
            else {
                written = 0
            }
            
            if written != length {
                self.writeBuffer.append(bytes + written, length: length - written)
                
                #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
                    if writerSource == nil {
                        writerSource = DispatchSource.makeWriteSource(fileDescriptor: socket.socketfd,
                                                                      queue: socketWriterQueue)
                        
                        writerSource!.setEventHandler() {
                            if  self.writeBuffer.length != 0 {
                                defer {
                                    #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
                                        if self.writeBuffer.length == 0, let writerSource = self.writerSource {
                                            writerSource.cancel()
                                        }
                                    #endif
                                }
                                
                                // Set handleWriteInProgress flag to true before the guard below to avoid another thread
                                // invoking close() in between us clearing the guard and setting the flag.
                                guard self.socket.isActive && self.socket.socketfd > -1 else {
                                    Log.warning("Socket closed with \(self.writeBuffer.length - self.writeBufferPosition) bytes still to be written")
                                    self.writeBuffer.length = 0
                                    self.writeBufferPosition = 0

                                    return
                                }
                                
                                do {
                                    let amountToWrite = self.writeBuffer.length - self.writeBufferPosition
                                    
                                    let written: Int
                                    
                                    if amountToWrite > 0 {
                                        written = try self.socket.write(from: self.writeBuffer.bytes + self.writeBufferPosition,
                                                                   bufSize: amountToWrite)
                                    }
                                    else {
                                        if amountToWrite < 0 {
                                            Log.error("Amount of bytes to write to file descriptor \(self.socket.socketfd) was negative \(amountToWrite)")
                                        }
                                        
                                        written = amountToWrite
                                    }
                                    
                                    if written != amountToWrite {
                                        self.writeBufferPosition += written
                                    }
                                    else {
                                        self.writeBuffer.length = 0
                                        self.writeBufferPosition = 0
                                    }
                                }
                                catch let error {
                                    if let error = error as? Socket.Error, error.errorCode == Int32(Socket.SOCKET_ERR_CONNECTION_RESET) {
                                        Log.debug("Write to socket (file descriptor \(self.socket.socketfd)) failed. Error = \(error).")
                                    } else {
                                        Log.error("Write to socket (file descriptor \(self.socket.socketfd)) failed. Error = \(error).")
                                    }
                                    
                                    // There was an error writing to the socket, close the socket
                                    self.writeBuffer.length = 0
                                    self.writeBufferPosition = 0
                                    self.socket.close()

                                }
                            }
                        }
                        writerSource!.setCancelHandler() {
                            self.writerSource = nil
                        }
                        writerSource!.resume()
                    }
                #endif
            }
        }
        catch let error {
            if let error = error as? Socket.Error, error.errorCode == Int32(Socket.SOCKET_ERR_CONNECTION_RESET) {
                Log.debug("Write to socket (file descriptor \(socket.socketfd)) failed. Error = \(error).")
            } else {
                Log.error("Write to socket (file descriptor \(socket.socketfd)) failed. Error = \(error).")
            }
        }
    }

}
