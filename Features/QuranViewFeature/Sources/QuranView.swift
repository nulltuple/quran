//
//  QuranView.swift
//  Quran
//
//  Created by Mohamed Afifi on 5/12/16.
//
//  Quran for iOS is a Quran reading application for iOS.
//  Copyright (C) 2017  Quran.com
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
import NoorUI
import UIKit
import UIx
import ViewConstrainer

@MainActor
protocol QuranViewDelegate: AnyObject {
    func onQuranViewTapped(_ quranView: QuranView)
    func canTogglePlayPause(in quranView: QuranView) -> Bool
    func onQuranViewPlayPauseKeyPressed(_ quranView: QuranView)
}

class QuranView: UIView, UIGestureRecognizerDelegate, UINavigationBarDelegate {
    // MARK: Lifecycle

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("Not implemented")
    }

    init() {
        super.init(frame: .zero)
        setUp()
    }

    // MARK: Internal

    weak var delegate: QuranViewDelegate?

    var contentView: UIView?

    let navigationBar = UINavigationBar()
    let navigationItem = UINavigationItem()

    /// Presented editors aren't in this responder chain, so they keep space for typing.
    override var keyCommands: [UIKeyCommand]? {
        let commands = super.keyCommands ?? []
        guard canTogglePlayPause else {
            return commands.isEmpty ? nil : commands
        }
        return commands + [playPauseCommand]
    }

    override func layoutSubviews() {
        navigationItem.titleView?.setNeedsLayout()
        super.layoutSubviews()
        configureNavigationBarScrollEdgeEffectIfNeeded()
        configureAudioBarScrollEdgeEffectIfNeeded()
    }

    func position(for bar: UIBarPositioning) -> UIBarPosition {
        .topAttached
    }

    func addWordPointerView(_ wordPointerView: UIView) {
        addAutoLayoutSubview(wordPointerView)
        wordPointerView.vc.edges()
    }

    func addContentView(_ contentView: UIView) {
        self.contentView = contentView
        addAutoLayoutSubview(contentView)
        contentView.vc
            .verticalEdges()
            .horizontalEdges()
        sendSubviewToBack(contentView)
    }

    func addAudioBannerView(_ audioBannerView: UIView) {
        audioView = audioBannerView
        // Toasts, the banner's own included, stay above the audio bar while it shows.
        audioBannerView.keepsToastsAbove = true
        addAutoLayoutSubview(audioBannerView)
        audioBannerView.vc
            .horizontalEdges()
            .bottom()
        updateAudioBarVisibility()
    }

    /// Shows live recitation follow's controls where the audio banner sits, in its place: they stay
    /// visible when the bars hide, since the microphone is on while they show.
    func addRecitationFollowView(_ followView: UIView) {
        recitationFollowView?.removeFromSuperview()
        recitationFollowView = followView
        followView.keepsToastsAbove = true
        addAutoLayoutSubview(followView)
        followView.vc
            .horizontalEdges()
        safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: followView.bottomAnchor).isActive = true
        setAudioBarHidden(true)
    }

    func removeRecitationFollowView() {
        recitationFollowView?.removeFromSuperview()
        recitationFollowView = nil
        setAudioBarHidden(navigationBarHidden)
    }

    func setBarsHidden(_ hidden: Bool, animated: Bool = false, completion: (() -> Void)? = nil) {
        let audioHidden = hidden || recitationFollowView != nil
        let navigationBarStateChanged = navigationBarHidden != hidden
        let audioBarStateChanged = audioBarHidden != audioHidden
        navigationBarHidden = hidden
        audioBarHidden = audioHidden
        configureNavigationBarScrollEdgeEffectIfNeeded()
        configureAudioBarScrollEdgeEffectIfNeeded()

        barsVisibilityAnimationID &+= 1
        let animationID = barsVisibilityAnimationID
        let animateNavigationBar = prepareBarForVisibilityTransition(
            navigationBar,
            hidden: hidden,
            animated: animated,
            stateChanged: navigationBarStateChanged
        )
        let animateAudioBar = prepareBarForVisibilityTransition(
            audioView,
            hidden: audioHidden,
            animated: animated,
            stateChanged: audioBarStateChanged
        )
        guard animateNavigationBar || animateAudioBar else {
            completion?()
            return
        }

        NoorAnimation.animate {
            if animateNavigationBar {
                self.navigationBar.alpha = hidden ? 0 : 1
            }
            if animateAudioBar {
                self.audioView?.alpha = audioHidden ? 0 : 1
            }
        } completion: { [weak self] in
            guard let self, barsVisibilityAnimationID == animationID else { return }
            if animateNavigationBar, navigationBarHidden == hidden {
                updateNavigationBarVisibility()
            }
            if animateAudioBar, audioBarHidden == audioHidden {
                updateAudioBarVisibility()
            }
            completion?()
        }
    }

    func setAudioBarHidden(_ hidden: Bool) {
        audioBarHidden = hidden
        configureAudioBarScrollEdgeEffectIfNeeded()
        audioView?.layer.removeAllAnimations()
        updateAudioBarVisibility()
    }

    func refreshScrollEdgeInteractions() {
        configureNavigationBarScrollEdgeEffectIfNeeded()
        configureAudioBarScrollEdgeEffectIfNeeded()
    }

    @objc
    func onViewTapped(_ sender: UITapGestureRecognizer) {
        if let audioView, audioView.bounds.contains(sender.location(in: audioView)), audioView.isUserInteractionEnabled {
            return
        }
        if let recitationFollowView, recitationFollowView.bounds.contains(sender.location(in: recitationFollowView)) {
            return
        }
        delegate?.onQuranViewTapped(self)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer != tapGesture || !isFirstResponder // dismiss bars only if not first responder
    }

    // MARK: Private

    private let tapGesture = UITapGestureRecognizer()
    private var audioView: UIView?
    private var recitationFollowView: UIView?
    private var navigationBarHidden = false
    private var audioBarHidden = false
    // Prevent an interrupted animation from finalizing a newer visibility request.
    private var barsVisibilityAnimationID = 0
    private var navigationBarScrollEdgeInteraction: (any UIInteraction)?
    private var audioBarScrollEdgeInteraction: (any UIInteraction)?

    private lazy var playPauseCommand: UIKeyCommand = {
        let command = UIKeyCommand(input: " ", modifierFlags: [], action: #selector(toggleRecitation))
        // Otherwise space activates the focused verse.
        command.wantsPriorityOverSystemBehavior = true
        return command
    }()

    private var canTogglePlayPause: Bool {
        guard let delegate, delegate.canTogglePlayPause(in: self) else {
            return false
        }
        return !(findFirstResponder() is UITextInput)
    }

    @objc
    private func toggleRecitation() {
        guard canTogglePlayPause else {
            return
        }
        delegate?.onQuranViewPlayPauseKeyPressed(self)
    }

    private func configureNavigationBarScrollEdgeEffectIfNeeded() {
        guard !navigationBarHidden,
              let scrollView = contentScrollView()
        else {
            if let interaction = navigationBarScrollEdgeInteraction {
                navigationBar.removeInteraction(interaction)
                navigationBarScrollEdgeInteraction = nil
            }
            return
        }

        let interaction: UIScrollEdgeElementContainerInteraction
        if let existingInteraction = navigationBarScrollEdgeInteraction as? UIScrollEdgeElementContainerInteraction {
            interaction = existingInteraction
        } else {
            interaction = UIScrollEdgeElementContainerInteraction()
            interaction.edge = .top
            navigationBarScrollEdgeInteraction = interaction
            navigationBar.addInteraction(interaction)
        }
        interaction.scrollView = scrollView
    }

    private func configureAudioBarScrollEdgeEffectIfNeeded() {
        guard let audioView else { return }

        guard !audioBarHidden,
              let scrollView = contentScrollView()
        else {
            if let interaction = audioBarScrollEdgeInteraction {
                audioView.removeInteraction(interaction)
                audioBarScrollEdgeInteraction = nil
            }
            return
        }

        let interaction: UIScrollEdgeElementContainerInteraction
        if let existingInteraction = audioBarScrollEdgeInteraction as? UIScrollEdgeElementContainerInteraction {
            interaction = existingInteraction
        } else {
            interaction = UIScrollEdgeElementContainerInteraction()
            interaction.edge = .bottom
            audioBarScrollEdgeInteraction = interaction
            audioView.addInteraction(interaction)
        }
        interaction.scrollView = scrollView
    }

    private func contentScrollView() -> UIScrollView? {
        guard let contentViewController = contentView?.nearestViewController,
              let pageViewController = contentViewController.findViewController(ofType: UIPageViewController.self),
              let pageView = pageViewController.mostVisibleViewController?.viewIfLoaded
        else {
            return nil
        }

        return pageView.mostVisibleSubview(ofType: UIScrollView.self)
    }

    private func updateNavigationBarVisibility() {
        updateBarVisibility(navigationBar, hidden: navigationBarHidden)
    }

    private func updateAudioBarVisibility() {
        updateBarVisibility(audioView, hidden: audioBarHidden)
    }

    private func prepareBarForVisibilityTransition(
        _ view: UIView?,
        hidden: Bool,
        animated: Bool,
        stateChanged: Bool
    ) -> Bool {
        guard let view else { return false }
        guard animated, stateChanged else {
            view.layer.removeAllAnimations()
            updateBarVisibility(view, hidden: hidden)
            return false
        }

        if !hidden, view.isHidden {
            view.alpha = 0
        }
        view.isHidden = false
        view.isUserInteractionEnabled = !hidden
        return true
    }

    private func updateBarVisibility(_ view: UIView?, hidden: Bool) {
        view?.isHidden = hidden
        view?.isUserInteractionEnabled = !hidden
        view?.alpha = 1
    }

    private func setUp() {
        clipsToBounds = true
        tapGesture.addTarget(self, action: #selector(onViewTapped(_:)))
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)

        // navigation bar
        addAutoLayoutSubview(navigationBar)
        navigationBar.vc.horizontalEdges()
        safeAreaLayoutGuide.topAnchor.constraint(equalTo: navigationBar.topAnchor).isActive = true
        navigationBar.pushItem(navigationItem, animated: false)
        navigationBar.delegate = self
    }
}
