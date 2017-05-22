//
//  HTTPResponse.swift
//  HTTPSketch
//
//  Created by Carl Brown on 4/24/17based on
//    https://lists.swift.org/pipermail/swift-server-dev/Week-of-Mon-20170403/000422.html
//
//

import Foundation
import Dispatch

public struct HTTPResponse {
    public var httpVersion : HTTPVersion
    public var status: HTTPResponseStatus
    public var transferEncoding: HTTPTransferEncoding
    public var headers: HTTPHeaders
    
    public init (httpVersion: HTTPVersion,
                 status: HTTPResponseStatus,
        transferEncoding: HTTPTransferEncoding,
        headers: HTTPHeaders) {
        self.httpVersion = httpVersion
        self.status = status
        self.transferEncoding = transferEncoding
        self.headers = headers
    }
}

public protocol HTTPResponseWriter : class {
    func writeContinue(headers: HTTPHeaders?) /* to send an HTTP `100 Continue` */
    
    func writeResponse(_ response: HTTPResponse)
    
    func writeTrailer(key: String, value: String)
    
    func writeBody(data: DispatchData, completion: @escaping (Result<POSIXError, ()>) -> Void)
    func writeBody(data: DispatchData) /* convenience */

    func writeBody(data: Data, completion: @escaping (Result<POSIXError, ()>) -> Void)
    func writeBody(data: Data) /* convenience */

    func done() /* convenience */
    func done(completion: @escaping (Result<POSIXError, ()>) -> Void)
    func abort()
}

public enum HTTPTransferEncoding {
    case identity(contentLength: UInt)
    case chunked
}

public enum HTTPResponseStatus: UInt16, RawRepresentable {
    /* use custom if you want to use a non-standard response code or
     have it available in a (UInt, String) pair from a higher-level web framework. */
    //case custom(code: UInt, reasonPhrase: String)
    
    /* all the codes from http://www.iana.org/assignments/http-status-codes */
    case `continue`
    case switchingProtocols
    case processing
    case ok
    case created
    case accepted
    case nonAuthoritativeInformation
    case noContent
    case resetContent
    case partialContent
    case multiStatus
    case alreadyReported
    case imUsed
    case multipleChoices
    case movedPermanently
    case found
    case seeOther
    case notModified
    case useProxy
    case temporaryRedirect
    case permanentRedirect
    case badRequest
    case unauthorized
    case paymentRequired
    case forbidden
    case notFound
    case methodNotAllowed
    case notAcceptable
    case proxyAuthenticationRequired
    case requestTimeout
    case conflict
    case gone
    case lengthRequired
    case preconditionFailed
    case payloadTooLarge
    case uriTooLong
    case unsupportedMediaType
    case rangeNotSatisfiable
    case expectationFailed
    case misdirectedRequest
    case unprocessableEntity
    case locked
    case failedDependency
    case upgradeRequired
    case preconditionRequired
    case tooManyRequests
    case requestHeaderFieldsTooLarge
    case unavailableForLegalReasons
    case internalServerError
    case notImplemented
    case badGateway
    case serviceUnavailable
    case gatewayTimeout
    case httpVersionNotSupported
    case variantAlsoNegotiates
    case insufficientStorage
    case loopDetected
    case notExtended
    case networkAuthenticationRequired
}

extension HTTPResponseStatus {
    public var reasonPhrase: String {
        switch(self) {
//        case .custom(_, let reasonPhrase):
//            return reasonPhrase
        case .`continue`:
            return "CONTINUE"
        default:
            return String(describing: self)
        }
    }
    
