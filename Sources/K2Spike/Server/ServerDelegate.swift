public protocol ServerDelegate: class {
    func serve(req: HTTPRequest, res: HTTPResponseWriter) -> HTTPBodyProcessing
}
