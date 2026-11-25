//
//  Reciter+URLs.swift
//
//
//  Created by Mohamed Afifi on 2023-06-10.
//

import Foundation
import QuranKit
import Utilities

extension Reciter {
    static let audioRemotePath = "hafs/databases/audio/"

    /// The timing database a gapless reciter downloads, unzipped; `nil` when it needs none.
    public var localDatabasePath: RelativeFilePath? {
        guard bundledTimingDatabase == nil, case .gapless(let databaseName) = audioType else {
            return nil
        }
        let baseFileName = localFolder().appendingPathComponent(databaseName, isDirectory: true)
        return baseFileName.appendingPathExtension(Files.databaseLocalFileExtension)
    }

    public var localZipPath: RelativeFilePath? {
        localDatabasePath?.deletingPathExtension()
            .appendingPathExtension(Files.databaseRemoteFileExtension)
    }

    public static var audioFiles: RelativeFilePath {
        RelativeFilePath(Files.audioFilesPathComponent, isDirectory: true)
    }

    public func localFolder() -> RelativeFilePath {
        Self.audioFiles.appendingPathComponent(directory, isDirectory: true)
    }

    // TODO: should be internal
    public func oldLocalFolder() -> RelativeFilePath {
        RelativeFilePath(directory, isDirectory: true)
    }

    /// The timing database a gapless reciter reads, bundled or downloaded.
    public var timingDatabaseURL: URL? {
        bundledTimingDatabase ?? localDatabasePath?.url
    }

    public func databaseRemoteURL(baseURL: URL) -> URL? {
        guard bundledTimingDatabase == nil, case AudioType.gapless(let databaseFileName) = audioType else {
            return nil
        }

        let audioDatabaseURL = baseURL.appendingPathComponent(Self.audioRemotePath)
        return audioDatabaseURL.appendingPathComponent(databaseFileName)
            .appendingPathExtension(Files.databaseRemoteFileExtension)
    }

    public func remoteURL(sura: Sura) -> URL {
        let fileName = sura.suraNumber.as3DigitString()
        return audioURL.appendingPathComponent(fileName)
            .appendingPathExtension(Files.audioExtension)
    }

    public func localURL(sura: Sura) -> RelativeFilePath {
        let fileName = sura.suraNumber.as3DigitString()
        return localFolder().appendingPathComponent(fileName, isDirectory: true)
            .appendingPathExtension(Files.audioExtension)
    }

    public func remoteURL(ayah: AyahNumber) -> URL {
        let fileName = ayah.sura.suraNumber.as3DigitString() + ayah.ayah.as3DigitString()
        return audioURL.appendingPathComponent(fileName)
            .appendingPathExtension(Files.audioExtension)
    }

    public func localURL(ayah: AyahNumber) -> RelativeFilePath {
        let fileName = ayah.sura.suraNumber.as3DigitString() + ayah.ayah.as3DigitString()
        return localFolder().appendingPathComponent(fileName, isDirectory: true)
            .appendingPathExtension(Files.audioExtension)
    }

    public func isReciterDirectory(_ directoryURL: URL) -> Bool {
        directory == directoryURL.lastPathComponent
    }
}

private enum Files {
    static let audioExtension = "mp3"
    static let databaseRemoteFileExtension = "zip"
    static let databaseLocalFileExtension = "db"
    static let audioFilesPathComponent = "audio_files"
}
