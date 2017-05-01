//
//  HelloWorldWebApp.swift
//  K2Spike
//
//  Created by Carl Brown on 4/27/17.
//
//

import Foundation
import K2Spike

class HelloWorldWebApp: ResponseCreating {
    func serve(req: HTTPRequest, context: RequestContext, res: HTTPResponseWriter ) -> HTTPBodyProcessing {
        //Assume the router gave us the right request - at least for now
        res.writeResponse(HTTPResponse(httpVersion: req.httpVersion,
                                       status: .ok,
                                       transferEncoding: .chunked,
                                       headers: HTTPHeaders([("X-foo", "bar")])))
        return .processBody { (chunk, stop) in
            switch chunk {
            case .chunk(_, let finishedProcessing):
                res.writeBody(data: "Hello, World!".data(using: .utf8)!) { _ in
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
