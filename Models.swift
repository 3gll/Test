import Foundation
import SwiftUI

struct IPAReport: Codable {
    let fileName: String
    let bundleIdentifier: String?
    let version: String?
    let executable: String?
    let architectures: [String]
    let frameworks: [String]
    let appPath: String
    let inspectedAt: Date
    let warnings: [String]
}

struct BuildRecord: Identifiable, Codable {
    var id = UUID()
    let sourceName: String
    let outputName: String
    let createdAt: Date
    let details: String
}

enum EngineError: LocalizedError {
    case invalidIPA
    case missingAppBundle
    case missingInfoPlist
    case invalidPlist
    case unsafePath
    case unsupportedOperation(String)

    var errorDescription: String? {
        switch self {
        case .invalidIPA: return "The selected file is not a valid IPA archive."
        case .missingAppBundle: return "No Payload/*.app bundle was found."
        case .missingInfoPlist: return "The application Info.plist is missing."
        case .invalidPlist: return "The application Info.plist could not be read."
        case .unsafePath: return "The requested resource path is unsafe."
        case .unsupportedOperation(let reason): return reason
        }
    }
}
