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
    var socket: Socket?
    var parser: StreamingParser?
    
    var socketFD: Int32
    
    var socketReaderQueue: DispatchQueue
    var socketWriterQueue: DispatchQueue
    
    private var readerSource: DispatchSourceRead?
    
    private weak var pruner: Pruning?
    
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
    
    private let _errorOccurredLock = DispatchSemaphore(value: 1)
    private var _errorOccurred: Bool = false
    var errorOccurred: Bool {
        get {
            _errorOccurredLock.wait()
            defer {
                _errorOccurredLock.signal()
            }
            return _errorOccurred
        }
        set {
            _errorOccurredLock.wait()
            defer {
                _errorOccurredLock.signal()
            }
            _errorOccurred = newValue
        }
    }
    
    // Timer that cleans up idle sockets on expire
    private var idleSocketTimer: DispatchSourceTimer?
    
    public init(socket: Socket, parser: StreamingParser, pruner:Pruning? = nil) {
        self.socket = socket
        socketFD = socket.socketfd
        socketReaderQueue = DispatchQueue(label: "Socket Reader \(socket.remotePort)")
        socketWriterQueue = DispatchQueue(label: "Socket Writer \(socket.remotePort)")
        self.parser = parser
        parser.parserConnector = self
        
        self.pruner = pruner
        
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
            print("\(#function) called for socket \(self.socket?.socketfd ?? -1)/\(self.socketFD)(\(Thread.current))")
        }
        if self.socket?.socketfd ?? -1 < 0 {
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
        if Log.isLogging(.debug) {
            print("\(#function) called for socket \(self.socket?.socketfd ?? -1)/\(self.socketFD)(\(Thread.current))")
        }
        cleanupIdleSocketTimer()
    }
    
    private func cleanupIdleSocketTimer() {
        if Log.isLogging(.debug) {
            print("\(#function) called for socket \(self.socket?.socketfd ?? -1)/\(self.socketFD)(\(Thread.current))")
        }
        idleSocketTimer?.cancel()
        idleSocketTimer = nil
    }
    
    public var isOpen: Bool {
        guard let socket = self.socket else {
            return false
        }
        return (socket.isActive || socket.isConnected)
    }
    
    func close() {
        if Log.isLogging(.debug) {
            print("\(#function) called for socket \(self.socket?.socketfd ?? -1)/\(self.socketFD)(\(Thread.current))")
        }
        if !self.responseCompleted && !self.errorOccurred {
            if Log.isLogging(.debug) {
            print("Response incomplete in \(#function) for socket \(self.socket?.socketfd ?? -1)/\(self.socketFD)(\(Thread.current))")
            }
            return
        }
        if Log.isLogging(.debug) {
            print("Closing socket \(#function) for FD \(self.socket?.socketfd ?? -1)/\(self.socketFD)(\(Thread.current))")
        }
        self.readerSource?.cancel()
        self.readerSource = nil
        self.idleSocketTimer?.cancel()
        self.socket?.close()
        self.socket = nil
        self.parser?.parserConnector = nil //allows for memory to be reclaimed
        self.parser = nil
        self.idleSocketTimer = nil
        self.pruner?.prune()
    }
    
    func closeWriter() {
        if Log.isLogging(.debug) {
            print("\(#function) called for socket \(self.socket?.socketfd ?? -1)/\(self.socketFD)(\(Thread.current))")
        }
        self.socketWriterQueue.async { [weak self] in
            if (self?.readerSource?.isCancelled ?? true) {
                self?.close()
            }
        }
    }
    
    public func responseBeginning() {
        if Log.isLogging(.debug) {
            print("\(#function) called for socket \(self.socket?.socketfd ?? -1)/\(self.socketFD)(\(Thread.current))")
        }
        self.socketWriterQueue.async { [weak self] in
            if Log.isLogging(.debug) {
                print("\(#function) run from queue for socket \(self?.socket?.socketfd ?? -1)/\(self?.socketFD ?? -1)(\(Thread.current))")
            }
            self?.responseCompleted = false
        }
    }
    
    public func responseComplete() {
        if Log.isLogging(.debug) {
            print("\(#function) called for socket \(self.socket?.socketfd ?? -1)/\(self.socketFD)(\(Thread.current))")
        }
        self.socketWriterQueue.async { [weak self] in
            if Log.isLogging(.debug) {
                print("\(#function) run from queue for socket \(self?.socket?.socketfd ?? -1)/\(self?.socketFD ?? -1)(\(Thread.current))")
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
                print("process called for socket \(socket?.socketfd ?? -1)/\(self.socketFD)(\(Thread.current))")
            }
            
            try! socket?.setBlocking(mode: true)
            
            let tempReaderSource = DispatchSource.makeReadSource(fileDescriptor: socket?.socketfd ?? -1,
                                                             queue: socketReaderQueue)
            
            tempReaderSource.setEventHandler { [weak self] in
                
                if Log.isLogging(.debug) {
                    print("ReaderSource Event Handler \(self?.socket?.socketfd ?? -1)/\(self?.socketFD ?? -1) (\(Thread.current)) called with data \(self?.readerSource?.data ?? 0)")
                }
                
                guard let strongSelf = self else {
                    return
                }
                guard strongSelf.socket?.socketfd ?? -1 > 0 else {
                    self?.readerSource?.cancel()
                    return
                }
                
                var length = 1 //initial value
                do {
                    repeat {
                        let readBuffer:NSMutableData = NSMutableData()
                        length = try strongSelf.socket?.read(into: readBuffer) ?? -1
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
                    if Log.isLogging(.info) {
                        print("ReaderSource Event Error: \(error)")
                    }
                    self?.readerSource?.cancel()
                    self?.errorOccurred = true
                    self?.close()
                }
                if (length == 0) {
                    if Log.isLogging(.debug) {
                        print("Read 0 - closing socket \(self?.socket?.socketfd ?? -1)/\(self?.socketFD ?? -1) (\(Thread.current))")
                    }
                    self?.readerSource?.cancel()
                }
                if (length < 0) {
                    if Log.isLogging(.debug) {
                        print("Read < 0 - closing socket \(self?.socket?.socketfd ?? -1)/\(self?.socketFD ?? -1) (\(Thread.current))")
                    }
                    self?.errorOccurred = true
                    self?.readerSource?.cancel()
                    self?.close()
                }
            }
            
            tempReaderSource.setCancelHandler { [ weak self] in
                if Log.isLogging(.debug) {
                    print("ReaderSource Cancel Handler  \(self?.socket?.socketfd ?? -1)/\(self?.socketFD ?? -1)\(Thread.current) called")
                }
                self?.close() //close if we can
            }
            
            self.readerSource = tempReaderSource
            self.readerSource?.resume()
        }
    }
    
    func queueSocketWrite(_ bytes: Data) {
        if Log.isLogging(.debug) {
            print("\(#function) called on FD \(self.socket?.socketfd ?? -1)/\(self.socketFD) (\(Thread.current)) with data \(bytes)")
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
            print("\(#function) called on FD \(self.socket?.socketfd ?? -1)/\(self.socketFD) (\(Thread.current)) with data \(data)")
        }
        
        do {
            var written: Int = 0
            var offset = 0
            
            while written < data.count && !errorOccurred {
                try data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
                    if Log.isLogging(.debug) {
                        print("socket.write starting on FD \(socket?.socketfd ?? -1)/\(socketFD) (\(Thread.current)) with data \(data)")
                    }
                    let result = try socket?.write(from: ptr + offset, bufSize:
                        data.count - offset) ?? -1
                    if Log.isLogging(.debug) {
                        print("strongSelf.socket.write completed on FD \(socket?.socketfd ?? -1)/\(socketFD) (\(Thread.current)) with data \(data)")
                    }
                    if (result < 0) {
                        print("Recived broken write socket indication")
                        errorOccurred = true
                    } else {
                        written += result
                    }
                }
                offset = data.count - written
            }
            if (errorOccurred) {
                close()
                return
            }
        } catch {
            if Log.isLogging(.info) {
                print("Writing Error: \(error)")
            }
            errorOccurred = true
            close()
        }
    }
    
}

public protocol Pruning: class {
    func prune() -> ()
}
