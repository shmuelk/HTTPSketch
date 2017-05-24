//
//  HTTPCommon.swift
//  HTTPSketch
//
//  Created by Carl Brown on 4/24/17 based on 
//    https://lists.swift.org/pipermail/swift-server-dev/Week-of-Mon-20170403/000422.html
//
//

import Foundation

public typealias HTTPVersion = (Int, Int)

public typealias WebApp = (HTTPRequest, HTTPResponseWriter) -> HTTPBodyProcessing

public protocol WebAppContaining: class {
    func serve(req: HTTPRequest, res: HTTPResponseWriter ) -> HTTPBodyProcessing
}

public struct HTTPHeaders {
    var storage: [String:[String]]     /* lower cased keys */
    var original: [(String, String)]   /* original casing */
    let description: String
    
    public subscript(key: String) -> [String] {
        get {
            return storage[key.lowercased()] ?? []
        }
    }
    
    func makeIterator() -> IndexingIterator<Array<(String, String)>> {
        return original.makeIterator()
    }
    
    public mutating func append(newHeader: (String, String)) {
        original.append(newHeader)
        storage = [String:[String]]()
        let key = newHeader.0.lowercased()
        let val = newHeader.1
        
        var existing = storage[key] ?? []
        existing.append(val)
        storage[key] = existing
    }

    
    public init(_ headers: [(String, String)] = []) {
        original = headers
        description=""
        storage = [String:[String]]()
        makeIterator().forEach { (element: (String, String)) in
            let key = element.0.lowercased()
            let val = element.1
            
            var existing = storage[key] ?? []
            existing.append(val)
            storage[key] = existing
        }
    }
}

public enum Result<POSIXError, Void> {
    case success(())
    case failure(POSIXError)
    
    // MARK: Constructors
    /// Constructs a success wrapping a `closure`.
    public init(completion: ()) {
        self = .success(completion)
    }
    
    /// Constructs a failure wrapping an `POSIXError`.
    public init(error: POSIXError) {
        self = .failure(error)
    }
}
