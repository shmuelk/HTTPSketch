/*
 * Copyright IBM Corporation 2016
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Dispatch
import Foundation

import LoggerAPI
import Socket

#if os(Linux)
  import Signals
#endif

// MARK: HTTPServer

/// An HTTP server that listens for connections on a socket.
public class HTTPServer {

    public typealias ServerType = HTTPServer

    /// Port number for listening for new connections.
    public private(set) var port: Int?

    public enum ServerState {
        case unknown, started, stopped, failed
    }

    /// A server state.
    public private(set) var state: ServerState = .unknown

    /// TCP socket used for listening for new connections
    private var listenSocket: Socket?

    /// Maximum number of pending connections
    private let maxPendingConnections = 100

    /// Incoming socket handler
    private var socketManager: IncomingSocketManager?
    
    /// Group for waiting on listeners
    private static let group = DispatchGroup()

    public init() {
        #if os(Linux)
            // On Linux, it is not possible to set SO_NOSIGPIPE on the socket, nor is it possible
            // to pass MSG_NOSIGNAL when writing via SSL_write(). Instead, we will receive it but
            // ignore it. This happens when a remote receiver closes a socket we are to writing to.
            Signals.trap(signal: .pipe) {
                _ in
                Log.info("Receiver closed socket, SIGPIPE ignored")
            }
        #endif
    }

    /// Listens for connections on a socket
    ///
    /// - Parameter on: port number for new connections (eg. 8080)
    /// - Parameter delegate: the delegate handler for HTTP connections
    public func listen(on port: Int, delegate: @escaping WebApp) throws {
        self.port = port
        do {
            let socket = try Socket.create()
            self.listenSocket = socket

            try socket.listen(on: port, maxBacklogSize: maxPendingConnections)

            let socketManager = IncomingSocketManager()
            self.socketManager = socketManager

            // If a random (ephemeral) port number was requested, get the listening port
            let listeningPort = Int(socket.listeningPort)
            if listeningPort != port {
                self.port = listeningPort
                // We should only expect a different port if the requested port was zero.
                if port != 0 {
                    Log.error("Listening port \(listeningPort) does not match requested port \(port)")
                }
            }

            if let delegate = socket.delegate {
                Log.info("Listening on port \(self.port!) (delegate: \(delegate))")
            } else {
                Log.info("Listening on port \(self.port!)")
            }

            // set synchronously to avoid contention in back to back server start/stop calls
            self.state = .started

            let queuedBlock = DispatchWorkItem(block: {
                self.listen(listenSocket: socket, socketManager: socketManager, delegate: delegate)
            })

            DispatchQueue.global().async(group: DispatchGroup(), execute: queuedBlock)
        }
        catch let error {
            self.state = .failed
            throw error
        }
    }

    /// Static method to create a new HTTPServer and have it listen for connections.
    ///
    /// - Parameter on: port number for accepting new connections
    /// - Parameter delegate: the delegate handler for HTTP connections
    ///
    /// - Returns: a new `HTTPServer` instance
    public static func listen(on port: Int, delegate: @escaping WebApp) throws -> HTTPServer {
        let server = HTTPServer()
        try server.listen(on: port, delegate: delegate)
        return server
    }

    /// Listen on socket while server is started and pass on to socketManager to handle
    private func listen(listenSocket: Socket, socketManager: IncomingSocketManager, delegate: @escaping WebApp) {
        repeat {
            do {
                let clientSocket = try listenSocket.acceptClientConnection()
                Log.debug("Accepted HTTP connection from: " +
                    "\(clientSocket.remoteHostname):\(clientSocket.remotePort)")

                socketManager.handle(socket: clientSocket, delegate: delegate)
            } catch let error {
                if self.state == .stopped {
                    if let socketError = error as? Socket.Error {
                        if socketError.errorCode == Int32(Socket.SOCKET_ERR_ACCEPT_FAILED) {
                            Log.info("Server has stopped listening")
                        } else {
                            Log.warning("Socket.Error accepting client connection after server stopped: \(error)")
                        }
                    } else {
                        Log.warning("Error accepting client connection after server stopped: \(error)")
                    }
                } else {
                    Log.error("Error accepting client connection: \(error)")
                }
            }
        } while self.state == .started && listenSocket.isListening

        if self.state == .started {
            Log.error("listenSocket closed without stop() being called")
            stop()
        }
    }

    /// Stop listening for new connections.
    public func stop() {
        self.state = .stopped

        listenSocket?.close()
        listenSocket = nil

        socketManager?.stop()
        socketManager = nil
    }

}
