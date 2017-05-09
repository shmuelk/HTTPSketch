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

    let socketReaderQueue: DispatchQueue
    let socketWriterQueue: DispatchQueue
    var readBuffer:NSMutableData? = NSMutableData()
    var readBufferPosition = 0
    
    var writeBuffer:NSMutableData? = NSMutableData()
    var writeBufferPosition = 0
    
    private var readerSource: DispatchSourceRead?
    private var writerSource: DispatchSourceWrite?

    // Timer that cleans up idle sockets on expire
    private var idleSocketTimer: DispatchSourceTimer?

    public init(socket: Socket, parser: StreamingParser) {
        self.socket = socket
        socketReaderQueue = DispatchQueue(label: "Socket Reader \(socket.remotePort)")
        socketWriterQueue = DispatchQueue(label: "Socket Writer \(socket.remotePort)")

        self.parser = parser
        parser.parserConnector = self

        idleSocketTimer = makeIdleSocketTimer()
    }

    private func makeIdleSocketTimer() -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "idleSocketTimer"))
        timer.scheduleRepeating(deadline: .now(), interval: .seconds(Int(StreamingParser.keepAliveTimeout)))
        timer.setEventHandler { [weak self] in
            self?.closeIdleSocket()
        }
        timer.resume()
        return timer
    }

    private func closeIdleSocket() {
        let now = Date().timeIntervalSinceReferenceDate
        if let keepAliveUntil = parser?.keepAliveUntil, now >= keepAliveUntil {
            close()
        }
    }

    deinit {
        cleanupIdleSocketTimer()
    }

    private func cleanupIdleSocketTimer() {
        idleSocketTimer?.cancel()
        idleSocketTimer = nil
    }
    
    public var isOpen: Bool {
        guard let socket = self.socket else {
            return false
        }
        return (socket.isActive || socket.isConnected)
    }
    
    public func close() {
        self.readerSource?.cancel()
        self.writerSource?.cancel()
        self.readBuffer = nil
        self.writeBuffer = nil
        self.socket?.close()
        self.socket = nil
        self.parser?.parserConnector = nil
        self.parser = nil
    }
    
    public func closeWriter() {
        self.writerSource?.cancel()
        if let readerSource = self.readerSource {
            if readerSource.isCancelled {
                self.socket?.close()
                self.readBuffer = nil
                self.writeBuffer = nil
            }
        } else {
            //No reader source, we're good to close
            self.socket?.close()
            self.readBuffer = nil
            self.writeBuffer = nil
        }
    }
    
    public func closeReader() {
        self.readerSource?.cancel()
        if let writerSource = self.writerSource {
            if writerSource.isCancelled {
                self.socket?.close()
                self.readBuffer = nil
                self.writeBuffer = nil
            }
        } else {
            //No writer source, we're good to close
            self.socket?.close()
            self.readBuffer = nil
            self.writeBuffer = nil
        }
    }
    
    public func process() {
        do {
            guard let socket = self.socket else {
                return
            }
            try socket.setBlocking(mode: false)
            
                readerSource = DispatchSource.makeReadSource(fileDescriptor: socket.socketfd,
                                                                 queue: socketReaderQueue)
                
                readerSource?.setEventHandler() {
                    guard let socket = self.socket else {
                        return
                    }
                    // The event handler gets called with readerSource.data == 0 continually even when there
                    // is no incoming data. Till we figure out how to set the dispatch event mask to filter out
                    // this condition, we just add a check for it.
                    if self.readerSource?.data != 0 {
                        guard socket.isConnected && socket.socketfd > -1 else {
                            self.closeReader()
                            return
                        }
                        
                        do {
                            guard let readBuffer = self.readBuffer else {
                                return
                            }
                            guard let parser = self.parser else {
                                return
                            }
                            var length = 1
                            while  length > 0  {
                                length = try socket.read(into: readBuffer)
                            }
                            if  readBuffer.length > 0  {
                                let bytes = readBuffer.bytes.assumingMemoryBound(to: Int8.self) + self.readBufferPosition
                                let length = readBuffer.length - self.readBufferPosition
                                let numberParsed = parser.readStream(bytes: bytes, len: length)

                                self.readBufferPosition += numberParsed
                                
                            }
                        }
                        catch let error as Socket.Error {
                            if error.errorCode == Int32(Socket.SOCKET_ERR_CONNECTION_RESET) {
                                Log.debug("Read from socket (file descriptor \(socket.socketfd)) reset. Error = \(error).")
                            } else {
                                Log.error("Read from socket (file descriptor \(socket.socketfd)) failed. Error = \(error).")
                            }
                        } catch {
                            Log.error("Unexpected error...")
                        }
                    }
                }
                readerSource?.setCancelHandler() {
                    guard let socket = self.socket else {
                        return
                    }
                    if socket.socketfd > -1 {
                        self.closeReader()
                    }
                }
                readerSource?.resume()
            
        } catch let error {
            Log.error("Error listening to client socket: \(error)")
        }
        
    }
    
    
    func queueSocketWrite(_ bytes: Data) {
        if Log.isLogging(.debug) {
            let byteStringToPrint = String(data:bytes, encoding:.utf8)
            if let byteStringToPrint = byteStringToPrint {
                Log.debug("\(#function) called with '\(byteStringToPrint)'")
            } else {
                Log.debug("\(#function) called with UNPRINTABLE")
            }
        }
        self.socketWriterQueue.async {
            self.socketWrite(from: bytes)
        }
    }

    func socketWrite(from bytes: Data) {
        let length = bytes.count
        
        if Log.isLogging(.debug) {
            if bytes.count > 0 {
                let byteStringToPrint = String(data:bytes, encoding:.utf8)
                if let byteStringToPrint = byteStringToPrint {
                    Log.debug("\(#function) called with '\(byteStringToPrint)' to \(bytes.count)")
                } else {
                    Log.debug("\(#function) called with UNPRINTABLE")
                }
            } else {
                Log.debug("\(#function) called empty")
            }
        }
        
        guard let socket = self.socket else {
            return
        }

        guard socket.isActive && socket.socketfd > -1 else {
            Log.warning("Socket write() called after socket \(socket.socketfd) closed")
            self.closeWriter()
            return
        }
        
        guard let writeBuffer = self.writeBuffer else {
            return
        }

        
        do {
            var written: Int = 0
            
            if  writeBuffer.length == 0 {
                try bytes.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
                    written = try socket.write(from: ptr, bufSize: length)
                }

            }
            else {
                written = 0
            }
            
            if written != length {
                bytes.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
                    writeBuffer.append(ptr + written, length: length - written)
                }

                
                if writerSource == nil {
                    writerSource = DispatchSource.makeWriteSource(fileDescriptor: socket.socketfd,
                                                                  queue: socketWriterQueue)
                    
                    writerSource!.setEventHandler() {
                        if  writeBuffer.length != 0 {
                            defer {
                                if writeBuffer.length == 0, let writerSource = self.writerSource {
                                    writerSource.cancel()
                                }
                            }
                            
                            guard socket.isActive && socket.socketfd > -1 else {
                                Log.warning("Socket closed with \(writeBuffer.length - self.writeBufferPosition) bytes still to be written")
                                writeBuffer.length = 0
                                self.writeBufferPosition = 0
                                
                                return
                            }
                            
                            do {
                                let amountToWrite = writeBuffer.length - self.writeBufferPosition
                                
                                let written: Int
                                
                                if amountToWrite > 0 {
                                    written = try socket.write(from: writeBuffer.bytes + self.writeBufferPosition,
                                                                    bufSize: amountToWrite)
                                }
                                else {
                                    if amountToWrite < 0 {
                                        Log.error("Amount of bytes to write to file descriptor \(socket.socketfd) was negative \(amountToWrite)")
                                    }
                                    
                                    written = amountToWrite
                                }
                                
                                if written != amountToWrite {
                                    self.writeBufferPosition += written
                                }
                                else {
                                    writeBuffer.length = 0
                                    self.writeBufferPosition = 0
                                }
                            }
                            catch let error {
                                if let error = error as? Socket.Error, error.errorCode == Int32(Socket.SOCKET_ERR_CONNECTION_RESET) {
                                    Log.debug("Write to socket (file descriptor \(socket.socketfd)) failed. Error = \(error).")
                                } else {
                                    Log.error("Write to socket (file descriptor \(socket.socketfd)) failed. Error = \(error).")
                                }
                                
                                // There was an error writing to the socket, close the socket
                                writeBuffer.length = 0
                                self.writeBufferPosition = 0
                                self.closeWriter()
                                
                            }
                        }
                    }
                    writerSource!.setCancelHandler() {
                        self.closeWriter()
                        self.writerSource = nil
                    }
                    writerSource!.resume()
                }
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
