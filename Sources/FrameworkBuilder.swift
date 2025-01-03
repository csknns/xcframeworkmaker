//
//  FrameworkBuilder.swift
//  
//
//  Created by Christos koninis on 4/10/24.
//

import Foundation
import Combine
import SwiftShell
import PackageModel
import Workspace
import Basics

struct FrameworkBuilder {
    let tempDir = NSTemporaryDirectory()
    let originalPackagePath: String
    let packagePath: String

    var scheme: String
    let platforms: [Command.Destination]

    init(scheme: String, originalPackagePath: String?, platforms: [Command.Destination]) throws {
        self.scheme = scheme
        self.platforms = platforms
        self.originalPackagePath = originalPackagePath ?? FileManager.default.currentDirectoryPath
        packagePath = "\(tempDir)/\(scheme)"

        // Clean up data from temp directory
        try? runAndPrint("rm", "-r", "-f", "\(packagePath)/")
        try runAndPrint("mkdir", "\(packagePath)/")
        // Copy library files to a temp folder
        try runAndPrint("cp", "-r", "\(self.originalPackagePath)/", "\(packagePath)")

        
        main.currentdirectory = packagePath
        main.stdout = try SwiftShellLogger(derivedDataPath: packagePath)
        main.stderror = try SwiftShellLogger(derivedDataPath: packagePath)
    }

    func arun() async throws {
        let scheme = scheme
        let derivedDataPath = "\(packagePath)/derivedData"//

        try? runAndPrint("rm", "-rf", "\(derivedDataPath)")

        removeXcodeProjectAndWorkspace()
        try await addDynamicTypeToLibraryTarget()

        // build frameworks for all platforms
        var platformsBuildSuccesfully = platforms
        for destination in platforms {
            print("building '\(scheme)' for '\(destination)'  ", terminator: "")
            for command in Command.archive(package: packagePath,
                                           scheme: scheme,
                                           destination: destination,
                                           derivedDataPath: derivedDataPath) {
                do {
                    // build the framework for the platform
                    try command.run()
                } catch {
                    print("FAILED (will not add to xcframework)")
                    // if the build fails, to not include the framework
                    // for this platform in the final xcframework
                    platformsBuildSuccesfully.removeAll(where: { $0 == destination })
                    break;
                }
            }
            if platformsBuildSuccesfully.contains(destination) {
                print("DONE")
            }
        }

        // combine frameworks to an xcframework
        let command = Command.createXcframework(package: packagePath,
                                                scheme: scheme,
                                                destinations: platformsBuildSuccesfully,
                                                derivedDataPath: derivedDataPath)
        print("creating \(scheme).xcframework")

        //TODO: name should be taken from the createXcframework command
        // delete previous framework, of the create command will fail
        try? runAndPrint("rm", "-r", "\(packagePath)/\(scheme).xcframework")
        try! command.run()

        print("full build log \(packagePath)/build.log")

        print("created \(packagePath)/\(scheme).xcframework")
    }

