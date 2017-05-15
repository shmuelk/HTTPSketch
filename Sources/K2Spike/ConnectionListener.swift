//
//  ConnectionListener.swift
//  K2Spike
//
//  Created by Carl Brown on 5/2/17.
//
//

import Foundation

import LoggerAPI
import Socket

#if os(Linux)
    import Signals
    import Dispatch
#endif


// MARK: HTTPServer

/// An HTTP server that listens for connections on a socket.
public class ConnectionListener: ParserConnecting {
    var socket: Socket
    var parser: StreamingParser?
    
    var socketFD: Int32
    
    var socketReaderQueue: DispatchQueue
    var socketWriterQueue: DispatchQueue
    
    private var readerSource: DispatchSourceRead?
    
    private let _responseCompletedLock = DispatchSemaphore(value: 1)
    private var _responseCompleted: Bool = false
    var responseCompleted: Bool {
        get {
            _responseCompletedLock.wait()
            defer {
                _responseCompletedLock.signal()
            }
            return _responseCompleted
        }
        set {
            _responseCompletedLock.wait()
            defer {
                _responseCompletedLock.signal()
            }
            _responseCompleted = newValue
        }
    }
        
    // Timer that cleans up idle sockets on expire
    private var idleSocketTimer: DispatchSourceTimer?
    
    public init(socket: Socket, parser: StreamingParser) {
        self.socket = socket
        socketFD = socket.socketfd
        socketReaderQueue = DispatchQueue(label: "Socket Reader \(socket.remotePort)")
        socketWriterQueue = DispatchQueue(label: "Socket Writer \(socket.remotePort)")
        self.parser = parser
        parser.parserConnector = self
        
        idleSocketTimer = makeIdleSocketTimer()
    }
    
