//
//  AudioFileListRetriever.swift
//  Quran
//
//  Created by Mohamed Afifi on 4/17/17.
//

import Foundation
import QuranAudio
import QuranKit
import Utilities

public struct ReciterAudioFile: Sendable, Hashable {
    public var remote: URL
    public var local: RelativeFilePath
    public var sura: Sura? = nil
}

private protocol AudioFileListRetriever {
    func get(for reciter: Reciter, from start: AyahNumber, to end: AyahNumber) -> [ReciterAudioFile]
}

private struct GaplessAudioFileListRetriever: AudioFileListRetriever {
    let baseURL: URL

    func get(for reciter: Reciter, from start: AyahNumber, to end: AyahNumber) -> [ReciterAudioFile] {
        guard case .gapless = reciter.audioType else {
            fatalError("Unsupported reciter type gapped. Only gapless reciters can be downloaded here.")
        }

        // A reciter with a bundled timing database downloads only its audio.
        let dbFiles = reciter.databaseRemoteURL(baseURL: baseURL).flatMap { remoteURL in
            reciter.localZipPath.map { ReciterAudioFile(remote: remoteURL, local: $0) }
        }.map { [$0] } ?? []

        // loop over the files
        var files = Set<ReciterAudioFile>()

        for sura in start.sura.array(to: end.sura) {
            let remoteURL = reciter.remoteURL(sura: sura)
            let localPath = reciter.localURL(sura: sura)
            files.insert(ReciterAudioFile(remote: remoteURL, local: localPath, sura: sura))
        }
        return Array(files) + dbFiles
    }
}

private struct GappedAudioFileListRetriever: AudioFileListRetriever {
    // MARK: Internal

    func get(for reciter: Reciter, from start: AyahNumber, to end: AyahNumber) -> [ReciterAudioFile] {
        guard case AudioType.gapped = reciter.audioType else {
            fatalError("Unsupported reciter type gapless. Only gapless reciters can be downloaded here.")
        }

        var files = Set<ReciterAudioFile>()

        // add besm Allah for all gapped audio
        files.insert(createRequestInfo(reciter: reciter, ayah: start.quran.firstVerse))

        for ayah in start.array(to: end) {
            files.insert(createRequestInfo(reciter: reciter, ayah: ayah))
        }
        return Array(files)
    }

    // MARK: Private

    private func createRequestInfo(reciter: Reciter, ayah: AyahNumber) -> ReciterAudioFile {
        let remoteURL = reciter.remoteURL(ayah: ayah)
        let localURL = reciter.localURL(ayah: ayah)
        return ReciterAudioFile(remote: remoteURL, local: localURL, sura: ayah.sura)
    }
}

extension Reciter {
    public func audioFiles(baseURL: URL, from: AyahNumber, to: AyahNumber) -> [ReciterAudioFile] {
        let retriever = retriever(baseURL: baseURL)
        return retriever.get(for: self, from: from, to: to)
    }

    private func retriever(baseURL: URL) -> AudioFileListRetriever {
        switch audioType {
        case .gapped: return GappedAudioFileListRetriever()
        case .gapless: return GaplessAudioFileListRetriever(baseURL: baseURL)
        }
    }
}
