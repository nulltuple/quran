//
//  ByPassTouchesView.swift
//  UIKitExtension
//
//  Created by Afifi, Mohamed on 3/14/20.
//  Copyright © 2020 Quran.com. All rights reserved.
//

import UIKit

/// Takes touches only inside its catch views' frames and passes the rest to the views behind it.
public class ByPassTouchesView: UIView {
    public var catchTouchesView: UIView?
    /// A second view that catches touches while it is a subview, such as a tappable popover.
    public weak var secondaryCatchTouchesView: UIView?

    override public func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if catchTouchesView?.frame.contains(point) ?? false {
            return true
        }
        if let secondaryCatchTouchesView, secondaryCatchTouchesView.superview === self,
           secondaryCatchTouchesView.frame.contains(point)
        {
            return true
        }
        return false
    }
}
