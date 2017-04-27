import LoggerAPI
import HeliumLogger

HeliumLogger.use(.info)

let port = 8080
let server = HTTPServer()
let creator = EchoWebApp()

do {
    try server.listen(on: port, delegate:creator)
    ListenerGroup.waitForListeners()
} catch {
    Log.error("Error listening on port \(port): \(error). Use server.failed(callback:) to handle")
}
