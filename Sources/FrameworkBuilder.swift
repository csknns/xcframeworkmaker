//
//  File.swift
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
    let originalPackagePath = FileManager.default.currentDirectoryPath
    let packagePath: String

    var scheme: String

    init(scheme: String) {
        self.scheme = scheme
        packagePath = "\(tempDir)/\(scheme)"
//        try? runAndPrint("mkdir", "\(packagePath)/")
        try? runAndPrint("cp", "-r", "\(originalPackagePath)/", "\(packagePath)")
    }

    func arun() async throws {
        print("arun")

        removeXcodeProjectAndWorkspace()
        try await addDynamicTypeToLibraryTarget()

        let scheme = scheme//"Alamofire"//"AddToWalletPM"
        let derivedDataPath = "lala"//

        // build frameworks for all platforms
        let destinations = [Command.Destination.ios, Command.Destination.iosSimulator] //
        for destination in destinations /*Command.Destination.allCases*/ {
            print("building \(scheme) for \(destination)")
            Command.archive(package: packagePath, scheme: scheme, destination: destination, derivedDataPath: derivedDataPath)
                .forEach { command in
        //            print(command)
                    try! runAndPrint(command.cmd, command.args)
                }
        }

        // combine frameworks to an xcframework
        //print("creating xcframework")
        let command = Command.createXcframework(package: packagePath, scheme: scheme, destinations: destinations, derivedDataPath: derivedDataPath)
        //print(command.args)
        print("creating \(scheme).xcframework")
        //let a = await try! safeShell(command).value
        try! runAndPrint(command.cmd, command.args)
    }

//    static func copyLibraryToTempFolder() -> String {
//        try? runAndPrint("cp", "\(packagePath)/*", "\(tempDir)/")
//
//        return tempDir
//    }

    // If in the same folder we have Package.swift and an xcode project,
    // xcodebuild tries to build the xcode project
    // with no way of pointing to SPM library
    func removeXcodeProjectAndWorkspace() {
        try? runAndPrint("rm", "\(packagePath)/*.xcodeproj", "\(tempDir)/")
        try? runAndPrint("rm", "\(packagePath)/*.xcworkspace", "\(tempDir)/")
    }

    func addDynamicTypeToLibraryTarget() async throws {
        //find the correct package.swift manifest depending on the swift version e.g. Package@swift-5.8.swift
        //modify it to add "type: .dynamic" to the library we are building
        //this is needed in order to produce the .framework
        // default are static libs
        let packageAbsPath = try AbsolutePath(validating: packagePath)
        let workspace = try Workspace(forRootPackage: packageAbsPath)
        let observability = ObservabilitySystem({ print("\($0): \($1)") })
        var manifest = try await workspace.loadRootManifest(at: packageAbsPath,
                                                            observabilityScope: observability.topScope)

        print("Found manifest \(manifest.path)")

        guard let library = manifest.products.first(where: { $0.name == scheme }) else {
            print("Could not find library in packges with name '\(scheme)'")
            return
        }

        // TODO: add .dynamic to target
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
                                   products: newProducts,
                                   targets: manifest.targets)

        let newContents = try newManifest.generateManifestFileContents(
            packageDirectory: try AbsolutePath(validating: packagePath))
        
        print("writing new manifest")
        try newContents.write(toFile: manifest.path.pathString,
                              atomically: true,
                              encoding: .utf8)
        print(newContents)

    }
}

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
                                          args: "-r \(derivedDataPath)/Build/Intermediates.noindex/ArchiveIntermediates/\(scheme)/IntermediateBuildFilesPath/GeneratedModuleMaps-\(suffix)/\(scheme)-Swift.h Release-\(suffix).xcarchive/Products/usr/local/lib/\(scheme).framework/Headers".split(separator: " ").map({ String($0) }) ),
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
