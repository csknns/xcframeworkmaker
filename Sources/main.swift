// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import Combine
import ArgumentParser

print("running")

// PREREQUISITES
// ============

// We need a package to work with.
// This computes the path of this package root based on the file location
//let packagePath = try AbsolutePath(validating: "/Users/x/develop/AFSE/book-seat-backend")

// LOADING
// =======

// There are several levels of information available.
// Each takes longer to load than the level above it, but provides more detail.
//
//let observability = ObservabilitySystem({ print("\($0): \($1)") })
//
//let workspace = try Workspace(forRootPackage: packagePath)
//
//let manifest = try await workspace.loadRootManifest(at: packagePath, observabilityScope: observability.topScope)
//
//let package = try await workspace.loadRootPackage(at: packagePath, observabilityScope: observability.topScope)
//
//let graph = try workspace.loadPackageGraph(rootPath: packagePath, observabilityScope: observability.topScope)
//
//print("dependencies\n \(graph.requiredDependencies.first!.)")

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
