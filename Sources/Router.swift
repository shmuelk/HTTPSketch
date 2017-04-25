import K2Spike

struct Router {
    var map: [Path: ResponseCreator]

    func route(request: HTTPRequest) -> ResponseCreator? {
        guard let verb = Verb(request.method) else {
            return nil
        }

        let url = request.target
        let path = Path(path: url, verb: verb)

        return map[path]
    }
}
