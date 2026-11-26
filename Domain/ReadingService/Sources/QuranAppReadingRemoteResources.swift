//
//  QuranAppReadingRemoteResources.swift
//

import Foundation
import QuranKit

/// The Mushaf packs Quran.app publishes on `files.quran.app`, the host its Android app downloads
/// page images from (`quran/quran_android`, `MadaniPageProvider`, `NewMadaniPageProvider`,
/// `TajweedPageProvider`).
///
/// Each zip unpacks to `width_<width>/` (page or line images) and `databases/ayahinfo_<width>.db`,
/// so extracting `images_<width>.zip` into a folder named `images_<width>` gives the layout
/// `Reading.imagesDirectory(in:)` and `Reading.ayahInfoDatabase(in:)` expect. Verified 2026-11-26
/// by listing every zip: 604 pages each and an ayahinfo database covering all 6,236 ayahs.
///
/// Hafs 1405 is bundled with the app. IndoPak has no verified public pack, so it stays unavailable.
public struct QuranAppReadingRemoteResources: ReadingRemoteResources {
    // MARK: Lifecycle

    public init(host: URL = URL(string: "https://files.quran.app/")!) {
        self.host = host
    }

    // MARK: Public

    public func resource(for reading: Reading) -> RemoteResource? {
        guard let pack = Self.pack(for: reading) else {
            return nil
        }
        let url = host
            .appendingPathComponent(pack.directory)
            .appendingPathComponent("zips")
            .appendingPathComponent("images_\(reading.imageAssetWidth).zip")
        return RemoteResource(url: url, reading: reading, version: pack.version, ayahMarkerURL: nil)
    }

    // MARK: Private

    private struct Pack {
        let directory: String
        /// The newest `width_<width>/.v<N>` marker in the zip, or 1 when it has none, so a device
        /// that unzipped a newer upload of the same URL recovers it (`RemoteResource.isDownloaded`).
        let version: Int
    }

    private let host: URL

    private static func pack(for reading: Reading) -> Pack? {
        switch reading {
        case .hafs_1405, .indoPak:
            nil
        case .hafs_1421:
            Pack(directory: "hafs/madani_1421", version: 2)
        case .hafs_1440:
            Pack(directory: "hafs/madani_1440", version: 4)
        case .hafs_1439:
            Pack(directory: "hafs/madani_1439", version: 1)
        case .hafs_1441:
            Pack(directory: "hafs/madani_1441", version: 1)
        case .tajweed:
            Pack(directory: "hafs/tajweed", version: 7)
        }
    }
}
