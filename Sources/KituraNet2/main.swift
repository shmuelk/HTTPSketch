import LoggerAPI
import HeliumLogger

HeliumLogger.use(.debug)

let port = 8080
let server = HTTPServer()
let creator = ResponseCreator()
server.delegate = creator

do {
    try server.listen(on: port)
    ListenerGroup.waitForListeners()
} catch {
    Log.error("Error listening on port \(port): \(error). Use server.failed(callback:) to handle")
}
