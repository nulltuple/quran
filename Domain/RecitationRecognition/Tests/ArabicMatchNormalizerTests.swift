//
//  ArabicMatchNormalizerTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import XCTest
@testable import RecitationRecognition

final class ArabicMatchNormalizerTests: XCTestCase {
    func testStripsMarksAndFoldsLetterVariants() {
        XCTAssertEqual(ArabicMatchNormalizer.normalize("قُلْ هُوَ ٱللَّهُ أَحَدٌ"), "قل هو الله احد")
        XCTAssertEqual(ArabicMatchNormalizer.normalize("إِنَّ آيَةً عَلَىٰ"), "ان ايه علي")
    }

    func testStripsQuranicAnnotationsTatweelBOMAndPunctuation() {
        // Superscript alef (U+0670), small high marks (U+06D6–06ED), tatweel and a BOM.
        XCTAssertEqual(ArabicMatchNormalizer.normalize("\u{FEFF}ٱلرَّحْمَٰنِ ۚ رَزَقۡنَـٰهُمۡ، النجوم."), "الرحمن رزقنهم النجوم")
    }

    func testCollapsesWhitespaceAndDropsLatinAndDigits() {
        XCTAssertEqual(ArabicMatchNormalizer.normalize("  الحمد \n لله  12 abc "), "الحمد لله")
        XCTAssertEqual(ArabicMatchNormalizer.normalize(""), "")
    }

    func testLettersDropSpaces() {
        XCTAssertEqual(ArabicMatchNormalizer.letters("قل هو"), Array("قلهو".utf16))
    }
}