    // If in the same folder we have Package.swift and an xcode project,
    // xcodebuild tries to build the xcode project
    // with no way of pointing to SPM library
    func removeXcodeProjectAndWorkspace() {
        let manager = FileManager.default
        try! manager.contentsOfDirectory(atPath: packagePath)
            .filter({ $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") })
            .forEach({ try! manager.removeItem(atPath: $0) })
    }

    func addDynamicTypeToLibraryTarget() async throws {
        //find the correct package.swift manifest depending on the swift version e.g. Package@swift-5.8.swift
        //modify it to add "type: .dynamic" to the library we are building
        //this is needed in order to produce the .framework
        // default are static libs
        let packageAbsPath = try AbsolutePath(validating: packagePath)
        let customToolsVersion = detectToolsVersion() ?? ToolsVersion.current
        let workspace = try Workspace.makeWorkspace(forRootPackage: packageAbsPath, customToolsVersion: customToolsVersion)
        let observability = ObservabilitySystem({ print("\($0): \($1)") })

        var manifest = try await workspace.loadRootManifest(at: packageAbsPath,
                                                            observabilityScope: observability.topScope)

        guard let library = manifest.products.first(where: { $0.name == scheme }) else {
            print("Could not find library with name '\(scheme)'")
            return
        }

        // Add .dynamic to target
        let newProduct = try ProductDescription(name: library.name,
                                                type: .library(.dynamic),
                                                targets: library.targets)

        let newProducts = manifest.products.map { p in
            if p.name == scheme {
                return newProduct
            } else {
                return p
            }
        }

        let newManifest = Manifest(displayName: manifest.displayName,
                                   path: manifest.path,
                                   packageKind: manifest.packageKind,
                                   packageLocation: manifest.packageLocation,
                                   defaultLocalization: manifest.defaultLocalization,
                                   platforms: manifest.platforms,
                                   version: manifest.version,
                                   revision: manifest.revision,
                                   toolsVersion: manifest.toolsVersion,
                                   pkgConfig: manifest.pkgConfig,
                                   providers: manifest.providers,
                                   cLanguageStandard: manifest.cLanguageStandard,
                                   cxxLanguageStandard: manifest.cxxLanguageStandard,
                                   swiftLanguageVersions: manifest.swiftLanguageVersions,
                                   dependencies: manifest.dependencies,
                                   products: newProducts,
                                   targets: manifest.targets)

        let packageDirectory = try AbsolutePath(validating: packagePath)
        let newContents
        = newManifest.generateManifestFileContents(packageDirectory: packageDirectory) { productDescription in
            return SourceCodeFragment(from: productDescription)
        }

        try newContents.write(toFile: manifest.path.pathString,
                              atomically: true,
                              encoding: .utf8)  

        print("writing new manifest to \(manifest.path.pathString)")
    }

    private func detectToolsVersion() -> ToolsVersion? {
        let consoleOutput = SwiftShell.run("swift", "--version").stdout
        // The stdout is something like:
        // swift-driver version: 1.87.3 Apple Swift version 5.9.2 (swiftlang-5.9.2.2.56 clang-1500.1.0.2.5) Target: arm64-apple-macosx14.0

        // return onlny the Swift version
        if let swiftVersion = swiftVersionString(from: consoleOutput) {
            return ToolsVersion(string: swiftVersion)
        }

        return nil
    }

    /// Extract the Swift version from the output of `swift --version` command
    /// 
    /// Example input: `Apple Swift version 5.9.2 (swiftlang-....'`
    /// Example output: `5.9.2`
    ///
    /// - Parameter versionString: the output of `swift --version` command
    /// - Returns: the Swift version as a string
    private func swiftVersionString(from versionString: String) -> String? {
        guard let match = versionString.range(of: "Apple Swift version ([0-9.]+)", options: .regularExpression) else {
            return nil
        }

        let extracted = versionString[match]
        return extracted.components(separatedBy: " ").last
    }
}

struct Command: CustomStringConvertible {
    let cmd: String
    let args: [String]
    let allowToFail: Bool

    init(cmd: String, args: [String], allowToFail: Bool = false) {
        self.cmd = cmd
        self.args = args
        self.allowToFail = allowToFail
    }

    func run() throws {
        if allowToFail {
            try? runAndPrint(cmd, args)
        } else {
            try runAndPrint(cmd, args)
        }
    }

    var description: String {
        return "'\(cmd)' '\(args)'"
    }

    static let xcodePath: String = { SwiftShell.run("xcrun", "xcode-select", "--print-path").stdout }()

    static func xcodebuildPath() -> String {
        return "\(xcodePath)/usr/bin/xcodebuild".replacingOccurrences(of: "()", with: "")
    }

    enum Destination: String, CaseIterable, CustomStringConvertible, Equatable {
        case ios, iosSimulator, macos, tvos, tvosSimulator, watchos, watchosSimulator

        //tvOS Simulator
        var description: String {
            switch self {
            case .ios:
                return "generic/platform=iOS"
            case .iosSimulator:
                return "generic/platform=iOS Simulator"
            case .macos:
                return "generic/platform=macOS"
            case .tvos:
                return "generic/platform=tvOS"
            case .tvosSimulator:
                return "generic/platform=tvOS Simulator"
            case .watchos:
                return "generic/platform=watchOS"
            case .watchosSimulator:
                return "generic/platform=watchOS Simulator"
            }
        }

        init?(rawValue: String) {
            switch rawValue {
            case "ios":
                self = .ios
            case "iosSimulator":
                self = .iosSimulator
            case "macos":
                self = .macos
            case "tvos":
                self = .tvos
            case "tvosSimulator":
                self = .tvosSimulator
            case "watchos":
                self = .watchos
            case "watchosSimulator":
                self = .watchosSimulator
            default:
                return nil
            }
        }
    }

    static func destinationSuffix(destination: Destination) -> String {
        switch destination {
        case .ios:
            return "iphoneos"
        case .iosSimulator:
            return "iphonesimulator"
        case .macos:
            return "macos"
        case .tvos:
            return "tvos"
        case .tvosSimulator:
            return "tvossimulator"
        case .watchos:
            return "watchos"
        case .watchosSimulator:
            return "watchosSimulator"
        }
    }

    // copy the .swiftmodule from the derived data data to the .xcarchive
    static func archive(package: String, scheme: String, destination: Destination, derivedDataPath: String) -> [Command] {
        let suffix = Command.destinationSuffix(destination:destination)
        let path = xcodebuildPath()
        let mkdir = "mkdir"
        let cp = "cp"

        return [Command.init(cmd: path,
                             args: ["archive", "-scheme", "\(scheme)", "-destination"] + ["\(destination)"] + "-archivePath Release-\(suffix).xcarchive -derivedDataPath \(derivedDataPath) SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES  OTHER_SWIFT_FLAGS=\"-no-verify-emitted-module-interface\"  INSTALL_PATH=usr/local/lib".split(separator: " ").map({ String($0) }) ),
                             Command.init(cmd: mkdir,
                                          args: "-p \(package)/Release-\(suffix).xcarchive/Products/usr/local/lib/\(scheme).framework/Modules/".split(separator: " ").map({ String($0) }) ),
                // swiftmodule does not exist on non Swift SwiftPM packages (e.g. Objective-C or C)
                             Command.init(cmd: cp,
                                          args: "-r \(derivedDataPath)/Build/Intermediates.noindex/ArchiveIntermediates/\(scheme)/BuildProductsPath/Release-\(suffix)/\(scheme).swiftmodule Release-\(suffix).xcarchive/Products/usr/local/lib/\(scheme).framework/Modules/\(scheme).swiftmodule".split(separator: " ").map({ String($0) }) ,
                                          allowToFail: true),
                             Command.init(cmd: cp,
                                          args: "-r \(derivedDataPath)/Build/Intermediates.noindex/ArchiveIntermediates/\(scheme)/IntermediateBuildFilesPath/\(scheme).build/Release-\(suffix)/\(scheme).build/\(scheme).modulemap Release-\(suffix).xcarchive/Products/usr/local/lib/\(scheme).framework/Modules/".split(separator: " ").map({ String($0) }),
                                          allowToFail: true),
                             Command.init(cmd: mkdir,
                                          args: "-p Release-\(suffix).xcarchive/Products/usr/local/lib/\(scheme).framework/Headers/".split(separator: " ").map({ String($0) }) ),
                             Command.init(cmd: cp,
                                          args: "-r \(derivedDataPath)/Build/Intermediates.noindex/ArchiveIntermediates/\(scheme)/IntermediateBuildFilesPath/GeneratedModuleMaps-\(suffix)/\(scheme)-Swift.h Release-\(suffix).xcarchive/Products/usr/local/lib/\(scheme).framework/Headers".split(separator: " ").map({ String($0) }),
                                          allowToFail: true),
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

extension SourceCodeFragment {
    init(from productDescription: ProductDescription) {
        var params: [SourceCodeFragment] = []
        params.append(SourceCodeFragment(key: "name", string: productDescription.name))
        if !productDescription.targets.isEmpty && !productDescription.type.isLibrary {
            params.append(SourceCodeFragment(key: "targets", strings: productDescription.targets))
        }
        switch productDescription.type {
        case .library(let type):
            if type != .automatic {
                params.append(SourceCodeFragment(key: "type", enum: type.rawValue))
            }
            if !productDescription.targets.isEmpty {
                params.append(SourceCodeFragment(key: "targets", strings: productDescription.targets))
            }
            self.init(enum: "library", subnodes: params, multiline: true)
        case .executable:
            self.init(enum: "executable", subnodes: params, multiline: true)
        case .snippet:
            self.init(enum: "sample", subnodes: params, multiline: true)
        case .plugin:
            self.init(enum: "plugin", subnodes: params, multiline: true)
        case .test:
            self.init(enum: "test", subnodes: params, multiline: true)
        case .macro:
            self.init(enum: "macro", subnodes: params, multiline: true)
        }
    }
}
