// The Swift Programming Language
// https://docs.swift.org/swift-book

import Basics
import Workspace
import Foundation
import Combine
import SwiftShell

print("Hello, world!")

// PREREQUISITES
// ============

// We need a package to work with.
// This computes the path of this package root based on the file location
//let packagePath = try AbsolutePath(validating: "/Users/koninich/develop/AFSE/book-seat-backend")

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

let packagePath = "/Users/koninich/develop/addtowalletpm"
let scheme = "AddToWalletPM"
let derivedDataPath = "lala"//NSTemporaryDirectory()

// build frameworks for all platforms
let destinations = [Command.Destination.ios, Command.Destination.iosSimulator] //
for destination in destinations /*Command.Destination.allCases*/ {
    print("building \(scheme) for \(destination)")
    Command.archive(package: packagePath, scheme: scheme, destination: destination, derivedDataPath: derivedDataPath)
        .forEach { command in
//            print(command)
            try! run(command.cmd, command.args)
        }
}

// combine frameworks to an xcframework
//print("creating xcframework")
let command = Command.createXcframework(package: packagePath, scheme: scheme, destinations: destinations, derivedDataPath: derivedDataPath)
//print(command.args)
print("creating \(scheme).xcframework")
//let a = await try! safeShell(command).value
try! run(command.cmd, command.args)

struct Command: CustomStringConvertible {
    let cmd: String
    let args: [String]

    var description: String {
        return "'\(cmd)' '\(args)'"
    }

    static let xcodePath: String = { run("xcrun", "xcode-select", "--print-path").stdout }()

    static func xcodebuildPath() -> String {
        return "\(xcodePath)/usr/bin/xcodebuild".replacingOccurrences(of: "()", with: "")
    }

    enum Destination: CaseIterable, CustomStringConvertible {
        case ios, macos, iosSimulator

        var description: String {
            switch self {
            case .ios:
                return "generic/platform=iOS"
            case .macos:
                return "generic/platform=macOS"
            case .iosSimulator:
                return "generic/platform=iOS Simulator"
            }
        }
    }

    static func destinationSuffix(destination: Destination) -> String {
        switch destination {
        case .ios:
            return "iphoneos"
        case .macos:
            return "macos"
        case .iosSimulator:
            return "iphonesimulator"
        }
    }

    //xcodebuild archive -scheme $SchemeName -destination $DestinationiPhone -archivePath \(xcarchiveName(destination:destination)) -derivedDataPath $DerivedDataPath SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES
    // copy the .swiftmodule from the derived data data to the .xcarchive
    static func archive(package: String, scheme: String, destination: Destination, derivedDataPath: String) -> [Command] {
        let suffix = Command.destinationSuffix(destination:destination)
        let path = xcodebuildPath()
        let mkdir = "mkdir"
        let cp = "cp"
        
//        print("xcodebuildPath \(path)")

        return [Command.init(cmd: path,
                             args: ["archive", "-scheme", "\(scheme)", "-destination"] + ["\(destination)"] + "-archivePath Release-\(suffix).xcarchive -derivedDataPath \(derivedDataPath) SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES".split(separator: " ").map({ String($0) }) ),
                             Command.init(cmd: mkdir,
                                          args: "-p \(package)/Release-\(suffix).xcarchive/Products/usr/local/lib/\(scheme).framework/Modules/".split(separator: " ").map({ String($0) }) ),
                             Command.init(cmd: cp,
                                          args: "-r \(derivedDataPath)/Build/Intermediates.noindex/ArchiveIntermediates/\(scheme)/BuildProductsPath/Release-\(suffix)/\(scheme).swiftmodule Release-\(suffix).xcarchive/Products/usr/local/lib/\(scheme).framework/Modules/\(scheme).swiftmodule".split(separator: " ").map({ String($0) }) ),
                             Command.init(cmd: cp,
                                          args: "-r \(derivedDataPath)/Build/Intermediates.noindex/ArchiveIntermediates/\(scheme)/IntermediateBuildFilesPath/\(scheme).build/Release-\(suffix)/\(scheme).build/\(scheme).modulemap Release-\(suffix).xcarchive/Products/usr/local/lib/\(scheme).framework/Modules/".split(separator: " ").map({ String($0) }) ),
                             Command.init(cmd: mkdir,
                                          args: "-p Release-\(suffix).xcarchive/Products/usr/local/lib/\(scheme).framework/Headers/".split(separator: " ").map({ String($0) }) ),
                             Command.init(cmd: cp,
                                          args: "-r \(derivedDataPath)/Build/Intermediates.noindex/ArchiveIntermediates/\(scheme)/IntermediateBuildFilesPath/GeneratedModuleMaps-\(suffix)/AddToWalletPM-Swift.h Release-\(suffix).xcarchive/Products/usr/local/lib/\(scheme).framework/Headers".split(separator: " ").map({ String($0) }) ),
                             ]
    }

    static func createXcframework(package: String, scheme: String, destinations: [Command.Destination], derivedDataPath: String) -> Command {
            let xcodebuildPath = xcodebuildPath()
            var createXcframeworkCommandArgs = ["-create-xcframework"]

        func lala(s: Command.Destination) -> [String] {
            return  "-framework Release-\(Command.destinationSuffix(destination:s)).xcarchive/Products/usr/local/lib/\(scheme).framework".split(separator: " ").map({ String($0) })
        }

        createXcframeworkCommandArgs.append(contentsOf: destinations.flatMap({lala(s: $0) }))

        createXcframeworkCommandArgs.append(contentsOf: ["-output", "\(scheme).xcframework"])
            return Command.init(cmd: xcodebuildPath, args: createXcframeworkCommandArgs)
        }
}

extension String : LocalizedError {
    public var errorDescription: String? { self }
}

@discardableResult // Add to suppress warnings when you don't want/need a result
func safeShell(_ command: String) -> Future<String, Error> {

    let a: Future<String, Error> =
     Future { promise in
        let task = Process()
        let pipe = Pipe()

        task.currentDirectoryPath = "/Users/koninich/develop/addtowalletpm"
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.standardInput = nil

         do {
             try task.run()
         } catch {
             promise(Result.failure(error))
             return
         }

         task.terminationHandler = { t in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)!

            guard task.terminationStatus == 0 else {
                let error = output
                promise(Result.failure(error))
                                return
            }
            promise(Result.success(output))
        }
    }

    return a
}
