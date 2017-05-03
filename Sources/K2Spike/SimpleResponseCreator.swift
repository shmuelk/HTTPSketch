//
//  SimpleResponseCreator.swift
//  K2Spike
//
//  Created by Carl Brown on 5/1/17.
//
//

import Foundation
class SimpleResponseCreator: ResponseCreating {
    
    typealias SimpleHandlerBlock = (_ req: HTTPRequest, _ context: RequestContext, _ body: Data) -> (reponse: HTTPResponse, responseBody: Data)
    let completionHandler: SimpleHandlerBlock
    
    init(completionHandler:@escaping (_ req: HTTPRequest, _ context: RequestContext, _ body: Data) -> (reponse: HTTPResponse, responseBody: Data)) {
        self.completionHandler = completionHandler
    }
    
    var buffer = Data()
    
    func serve(req: HTTPRequest, context: RequestContext, res: HTTPResponseWriter ) -> HTTPBodyProcessing {
        return .processBody { (chunk, stop) in
            switch chunk {
            case .chunk(let data, let finishedProcessing):
                if (data.count > 0) {
                    self.buffer.append(Data(data))
                }
                finishedProcessing()
            case .end:
                let (response, body) = self.completionHandler(req, context, self.buffer)
                res.writeResponse(HTTPResponse(httpVersion: response.httpVersion,
                status: response.status,
                transferEncoding: .chunked,
                headers: response.headers))
                res.writeBody(data: body) { _ in
                        res.done()
                }
            default:
                stop = true /* don't call us anymore */
                res.abort()
            }
        }
    }
}