    private func makeIdleSocketTimer() -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "idleSocketTimer"))
        timer.scheduleRepeating(deadline: .now() + StreamingParser.keepAliveTimeout, interval: .seconds(Int(StreamingParser.keepAliveTimeout)))
        timer.setEventHandler { [weak self] in
            self?.closeIdleSocket()
        }
        timer.resume()
        return timer
    }
    
    private func closeIdleSocket() {
        if Log.isLogging(.debug) {
            print("\(#function) called for socket \(self.socket.socketfd)/\(self.socketFD)(\(Thread.current))")
        }
        if self.socket.socketfd < 0 {
            //Already closed
            self.idleSocketTimer?.cancel()
            return
        }
        let now = Date().timeIntervalSinceReferenceDate
        if let keepAliveUntil = parser?.keepAliveUntil, now >= keepAliveUntil {
            close()
        }
    }
    
    deinit {
        cleanupIdleSocketTimer()
    }
    
    private func cleanupIdleSocketTimer() {
        if Log.isLogging(.debug) {
            print("\(#function) called for socket \(self.socket.socketfd)/\(self.socketFD)(\(Thread.current))")
        }
        idleSocketTimer?.cancel()
        idleSocketTimer = nil
    }
    
    public var isOpen: Bool {
        return (socket.isActive || socket.isConnected)
    }
    
    func close() {
        if Log.isLogging(.debug) {
            print("\(#function) called for socket \(self.socket.socketfd)/\(self.socketFD)(\(Thread.current))")
        }
        if !self.responseCompleted {
            if Log.isLogging(.debug) {
            print("Response incomplete in \(#function) for socket \(self.socket.socketfd)/\(self.socketFD)(\(Thread.current))")
            }
            return
        }
        if Log.isLogging(.debug) {
            print("Closing socket \(#function) for FD \(self.socket.socketfd)/\(self.socketFD)(\(Thread.current))")
        }
        self.readerSource?.cancel()
        self.idleSocketTimer?.cancel()
        self.socket.close()
        self.parser?.parserConnector = nil
        self.parser = nil
        self.idleSocketTimer = nil
    }
    
    func closeWriter() {
        if Log.isLogging(.debug) {
            print("\(#function) called for socket \(self.socket.socketfd)/\(self.socketFD)(\(Thread.current))")
        }
        self.socketWriterQueue.async { [weak self] in
            if (self?.readerSource?.isCancelled ?? true) {
                self?.close()
            }
        }
    }
    
    public func responseBeginning() {
        if Log.isLogging(.debug) {
            print("\(#function) called for socket \(self.socket.socketfd)/\(self.socketFD)(\(Thread.current))")
        }
        self.socketWriterQueue.async { [weak self] in
            if Log.isLogging(.debug) {
                print("\(#function) run from queue for socket \(self?.socket.socketfd ?? -1)/\(self?.socketFD ?? -1)(\(Thread.current))")
            }
            self?.responseCompleted = false
        }
    }
    
    public func responseComplete() {
        if Log.isLogging(.debug) {
            print("\(#function) called for socket \(self.socket.socketfd)/\(self.socketFD)(\(Thread.current))")
        }
        self.socketWriterQueue.async { [weak self] in
            if Log.isLogging(.debug) {
                print("\(#function) run from queue for socket \(self?.socket.socketfd ?? -1)/\(self?.socketFD ?? -1)(\(Thread.current))")
            }
            self?.responseCompleted = true
            if (self?.readerSource?.isCancelled ?? true) {
                self?.close()
            }
        }
    }
    
    public func process() {
        do {
            if Log.isLogging(.debug) {
                print("process called for socket \(socket.socketfd)/\(self.socketFD)(\(Thread.current))")
            }
            
            try! socket.setBlocking(mode: true)
            
            let readerSource = DispatchSource.makeReadSource(fileDescriptor: socket.socketfd,
                                                             queue: socketReaderQueue)
            
            readerSource.setEventHandler { [weak self] in
                
                if Log.isLogging(.debug) {
                    print("ReaderSource Event Handler \(self?.socket.socketfd ?? -1)/\(self?.socketFD ?? -1) (\(Thread.current)) called with data \(readerSource.data)")
                }
                
                guard let strongSelf = self else {
                    return
                }
                guard strongSelf.socket.socketfd > 0 else {
                    readerSource.cancel()
                    return
                }
                
                var length = 1 //initial value
                do {
                    repeat {
                        let readBuffer:NSMutableData = NSMutableData()
                        length = try strongSelf.socket.read(into: readBuffer)
                        if length > 0 {
                            self?.responseCompleted = false
                        }
                        let data = Data(bytes:readBuffer.bytes.assumingMemoryBound(to: Int8.self), count:readBuffer.length)
                        
                        let numberParsed = strongSelf.parser?.readStream(data:data) ?? 0
                        
                        if numberParsed != data.count {
                            print("Error: wrong number of bytes consumed by parser (\(numberParsed) instead of \(data.count)")
                        }
                        
                    } while length > 0
                } catch {
                    print("Error: \(error)")
                }
                if (length == 0) {
                    if Log.isLogging(.debug) {
                        print("Read 0 - closing socket \(self?.socket.socketfd ?? -1)/\(self?.socketFD ?? -1) (\(Thread.current))")
                    }
                    readerSource.cancel()
                }
            }
            
            readerSource.setCancelHandler { [ weak self] in
                if Log.isLogging(.debug) {
                    print("ReaderSource Cancel Handler  \(self?.socket.socketfd ?? -1)/\(self?.socketFD ?? -1)\(Thread.current) called")
                }
                self?.close() //close if we can
            }
            
            self.readerSource = readerSource
            readerSource.resume()
        }
    }
    
    func queueSocketWrite(_ bytes: Data) {
        if Log.isLogging(.debug) {
            print("\(#function) called on FD \(self.socket.socketfd)/\(self.socketFD) (\(Thread.current)) with data \(bytes)")
        }
        if Log.isLogging(.debug) {
            let byteStringToPrint = String(data:bytes, encoding:.utf8)
            if let byteStringToPrint = byteStringToPrint {
                Log.debug("\(#function) called with '\(byteStringToPrint)'")
            } else {
                Log.debug("\(#function) called with UNPRINTABLE")
            }
        }
        self.socketWriterQueue.async { [ weak self ] in
            self?.write(bytes)
        }
    }
    
    public func write(_ data:Data) {
        if Log.isLogging(.debug) {
            print("\(#function) called on FD \(self.socket.socketfd)/\(self.socketFD) (\(Thread.current)) with data \(data)")
        }
        
        do {
            var errorResult = false
            var written: Int = 0
            var offset = 0
            
            while written < data.count && !errorResult {
                try data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
                    if Log.isLogging(.debug) {
                        print("socket.write starting on FD \(socket.socketfd)/\(socketFD) (\(Thread.current)) with data \(data)")
                    }
                    let result = try socket.write(from: ptr + offset, bufSize:
                        data.count - offset)
                    if Log.isLogging(.debug) {
                        print("strongSelf.socket.write completed on FD \(socket.socketfd)/\(socketFD) (\(Thread.current)) with data \(data)")
                    }
                    if (result < 0) {
                        print("Recived broken write socket indication")
                        errorResult = true
                    } else {
                        written += result
                    }
                }
                offset = data.count - written
            }
            if (errorResult) {
                close()
                return
            }
        } catch {
            print("Error: \(error)")
            close()
        }
    }
    
}
