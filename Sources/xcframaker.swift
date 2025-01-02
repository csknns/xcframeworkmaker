import Foundation
import Combine
import ArgumentParser
import SourceControl
import Basics
import SwiftShell

extension Command.Destination: ExpressibleByArgument {
    init?(argument: String) {
        self.init(rawValue: argument)
    }
}

@main
struct xcframaker: AsyncParsableCommand {

    @Argument(help: "The scheme to build")
    var scheme: String

    @Argument(help: "The path to the library (default to current folder)")
    var libraryFolder: String?

    @Option(help: "The platforms to build for")
    var platforms: [Command.Destination] = Command.Destination.allCases

    mutating func run() async throws {
        print("Building \(scheme) for \(platforms)")
        let scheme = self.scheme
        let libraryFolder = self.libraryFolder
        let platforms = self.platforms

        try await FrameworkBuilder(scheme: scheme,
                                   originalPackagePath: libraryFolder,
                                   platforms: platforms).arun()
    }
}

extension String : LocalizedError {
    public var errorDescription: String? { self }
}
