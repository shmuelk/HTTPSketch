//
//  TestResponseResolver.swift
//  K2Spike
//
//  Created by Carl Brown on 4/24/17.
//
//

import Foundation
import Dispatch
import K2Spike

class TestResponseResolver: HTTPResponseWriter {
    let request: HTTPRequest
    let requestBody: Data
    
    var response: HTTPResponse?
    var responseBody: Data?
    
    
    init(request: HTTPRequest, requestBody: Data) {
        self.request = request
        self.requestBody = requestBody
    }
    
    func writeContinue(headers: HTTPHeaders?) /* to send an HTTP `100 Continue` */ {
        fatalError("Not implemented")
    }
    
    func writeResponse(_ response: HTTPResponse) {
        self.response=response
    }
    
    func writeTrailer(key: String, value: String) {
        fatalError("Not implemented")
    }
    
    func writeBody(data: DispatchData, completion: @escaping (Result<POSIXError, ()>) -> Void) {
        fatalError("Not implemented")
    }
    func writeBody(data: DispatchData) /* convenience */ {
        fatalError("Not implemented")
    }
    
    func writeBody(data: Data, completion: @escaping (Result<POSIXError, ()>) -> Void) {
        self.responseBody = data
        completion(Result(completion: ()))
    }
    
    func writeBody(data: Data) /* convenience */ {
        writeBody(data: data) { _ in
            
        }
    }
    
    func done(completion: @escaping (Result<POSIXError, ()>) -> Void) {
        completion(Result(completion: ()))
    }
    func done() /* convenience */ {
        done() { _ in
        }
    }
    
    func abort() {
        fatalError("abort called, not sure what to do with it")
    }
    
}
