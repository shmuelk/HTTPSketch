//
//  HTTPSimpleServer.swift
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
public class HTTPSimpleServer {
    
    private let serverSocket: Socket
    private var connectionListenerList = ConnectionListenerCollection()
    
    // Timer that cleans up idle sockets on expire
    private let pruneSocketTimer: DispatchSourceTimer
    
    public var port: Int {
        return Int(serverSocket.listeningPort)
    }
    
    public init() {
        #if os(Linux)
            Signals.trap(signal: .pipe) {
                _ in
                Log.info("Receiver closed socket, SIGPIPE ignored")
            }
        #endif
        
        serverSocket = try! Socket.create()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "pruneSocketTimer"))
        timer.scheduleRepeating(deadline: .now(), interval: .seconds(Int(StreamingParser.keepAliveTimeout)))
        pruneSocketTimer = timer
    }
    
    public func start(port: Int = 0, webapp: @escaping WebApp) throws {
        try self.serverSocket.listen(on: port, maxBacklogSize: 100)
        pruneSocketTimer.setEventHandler { [weak self] in
            self?.connectionListenerList.prune()
        }
        pruneSocketTimer.resume()
        
        DispatchQueue.global().async {
            repeat {
                do {
                    let clientSocket = try self.serverSocket.acceptClientConnection()
                    let streamingParser = StreamingParser(webapp: webapp)
                    let connectionListener = ConnectionListener(socket:clientSocket, parser: streamingParser)
                    var worker: DispatchWorkItem!
                    worker = DispatchWorkItem { [weak connectionListener] in
                        if let connectionListener = connectionListener {
                            connectionListener.process()
                        }
                        worker = nil
                    }
                    DispatchQueue.global().async(execute: worker)
                    self.connectionListenerList.add(connectionListener)
                
                } catch let error {
                    Log.error("Error accepting client connection: \(error)")
                }
            } while self.serverSocket.isListening
        }
        
    }
    
    public func stop() {
        connectionListenerList.closeAll()
        serverSocket.close()
    }
    
    internal var connectionCount: Int {
        return connectionListenerList.count
    }
    
}

class ConnectionListenerCollection {

    let lock = DispatchSemaphore(value: 1)
    
    var storage = [ConnectionListener]()
    
    func add(_ listener:ConnectionListener) {
        lock.wait()
        storage.append(listener)
        lock.signal()
    }
    
    func closeAll() {
        storage.forEach { $0.close() }
    }
    
    func prune() {
        lock.wait()
        storage = storage.filter { $0.isOpen }
        lock.signal()
    }
    
    var count: Int {
        return storage.count
    }
}