    public var code: UInt {
        switch(self) {
//        case .custom(let code, _):
//            return code
        case .`continue`:
            return 100
        case .switchingProtocols:
            return 101
        case .processing:
            return 102
        case .ok:
            return 200
        case .created:
            return 201
        case .accepted:
            return 202
        case .nonAuthoritativeInformation:
            return 203
        case .noContent:
            return 204
        case .resetContent:
            return 205
        case .partialContent:
            return 206
        case .multiStatus:
            return 207
        case .alreadyReported:
            return 208
        case .imUsed:
            return 226
        case .multipleChoices:
            return 300
        case .movedPermanently:
            return 301
        case .found:
            return 302
        case .seeOther:
            return 303
        case .notModified:
            return 304
        case .useProxy:
            return 305
        case .temporaryRedirect:
            return 307
        case .permanentRedirect:
            return 308
        case .badRequest:
            return 400
        case .unauthorized:
            return 401
        case .paymentRequired:
            return 402
        case .forbidden:
            return 403
        case .notFound:
            return 404
        case .methodNotAllowed:
            return 405
        case .notAcceptable:
            return 406
        case .proxyAuthenticationRequired:
            return 407
        case .requestTimeout:
            return 408
        case .conflict:
            return 409
        case .gone:
            return 410
        case .lengthRequired:
            return 411
        case .preconditionFailed:
            return 412
        case .payloadTooLarge:
            return 413
        case .uriTooLong:
            return 414
        case .unsupportedMediaType:
            return 415
        case .rangeNotSatisfiable:
            return 416
        case .expectationFailed:
            return 417
        case .misdirectedRequest:
            return 421
        case .unprocessableEntity:
            return 422
        case .locked:
            return 423
        case .failedDependency:
            return 424
        case .upgradeRequired:
            return 426
        case .preconditionRequired:
            return 428
        case .tooManyRequests:
            return 429
        case .requestHeaderFieldsTooLarge:
            return 431
        case .unavailableForLegalReasons:
            return 451
        case .internalServerError:
            return 500
        case .notImplemented:
            return 501
        case .badGateway:
            return 502
        case .serviceUnavailable:
            return 503
        case .gatewayTimeout:
            return 504
        case .httpVersionNotSupported:
            return 505
        case .variantAlsoNegotiates:
            return 506
        case .insufficientStorage:
            return 507
        case .loopDetected:
            return 508
        case .notExtended:
            return 510
        case .networkAuthenticationRequired:
            return 511
        }
    }
    
    public static func from(code: UInt) -> HTTPResponseStatus? {
        switch code {
        case 100:
            return .`continue`
        case 101:
            return .switchingProtocols
        case 102:
            return .processing
        case 200:
            return .ok
        case 201:
            return .created
        case 202:
            return .accepted
        case 203:
            return .nonAuthoritativeInformation
        case 204:
            return .noContent
        case 205:
            return .resetContent
        case 206:
            return .partialContent
        case 207:
            return .multiStatus
        case 208:
            return .alreadyReported
        case 226:
            return .imUsed
        case 300:
            return .multipleChoices
        case 301:
            return .movedPermanently
        case 302:
            return .found
        case 303:
            return .seeOther
        case 304:
            return .notModified
        case 305:
            return .useProxy
        case 307:
            return .temporaryRedirect
        case 308:
            return .permanentRedirect
        case 400:
            return .badRequest
        case 401:
            return .unauthorized
        case 402:
            return .paymentRequired
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 405:
            return .methodNotAllowed
        case 406:
            return .notAcceptable
        case 407:
            return .proxyAuthenticationRequired
        case 408:
            return .requestTimeout
        case 409:
            return .conflict
        case 410:
            return .gone
        case 411:
            return .lengthRequired
        case 412:
            return .preconditionFailed
        case 413:
            return .payloadTooLarge
        case 414:
            return .uriTooLong
        case 415:
            return .unsupportedMediaType
        case 416:
            return .rangeNotSatisfiable
        case 417:
            return .expectationFailed
        case 421:
            return .misdirectedRequest
        case 422:
            return .unprocessableEntity
        case 423:
            return .locked
        case 424:
            return .failedDependency
        case 426:
            return .upgradeRequired
        case 428:
            return .preconditionRequired
        case 429:
            return .tooManyRequests
        case 431:
            return .requestHeaderFieldsTooLarge
        case 451:
            return .unavailableForLegalReasons
        case 500:
            return .internalServerError
        case 501:
            return .notImplemented
        case 502:
            return .badGateway
        case 503:
            return .serviceUnavailable
        case 504:
            return .gatewayTimeout
        case 505:
            return .httpVersionNotSupported
        case 506:
            return .variantAlsoNegotiates
        case 507:
            return .insufficientStorage
        case 508:
            return .loopDetected
        case 510:
            return .notExtended
        case 511:
            return .networkAuthenticationRequired
            
        default:
            return nil
        }
    }
}

