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
    private var pruneSocketTimer: DispatchSourceTimer?
    
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
    }
    
    public func start(port: Int = 0, webapp: @escaping WebApp) throws {
        try self.serverSocket.listen(on: port, maxBacklogSize: 100)
        self.pruneSocketTimer = makeIdleSocketTimer()
        DispatchQueue.global().async {
            repeat {
                do {
                    let clientSocket = try self.serverSocket.acceptClientConnection()
                    let streamingParser = StreamingParser(webapp: webapp)
                    let connectionListener = ConnectionListener(socket:clientSocket, parser: streamingParser)
                    let worker = DispatchWorkItem {
                        connectionListener.process()
                    }
                    DispatchQueue.global().async(execute: worker)
                    let container = CollectionWorker(worker: worker, listener: connectionListener)
                    self.connectionListenerList.add(container)
                
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
    
    private func makeIdleSocketTimer() -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "pruneSocketTimer"))
        timer.scheduleRepeating(deadline: .now(), interval: .seconds(Int(StreamingParser.keepAliveTimeout)))
        timer.setEventHandler { [weak self] in
            self?.connectionListenerList.prune()
        }
        timer.resume()
        return timer
    }

}

class CollectionWorker {
    let worker:DispatchWorkItem
    let listener: ConnectionListener
    init(worker:DispatchWorkItem, listener: ConnectionListener) {
        self.worker = worker
        self.listener = listener
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
    
    var storage = [WeakConnectionListener<CollectionWorker>]()
    
    func add(_ listener:CollectionWorker) {
        lock.wait()
        storage.append(WeakConnectionListener(listener))
        lock.signal()
    }
    
    func closeAll() {
        storage.filter { nil != $0.value }.forEach { $0.value?.listener.close(); $0.value?.worker.cancel()}
    }
    
    func prune() {
        lock.wait()
        storage.forEach {
            guard let container = $0.value else {
                return
            }
            if !container.listener.isOpen {
                container.worker.cancel()
            }
        }
        storage = storage.filter { nil != $0.value }.filter { $0.value?.listener.isOpen ?? false }
        lock.signal()
    }
    
    var count: Int {
        return storage.filter { nil != $0.value }.count
    }
}
