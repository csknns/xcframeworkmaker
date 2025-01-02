//
//  Workspace+CustomInit.swift
//
//
//  Created by Christos koninis on 1/1/25.
//

import Foundation
import Workspace
import Basics
import PackageModel
import PackageGraph
import SourceControl
import PackageLoading

extension Workspace {
    public static func makeWorkspace(
        fileSystem: FileSystem? = .none,
        forRootPackage packagePath: AbsolutePath,
        authorizationProvider: AuthorizationProvider? = .none,
        registryAuthorizationProvider: AuthorizationProvider? = .none,
        configuration: WorkspaceConfiguration? = .none,
        cancellator: Cancellator? = .none,
        initializationWarningHandler: ((String) -> Void)? = .none,
        // optional customization used for advanced integration situations
        customToolsVersion: ToolsVersion? = .none,
        customHostToolchain: UserToolchain? = .none,
        customPackageContainerProvider: PackageContainerProvider? = .none,
        customRepositoryProvider: RepositoryProvider? = .none,
        // delegate
        delegate: Delegate? = .none
    ) throws -> Workspace {
        let fileSystem = fileSystem ?? localFileSystem
        let location = try Location(forRootPackage: packagePath, fileSystem: fileSystem)
        let hostToolchain = try customHostToolchain ?? UserToolchain(
            swiftSDK: .hostSwiftSDK(
                environment: .process()
            ),
            environment: .process(),
            fileSystem: fileSystem
        )

        let manifestLoader = ManifestLoader(
            toolchain: hostToolchain,
            cacheDir: location.sharedManifestsCacheDirectory,
            importRestrictions: configuration?.manifestImportRestrictions,
            delegate: .none)

        return try Workspace._init(
            fileSystem: fileSystem,
            environment: .process(),
            location: location,
            authorizationProvider: authorizationProvider,
            registryAuthorizationProvider: registryAuthorizationProvider,
            configuration: configuration,
            cancellator: cancellator,
            initializationWarningHandler: initializationWarningHandler,
            customToolsVersion: customToolsVersion,
            customHostToolchain: hostToolchain,
            customManifestLoader: manifestLoader,
            customPackageContainerProvider: customPackageContainerProvider,
            customRepositoryProvider: customRepositoryProvider,
            delegate: delegate
        )
    }
}
