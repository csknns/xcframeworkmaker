//
//  File.swift
//  
//
//  Created by Christos koninis on 20/10/24.
//

import Foundation
import SwiftShell

final class SwiftShellLogger: WritableStream {
    var encoding: String.Encoding = .utf8
    var filehandle: FileHandle = FileHandle.nullDevice

    init(derivedDataPath: String) throws {
        var url = URL(filePath: derivedDataPath)
        url.append(component: "build")
        url.appendPathExtension("log")
        try? runAndPrint("touch", "\(derivedDataPath)/build.log")
        self.filehandle = try FileHandle(forUpdating: url)
    }

    func write(_ x: String) {
        Swift.print(x, separator: "")
        filehandle.write(x)
    }

    func close() {
        try? filehandle.close()
    }
}
