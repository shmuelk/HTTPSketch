
enum Verb: String {
    case GET = "get"
    case PUT = "put"
    case POST = "post"
    case DELETE = "delete"
    case OPTIONS = "options"
    case HEAD = "head"
    case PATCH = "patch"

    init?(_ verb: HTTPMethod) {
        switch verb {
        case .GET:
            self = .GET
        case .PUT:
            self = .PUT
        case .POST:
            self = .POST
        case .DELETE:
            self = .DELETE
        case .OPTIONS:
            self = .OPTIONS
        case .HEAD:
            self = .HEAD
        case .PATCH:
            self = .PATCH
        default:
            return nil
        }
    }
}

//struct Operation {
//    var tags: [String]
//    var summary: String
//    var description: String
//    var externalDocs: String
//    var operationId: String
//    var consumes: [String]
//    var produces: [String]
//    var parameters: [Parameter]
//    var responses: [Response]
//    var schemes: [String]
//    var deprecated: Bool
//    var security: SecurityRequirement
//}
//
//struct Response {
//
//}
//
//struct SecurityRequirement {
//
//}
//
//struct Parameter {
//
//}
//
//struct PathItem {
//    var operations: [Verb: Operation]
//    var parameters: [Parameter]
//}
//
//struct Paths {
//    var paths: [String: PathItem]
//}

public struct Path: Hashable {
    var path: String
    var verb: Verb

    /// The hash value.
    ///
    /// Hash values are not guaranteed to be equal across different executions of
    /// your program. Do not save hash values to use during a future execution.
    public var hashValue: Int {
        return "\(verb) - \(path)".hashValue
    }

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func ==(lhs: Path, rhs: Path) -> Bool {
        return lhs.path == rhs.path && lhs.verb == rhs.verb
    }
}
