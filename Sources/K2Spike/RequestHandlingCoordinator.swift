//
//  RequestHandlingCoordinator.swift
//  K2Spike
//
//  Created by Carl Brown on 4/28/17.
//
//

import Foundation



public class RequestHandlingCoordinator {
    
    let router: Router
    
    public init(router: Router) {
        self.router = router
    }
        
    public func handle(req: HTTPRequest, res: HTTPResponseWriter ) -> HTTPBodyProcessing {
        let (_, responseCreator) = router.route(request: req)! //FIXME: Handle Error case
        return responseCreator.serve(req: req, context: RequestContext(dict:[:]), res: res)
    }
}

public typealias HTTPPostProcessing = (_ req: HTTPRequest, _ context: RequestContext, _ res: HTTPResponseWriter, _ processor:HTTPBodyProcessing) -> HTTPPostProcessingStatus

public typealias HTTPPreProcessing = (_ req: HTTPRequest, _ context: RequestContext) -> HTTPPreProcessingStatus

public enum HTTPPreProcessingStatus {
    case notApplicable
    case replace(req: HTTPRequest, context: RequestContext)
    case callback(completionHandler: () -> (req: HTTPRequest, context: RequestContext))
}

public enum HTTPPostProcessingStatus {
    case notApplicable
    case replace(res: HTTPResponseWriter, processor: HTTPBodyProcessing)
}
