//
//  PlusBinaryStore.swift
//  QuotioForkExtras — bundled cli-proxy-api-plus binary management
//

import CryptoKit
import Foundation
import QuotioApplication
import QuotioDomain

/// Manages the fork-bundled `cli-proxy-api-plus` proxy binary.
///
/// Fork parity with the pre-port behavior: the plus binary is committed to
/// the app bundle, pinned to a fixed version + SHA256, installed under
/// `…/Quotio/proxy/plus/v<version>/CLIProxyAPI` with a `current` symlink,
/// ad-hoc codesigned, and never auto-updated. The currently active version
/// is never deleted.
public final class PlusBinaryStore: Sendable {
    public static let plusLocalVersion = "6.9.28-0"
    public static let plusLocalSHA256 = "a722885ab3c0cea5535ee69a86220d35c4f95ee7656e009d872d24de2910acf0"
    public static let plusLocalBinaryName = "cli-proxy-api-plus"
    static let binaryName = "CLIProxyAPI"
    static let resourceSubdirectory = "Proxy"

    private let lock = NSLock()

    private var fileManager: FileManager { FileManager.default }

    private var proxyPlusDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("Quotio/proxy/plus", isDirectory: true)
    }

    public init() {}

    // MARK: - Paths

    /// Path of the active plus binary (through the `current` symlink).
    public func currentBinaryPath() -> String? {
        let path = expectedBinaryPath()
        var isSymlink: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isSymlink), !isSymlink.boolValue else {
            return nil
        }
        return path
    }

    /// Expected path of the active plus binary, whether or not it exists.
    public func expectedBinaryPath() -> String {
        currentSymlink().appendingPathComponent(Self.binaryName).path
    }

    private func currentSymlink() -> URL {
        proxyPlusDirectory.appendingPathComponent("current", isDirectory: true)
    }

    private func versionDirectory() -> URL {
        proxyPlusDirectory.appendingPathComponent("v\(Self.plusLocalVersion)", isDirectory: true)
    }

    // MARK: - Bundle resolution

    /// Locate the bundled binary in the app bundle (Resources/Proxy/…).
    public func resolveBundledBinaryPath() -> String? {
        let name = Self.plusLocalBinaryName
        let subdirectory = Self.resourceSubdirectory

        let candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: nil, subdirectory: subdirectory),
            Bundle.main.resourceURL?
                .appendingPathComponent(subdirectory, isDirectory: true)
                .appendingPathComponent(name, isDirectory: false),
            Bundle.main.url(forResource: name, withExtension: nil),
            Bundle.main.resourceURL?.appendingPathComponent(name, isDirectory: false),
        ]

        for candidate in candidates.compactMap({ $0 }) {
            guard fileManager.fileExists(atPath: candidate.path) else { continue }
            let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values?.isRegularFile == true, values?.isSymbolicLink != true {
                return candidate.path
            }
        }
        return nil
    }

    // MARK: - Install

    /// Verify the bundled binary's checksum and install it if needed.
    ///
    /// Skips work when the pinned version is already active. Throws when the
    /// binary is missing from the bundle or the checksum does not match the
    /// pin (fails closed: a tampered binary must never be executed).
    public func ensureInstalled() throws {
        try lock.withLock {
            if currentBinaryPath() != nil { return }

            guard let bundledPath = resolveBundledBinaryPath() else {
                throw PlusBinaryError.notBundled
            }
            try verifyChecksum(ofFileAt: bundledPath, expected: Self.plusLocalSHA256)

            let versionDir = versionDirectory()
            let binaryPath = versionDir.appendingPathComponent(Self.binaryName)

            if fileManager.fileExists(atPath: binaryPath.path) {
                // Binary exists but the symlink is missing/dangling: just re-point.
                try activate()
                return
            }

            try fileManager.createDirectory(at: versionDir, withIntermediateDirectories: true)
            do {
                try fileManager.copyItem(at: URL(fileURLWithPath: bundledPath), to: binaryPath)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryPath.path)
                signBinary(at: binaryPath.path)
                try activate()
            } catch {
                try? fileManager.removeItem(at: versionDir)
                throw PlusBinaryError.installationFailed(error.localizedDescription)
            }
        }
    }

    private func activate() throws {
        let symlink = currentSymlink()
        let versionDir = versionDirectory()
        guard fileManager.fileExists(atPath: versionDir.appendingPathComponent(Self.binaryName).path) else {
            throw PlusBinaryError.installationFailed("Version \(Self.plusLocalVersion) is not installed")
        }
        if fileManager.fileExists(atPath: symlink.path) {
            try fileManager.removeItem(at: symlink)
        }
        try fileManager.createSymbolicLink(at: symlink, withDestinationURL: versionDir)
    }

    private func verifyChecksum(ofFileAt path: String, expected: String) throws {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == expected.lowercased() else {
            throw PlusBinaryError.checksumMismatch
        }
    }

    /// Ad-hoc codesign; best effort like the fork original.
    private func signBinary(at path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-f", "-s", "-", path]
        try? process.run()
        process.waitUntilExit()
    }
}

public enum PlusBinaryError: Error, Equatable, Sendable {
    case notBundled
    case checksumMismatch
    case installationFailed(String)
}

/// `ProxyVersionRepository` view over the plus install: the fork runs the
/// fixed bundled binary, so the only installed version is the pinned one.
public final class PlusProxyVersionRepository: ProxyVersionRepository {
    private let store: PlusBinaryStore

    public init(store: PlusBinaryStore = PlusBinaryStore()) {
        self.store = store
    }

    public func snapshot() async -> ProxyVersionSnapshot {
        let currentPath = store.currentBinaryPath()
        let installed = InstalledProxyVersion(
            version: PlusBinaryStore.plusLocalVersion,
            path: currentPath ?? store.expectedBinaryPath(),
            installedAt: Date.distantPast,
            isCurrent: currentPath != nil
        )
        return ProxyVersionSnapshot(
            currentBinaryPath: currentPath,
            expectedBinaryPath: store.expectedBinaryPath(),
            currentVersion: currentPath != nil ? PlusBinaryStore.plusLocalVersion : nil,
            installedVersions: [installed]
        )
    }

    public func binaryPath(for version: String) async -> String? {
        guard version == PlusBinaryStore.plusLocalVersion else { return nil }
        return store.currentBinaryPath()
    }

    public func install(version: String, data: Data, assetName: String) async throws -> InstalledProxyVersion {
        // Fork parity: the plus binary only ever comes from the app bundle.
        throw PlusBinaryError.installationFailed("The bundled plus binary cannot be replaced")
    }

    public func activate(version: String) async throws {
        guard version == PlusBinaryStore.plusLocalVersion else {
            throw PlusBinaryError.installationFailed("Unknown plus version \(version)")
        }
        try store.ensureInstalled()
    }

    public func delete(version: String) async throws {
        // Invariant: never delete the current (and only) proxy version.
        throw PlusBinaryError.installationFailed("The active plus binary is never deleted")
    }

    public func cleanup(keeping count: Int) async {}

    public func versionsToDeleteAfterInstalling(keeping count: Int) async -> [String] { [] }
}
