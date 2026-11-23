import Foundation
import ZIPFoundation

struct IPAEngine {
    func inspect(ipaURL: URL, workspace: URL) throws -> IPAReport {
        let fm = FileManager.default
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        let extracted = workspace.appendingPathComponent("inspection-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: extracted) }

        do {
            try fm.unzipItem(at: ipaURL, to: extracted)
        } catch {
            throw EngineError.invalidIPA
        }

        let payload = extracted.appendingPathComponent("Payload", isDirectory: true)
        let apps = (try? fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: [.isDirectoryKey]))?
            .filter { $0.pathExtension == "app" } ?? []
        guard let app = apps.first else { throw EngineError.missingAppBundle }

        let plistURL = app.appendingPathComponent("Info.plist")
        guard fm.fileExists(atPath: plistURL.path) else { throw EngineError.missingInfoPlist }
        guard let plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
            throw EngineError.invalidPlist
        }

        let executableName = plist["CFBundleExecutable"] as? String
        var architectures: [String] = []
        if let executableName {
            let executableURL = app.appendingPathComponent(executableName)
            if let data = try? Data(contentsOf: executableURL) {
                architectures = MachOInspector.architectures(in: data)
            }
        }

        let frameworksURL = app.appendingPathComponent("Frameworks", isDirectory: true)
        let frameworks = (try? fm.contentsOfDirectory(at: frameworksURL, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "framework" }
            .map(\.lastPathComponent) ?? []

        var warnings: [String] = []
        if architectures.isEmpty { warnings.append("Executable architecture could not be identified.") }
        warnings.append("Inspection does not verify Apple code-signing validity or installation eligibility.")

        return IPAReport(
            fileName: ipaURL.lastPathComponent,
            bundleIdentifier: plist["CFBundleIdentifier"] as? String,
            version: (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String),
            executable: executableName,
            architectures: architectures,
            frameworks: frameworks,
            appPath: "Payload/\(app.lastPathComponent)",
            inspectedAt: Date(),
            warnings: warnings
        )
    }

    func package(ipaURL: URL, outputURL: URL, replacementImage: Data?, replacementRelativePath: String?) throws {
        let fm = FileManager.default
        let parent = fm.temporaryDirectory.appendingPathComponent("IPAModEngine-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: parent) }

        try fm.unzipItem(at: ipaURL, to: parent)

        if let replacementImage, let relative = replacementRelativePath, !relative.isEmpty {
            guard !relative.hasPrefix("/"),
                  !relative.split(separator: "/").contains(".."),
                  relative.hasPrefix("Payload/"),
                  relative.contains(".app/") else { throw EngineError.unsafePath }

            let destination = parent.appendingPathComponent(relative)
            guard destination.standardizedFileURL.path.hasPrefix(parent.standardizedFileURL.path + "/") else {
                throw EngineError.unsafePath
            }
            guard fm.fileExists(atPath: destination.path) else {
                throw EngineError.unsupportedOperation("The resource path does not exist in the extracted app. No file was replaced.")
            }
            try replacementImage.write(to: destination, options: .atomic)
        }

        if fm.fileExists(atPath: outputURL.path) { try fm.removeItem(at: outputURL) }
        try fm.zipItem(at: parent, to: outputURL, shouldKeepParent: false)

        guard fm.fileExists(atPath: outputURL.path),
              let archive = Archive(url: outputURL, accessMode: .read),
              archive["Payload"] != nil else {
            throw EngineError.unsupportedOperation("The output archive failed structural validation.")
        }
    }
}

enum MachOInspector {
    static func architectures(in data: Data) -> [String] {
        guard data.count >= 4 else { return [] }
        let bytes = [UInt8](data.prefix(8))
        let magic = Array(bytes.prefix(4))
        let names: [UInt32: String] = [
            0x0100000C: "arm64",
            0x0200000C: "arm64_32",
            0x01000007: "x86_64",
            0x00000007: "i386",
            0x0000000C: "arm"
        ]

        func u32(_ b: [UInt8]) -> UInt32 {
            UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 24)
        }
        func be32(_ b: [UInt8]) -> UInt32 {
            (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
        }

        // FAT_MAGIC / FAT_MAGIC_64, including byte-swapped variants.
        if magic == [0xCA, 0xFE, 0xBA, 0xBE] || magic == [0xBE, 0xBA, 0xFE, 0xCA] {
            let count = Int(be32(Array(bytes[4...7])))
            guard count > 0, count < 64, data.count >= 8 + count * 20 else { return [] }
            var result: [String] = []
            for index in 0..<count {
                let start = 8 + index * 20
                let cputype = be32(Array(data[start..<(start + 4)]))
                if let name = names[cputype], !result.contains(name) { result.append(name) }
            }
            return result
        }

        let littleMagic = u32(magic)
        let bigMagic = be32(magic)
        let cpu: UInt32
        if littleMagic == 0xFEEDFACF || littleMagic == 0xFEEDFACE {
            guard data.count >= 8 else { return [] }
            cpu = u32(Array(data[4...7]))
        } else if bigMagic == 0xFEEDFACF || bigMagic == 0xFEEDFACE {
            guard data.count >= 8 else { return [] }
            cpu = be32(Array(data[4...7]))
        } else {
            return []
        }
        return names[cpu].map { [$0] } ?? []
    }
}
