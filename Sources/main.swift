import Foundation
import Combine
import ArgumentParser

extension Command.Destination: ExpressibleByArgument {
    init?(argument: String) {
        self.init(rawValue: argument)
    }
}

struct xcframaker: ParsableCommand {

    @Argument(help: "The scheme to build")
    var scheme: String

    @Argument(help: "The path to the library (default to current folder)")
    var libraryFolder: String?

    @Option(help: "The platforms to build for")
    var platforms: [Command.Destination] = Command.Destination.allCases

    mutating func run() throws {
        print("Building \(scheme) for \(platforms)")
        let semaphore = DispatchSemaphore(value: 0)
        let scheme = self.scheme
        let libraryFolder = self.libraryFolder
        let platforms = self.platforms
        Task {
            try await FrameworkBuilder(scheme: scheme,
                                       originalPackagePath: libraryFolder,
                                       platforms: platforms).arun()
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
