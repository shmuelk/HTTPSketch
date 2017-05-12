//
//  HelloWorldKeepAliveWebApp.swift
//  K2Spike
//
//  Created by Carl Brown on 5/12/17.
//
//


import Foundation
import K2Spike

class HelloWorldKeepAliveWebApp: ResponseCreating {
    func serve(req: HTTPRequest, context: RequestContext, res: HTTPResponseWriter ) -> HTTPBodyProcessing {
        //Assume the router gave us the right request - at least for now
        res.writeResponse(HTTPResponse(httpVersion: req.httpVersion,
                                       status: .ok,
                                       transferEncoding: .chunked,
                                       headers: HTTPHeaders([("Connection","Keep-Alive"),("Keep-Alive","timeout=5, max=10")])))
        return .processBody { (chunk, stop) in
            switch chunk {
            case .chunk(_, let finishedProcessing):
                finishedProcessing()
            case .end:
                res.writeBody(data: "Hello, World!".data(using: .utf8)!) { _ in }
                res.done()
            default:
                stop = true /* don't call us anymore */
                res.abort()
            }
        }
    }
}
