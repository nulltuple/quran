//
//  QuranAppReadingRemoteResourcesTests.swift
//

import BatchDownloaderFake
import QuranKit
import SystemDependenciesFake
import XCTest
@testable import ReadingService

final class QuranAppReadingRemoteResourcesTests: XCTestCase {
    func test_resource_pointsEachDownloadableReadingAtItsVerifiedPack() {
        let expected: [Reading: (url: String, version: Int)] = [
            .hafs_1421: ("https://files.quran.app/hafs/madani_1421/zips/images_1120.zip", 2),
            .hafs_1440: ("https://files.quran.app/hafs/madani_1440/zips/images_1352.zip", 4),
            .hafs_1439: ("https://files.quran.app/hafs/madani_1439/zips/images_1080.zip", 1),
            .hafs_1441: ("https://files.quran.app/hafs/madani_1441/zips/images_1440.zip", 1),
            .tajweed: ("https://files.quran.app/hafs/tajweed/zips/images_1280.zip", 7),
        ]

        for (reading, pack) in expected {
            let resource = sut.resource(for: reading)
            XCTAssertEqual(resource?.url.absoluteString, pack.url, "\(reading)")
            XCTAssertEqual(resource?.version, pack.version, "\(reading)")
            XCTAssertNil(resource?.ayahMarkerURL, "\(reading) reads markers from its ayahinfo database")
        }
    }

    func test_resource_isNilForTheBundledReadingAndIndoPak() {
        XCTAssertNil(sut.resource(for: .hafs_1405), "Bundled with the app")
        XCTAssertNil(sut.resource(for: .indoPak), "No verified public pack")
    }

    /// The service unzips `images_<width>.zip` into a folder named after the zip, which must be the
    /// folder the reader looks in, for page images and line pages alike.
    func test_zipName_unpacksWhereTheReaderLooks() {
        for reading in Reading.allReadings {
            guard let resource = sut.resource(for: reading) else {
                continue
            }
            let unzipFolder = resource.url.deletingPathExtension().lastPathComponent
            let readerFolder = reading.imagesDirectory(in: URL(fileURLWithPath: "/r"))
                .deletingLastPathComponent().lastPathComponent
            XCTAssertEqual(unzipFolder, readerFolder, "\(reading)")
            if let metrics = reading.linePageMetrics {
                XCTAssertEqual(unzipFolder, "images_\(metrics.widthParameter)", "\(reading) line pages")
            }
            XCTAssertEqual(resource.downloadDestination.url.lastPathComponent, reading.localPath)
        }
    }

    func test_availableReadings_offerEveryReadingButIndoPakWithTheBundledOne() async {
        let testContext = BatchDownloaderFake.makeContext()
        let (downloader, _) = await testContext.makeDownloader(fileManager: FileSystemFake())
        let service = ReadingResourcesService(
            fileManager: FileSystemFake(),
            downloader: downloader,
            remoteResources: sut,
            bundledReadings: [.hafs_1405]
        )

        XCTAssertEqual(service.availableReadings(), Set(Reading.allReadings).subtracting([.indoPak]))
    }

    // MARK: Private

    private let sut = QuranAppReadingRemoteResources()
}
