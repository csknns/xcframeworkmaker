import Foundation
import Combine
import ArgumentParser

struct xcframaker: ParsableCommand {

    @Argument(help: "The scheme to build")
    var scheme: String

    @Argument(help: "The path to the library (default to current folder)")
    var libraryFolder: String?

    mutating func run() throws {
        print("run")
        let semaphore = DispatchSemaphore(value: 0)
        let scheme = self.scheme
        let libraryFolder = self.libraryFolder
        Task {
            try await FrameworkBuilder(scheme: scheme, originalPackagePath: libraryFolder).arun()
            semaphore.signal()
        }
        semaphore.wait()
        print("run end")
    }
}

xcframaker.main()

extension String : LocalizedError {
    public var errorDescription: String? { self }
}
