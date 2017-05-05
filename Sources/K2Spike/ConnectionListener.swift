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

#if os(Linux)
    import Signals
#endif


// MARK: HTTPServer

/// An HTTP server that listens for connections on a socket.
public class ConnectionListener {
    var socket : Socket
    let parser: StreamingParser
    
    let socketReaderQueue: DispatchQueue
    let socketWriterQueue: DispatchQueue
    let readBuffer = NSMutableData()
    var readBufferPosition = 0
    
    let writeBuffer = NSMutableData()
    var writeBufferPosition = 0
    
    private var readerSource: DispatchSourceRead?
    private var writerSource: DispatchSourceWrite?
    
    public init(socket: Socket, parser: StreamingParser) {
        self.socket = socket
        socketReaderQueue = DispatchQueue(label: "Socket Reader \(socket.remotePort)")
        socketWriterQueue = DispatchQueue(label: "Socket Writer \(socket.remotePort)")

        self.parser = parser
        parser.closeConnection = self.closeWriter
        parser.writeToConnection = self.socketWrite
    }
    
    public func close() {
        self.readerSource?.cancel()
        self.writerSource?.cancel()
        self.socket.close()
    }
    
    public func closeWriter() {
        self.writerSource?.cancel()
        if let readerSource = self.readerSource {
            if readerSource.isCancelled {
                self.socket.close()
            }
        } else {
            //No reader source, we're good to close
            self.socket.close()
        }
    }
    
    public func closeReader() {
        self.readerSource?.cancel()
        if let writerSource = self.writerSource {
            if writerSource.isCancelled {
                self.socket.close()
            }
        } else {
            //No writer source, we're good to close
            self.socket.close()
        }
    }
    
    public func process() {
        do {
            try socket.setBlocking(mode: false)
            
                readerSource = DispatchSource.makeReadSource(fileDescriptor: socket.socketfd,
                                                                 queue: socketReaderQueue)
                
                readerSource?.setEventHandler() {
                    // The event handler gets called with readerSource.data == 0 continually even when there
                    // is no incoming data. Till we figure out how to set the dispatch event mask to filter out
                    // this condition, we just add a check for it.
                    if self.readerSource?.data != 0 {
                        guard self.socket.isConnected && self.socket.socketfd > -1 else {
                            self.closeReader()
                            return
                        }
                        
                        do {
                            var length = 1
                            while  length > 0  {
                                length = try self.socket.read(into: self.readBuffer)
                            }
                            if  self.readBuffer.length > 0  {
                                let bytes = self.readBuffer.bytes.assumingMemoryBound(to: Int8.self) + self.readBufferPosition
                                let length = self.readBuffer.length - self.readBufferPosition
                                let numberParsed = self.parser.readStream(bytes: bytes, len: length)

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
                        self.closeReader()
                    }
                }
                readerSource?.resume()
            
        } catch let error {
            Log.error("Error listening to client socket: \(error)")
        }
        
    }
    
    

    func socketWrite(from bytes: UnsafeRawPointer, length: Int) {
        guard self.socket.isActive && socket.socketfd > -1 else {
            Log.warning("Socket write() called after socket \(socket.socketfd) closed")
            self.closeWriter()
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
                
                if writerSource == nil {
                    writerSource = DispatchSource.makeWriteSource(fileDescriptor: socket.socketfd,
                                                                  queue: socketWriterQueue)
                    
                    writerSource!.setEventHandler() {
                        if  self.writeBuffer.length != 0 {
                            defer {
                                if self.writeBuffer.length == 0, let writerSource = self.writerSource {
                                    writerSource.cancel()
                                }
                            }
                            
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
