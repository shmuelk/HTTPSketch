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
    #if !GCD_ASYNCH
        import Glibc
        import CEpoll
    #endif
#endif


// MARK: HTTPServer

/// An HTTP server that listens for connections on a socket.
public class HTTPSimpleServer {
    
    private let serverSocket: Socket
    
    public var port: Int {
        return Int(serverSocket.listeningPort)
    }
    
    init() {
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
        DispatchQueue.global().async {
            repeat {
                do {
                    let clientSocket = try self.serverSocket.acceptClientConnection()
                    let connectionListener = ConnectionListener(socket: clientSocket, webapp: webapp)
                    DispatchQueue.global().async {
                        connectionListener.process()
                    }
                } catch let error {
                    Log.error("Error accepting client connection: \(error)")
                }
            } while self.serverSocket.isListening
        }
        
    }
    
    public func stop() {
        serverSocket.close()
    }
}
