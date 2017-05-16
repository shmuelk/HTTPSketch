//
//  ConnectionListener.swift
//  HTTPSketch
//
//  Created by Carl Brown on 5/2/17.
//
//

import Foundation

import Socket

#if os(Linux)
    import Signals
    import Dispatch
#endif

public class ConnectionListener: ParserConnecting {
    var socket: Socket?
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
        
    public init(socket: Socket, parser: StreamingParser) {
        self.socket = socket
        socketFD = socket.socketfd
        socketReaderQueue = DispatchQueue(label: "Socket Reader \(socket.remotePort)")
        socketWriterQueue = DispatchQueue(label: "Socket Writer \(socket.remotePort)")
        self.parser = parser
        parser.parserConnector = self
    }
    
    
    public var isOpen: Bool {
        guard let socket = self.socket else {
            return false
        }
        return (socket.isActive || socket.isConnected)
    }
    
    func close() {
        if !self.responseCompleted && !self.errorOccurred {
            return
        }
        self.readerSource?.cancel()
        self.readerSource = nil
        self.socket?.close()
        self.socket = nil
        self.parser?.parserConnector = nil //allows for memory to be reclaimed
        self.parser = nil
    }
    
    func closeWriter() {
        self.socketWriterQueue.async { [weak self] in
            if (self?.readerSource?.isCancelled ?? true) {
                self?.close()
            }
        }
    }
    
    public func responseBeginning() {
        self.socketWriterQueue.async { [weak self] in
            self?.responseCompleted = false
        }
    }
    
    public func responseComplete() {
        self.socketWriterQueue.async { [weak self] in
            self?.responseCompleted = true
            if (self?.readerSource?.isCancelled ?? true) {
                self?.close()
            }
        }
    }
    
    public func process() {
        do {
            try! socket?.setBlocking(mode: true)
            
            let tempReaderSource = DispatchSource.makeReadSource(fileDescriptor: socket?.socketfd ?? -1,
                                                             queue: socketReaderQueue)
            
            tempReaderSource.setEventHandler { [weak self] in
                
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
                    print("ReaderSource Event Error: \(error)")
                    self?.readerSource?.cancel()
                    self?.errorOccurred = true
                    self?.close()
                }
                if (length == 0) {
                    self?.readerSource?.cancel()
                }
                if (length < 0) {
                    self?.errorOccurred = true
                    self?.readerSource?.cancel()
                    self?.close()
                }
            }
            
            tempReaderSource.setCancelHandler { [ weak self] in
                self?.close() //close if we can
            }
            
            self.readerSource = tempReaderSource
            self.readerSource?.resume()
        }
    }
    
    func queueSocketWrite(_ bytes: Data) {
        self.socketWriterQueue.async { [ weak self ] in
            self?.write(bytes)
        }
    }
    
    public func write(_ data:Data) {
        do {
            var written: Int = 0
            var offset = 0
            
            while written < data.count && !errorOccurred {
                try data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
                    let result = try socket?.write(from: ptr + offset, bufSize:
                        data.count - offset) ?? -1
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
            print("Recived write socket error: \(error)")
            errorOccurred = true
            close()
        }
    }
}
