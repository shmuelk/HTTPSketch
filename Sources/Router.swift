import HTTPAPISketch

struct Action {

}

struct Router {
    var map: [Path: Action]

    func route(request: HTTPRequest) -> Action? {
        guard let verb = Verb(request.method) else {
            return nil
        }

        let url = request.target
        let path = Path(path: url, verb: verb)

        return map[path]
    }
}
