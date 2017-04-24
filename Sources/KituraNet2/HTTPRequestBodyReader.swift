import Foundation

public protocol HTTPRequestBodyReader : class {
    func read(into data: inout Data) throws -> Int
    func read(into data: inout DispatchData) throws -> Int

    func close()
}
