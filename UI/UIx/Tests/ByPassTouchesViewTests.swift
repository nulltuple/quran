//
//  ByPassTouchesViewTests.swift
//
//
//  Created by Claude Code on 2026-11-26.
//

import UIKit
import XCTest
@testable import UIx

@MainActor
final class ByPassTouchesViewTests: XCTestCase {
    func test_onlyTheCatchViewTakesTouches() {
        let view = ByPassTouchesView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let pointer = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        view.addSubview(pointer)
        view.catchTouchesView = pointer

        XCTAssertTrue(view.point(inside: CGPoint(x: 10, y: 10), with: nil))
        XCTAssertFalse(view.point(inside: CGPoint(x: 200, y: 200), with: nil))
    }

    func test_aSecondaryCatchViewTakesTouchesOnlyWhileItIsASubview() {
        let view = ByPassTouchesView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let popover = UIView(frame: CGRect(x: 150, y: 150, width: 100, height: 40))
        view.secondaryCatchTouchesView = popover
        XCTAssertFalse(view.point(inside: CGPoint(x: 200, y: 170), with: nil), "Not shown yet")

        view.addSubview(popover)
        XCTAssertTrue(view.point(inside: CGPoint(x: 200, y: 170), with: nil))
        XCTAssertFalse(view.point(inside: CGPoint(x: 100, y: 100), with: nil))

        popover.removeFromSuperview()
        XCTAssertFalse(view.point(inside: CGPoint(x: 200, y: 170), with: nil), "Hidden again")
    }
}
