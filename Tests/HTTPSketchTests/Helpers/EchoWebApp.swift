import Foundation
import HTTPSketch


/// Simple `WebApp` that just echoes back whatever input it gets
class EchoWebApp: WebAppContaining {
    func serve(req: HTTPRequest, res: HTTPResponseWriter ) -> HTTPBodyProcessing {
        //Assume the router gave us the right request - at least for now
        res.writeResponse(HTTPResponse(httpVersion: req.httpVersion,
                                       status: .ok,
                                       transferEncoding: .chunked,
                                       headers: HTTPHeaders([("X-foo", "bar")])))
        return .processBody { (chunk, stop) in
            switch chunk {
            case .chunk(let data, let finishedProcessing):
                res.writeBody(data: data) { _ in
                    finishedProcessing()
                }
            case .end:
                res.done()
            default:
                stop = true /* don't call us anymore */
                res.abort()
            }
        }
    }
}
