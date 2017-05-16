//
//  HTTPSimpleServer.swift
//  HTTPSketch
//
//  Created by Carl Brown on 5/2/17.
//
//

import Dispatch
import Foundation

import Socket

//import HeliumLogger

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
                print("Receiver closed socket, SIGPIPE ignored")
            }
        #endif
                
        serverSocket = try! Socket.create()
        pruneSocketTimer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "pruneSocketTimer"))
    }
    
    public func start(port: Int = 0, webapp: @escaping WebApp) throws {
        try self.serverSocket.listen(on: port, maxBacklogSize: 100)
        pruneSocketTimer.setEventHandler { [weak self] in
            self?.connectionListenerList.prune()
        }
        pruneSocketTimer.scheduleRepeating(deadline: .now() + StreamingParser.keepAliveTimeout, interval: .seconds(Int(StreamingParser.keepAliveTimeout)))
        pruneSocketTimer.resume()
        
        DispatchQueue.global().async {
            repeat {
                do {
                    let clientSocket = try self.serverSocket.acceptClientConnection()
                    let streamingParser = StreamingParser(webapp: webapp)
                    let connectionListener = ConnectionListener(socket:clientSocket, parser: streamingParser)
                    DispatchQueue.global().async { [weak connectionListener] in
                        connectionListener?.process()
                    }
                    self.connectionListenerList.add(connectionListener)
                
                } catch let error {
                    print("Error accepting client connection: \(error)")
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
    class WeakConnectionListener<T: AnyObject> {
        weak var value : T?
        init (_ value: T) {
            self.value = value
        }
    }
    
    let lock = DispatchSemaphore(value: 1)
    
    var storage = [WeakConnectionListener<ConnectionListener>]()
    
    func add(_ listener:ConnectionListener) {
        lock.wait()
        storage.append(WeakConnectionListener(listener))
        lock.signal()
    }
    
    func closeAll() {
        storage.filter { nil != $0.value }.forEach { $0.value?.close() }
    }
    
    func prune() {
        lock.wait()
        storage = storage.filter { nil != $0.value }.filter { $0.value?.isOpen ?? false}
        lock.signal()
    }
    
    var count: Int {
        return storage.filter { nil != $0.value }.count
    }
}
