//
//  ReadingExercises.swift
//  ArabicLearning (Arabican app)
//

import ArabicScript
import LearningModel

/// The vowel of a syllable exercise (`vowel.listen.<vowel>`, `vowel.read.<vowel>`).
enum SyllableVowel: String, CaseIterable {
    case fatha
    case kasra
    case damma
    case sukun

    // MARK: Internal

    /// The mark as the canonical text writes it (the Uthmani sukun, U+06E1).
    var mark: ArabicMark {
        switch self {
        case .fatha: .fatha
        case .kasra: .kasra
        case .damma: .damma
        case .sukun: .quranicSukun
        }
    }

    var clipKind: AudioClip.Kind {
        switch self {
        case .fatha: .fatha
        case .kasra: .kasra
        case .damma: .damma
        case .sukun: .sukun
        }
    }

    /// The vowels offered with this one: the three short vowels, plus sukun when it is the answer.
    var choices: [SyllableVowel] {
        self == .sukun ? SyllableVowel.allCases : [.fatha, .kasra, .damma]
    }

    static func of(_ mark: ArabicMark) -> SyllableVowel? {
        allCases.first { $0.mark == mark }
    }
}

/// Which Quran words a decoding exercise (`decode.words.<stage>`) may use: only words whose every
/// grapheme needs features taught by then, and that practice what the stage adds.
enum ReadingStage: String {
    /// U4: short vowels only.
    case short
    /// U5: short and long vowels, with at least one long vowel.
    case long
    /// U6: every feature, with at least one sukun, shaddah, tanwin or silent letter.
    case marks
    /// U7: every feature, words of four graphemes or more.
    case full

    // MARK: Internal

    static let markFeatures: Set<ReadingFeature> = [.sukun, .shadda, .tanwin, .tanwinAlif, .hamzatWasl, .sunLam, .silentLetter, .hamzaSeat, .taMarbuta]

    /// Features a word may need at this stage.
    var allowed: Set<ReadingFeature> {
        switch self {
        case .short: [.shortVowel]
        case .long: [.shortVowel, .longVowel]
        case .marks, .full: Set(ReadingFeature.allCases)
        }
    }

    func admits(_ word: ReadableWord) -> Bool {
        let features = word.allFeatures
        guard features.isSubset(of: allowed), word.graphemes.count >= 2 else {
            return false
        }
        switch self {
        case .short: return true
        case .long: return features.contains(.longVowel)
        case .marks: return !features.isDisjoint(with: Self.markFeatures)
        case .full: return word.graphemes.count >= 4
        }
    }

    /// The stage at which `feature` is taught, so a mark-spotting word shows nothing newer.
    static func teaching(_ feature: ReadingFeature) -> ReadingStage {
        switch feature {
        case .shortVowel: .short
        case .longVowel: .long
        default: .marks
        }
    }
}

extension ExerciseGenerator {
    /// Hear a letter with `vowel`, pick the written syllable among the same letter's vowels.
    func listenForSyllable(_ skill: SkillID, _ vowel: SyllableVowel, _ random: inout SeededRandom) -> Exercise? {
        let candidates = letters.filter { clip($0.letter, vowel.clipKind) != nil }
        guard let target = candidates.randomElement(using: &random), let audio = clip(target.letter, vowel.clipKind) else {
            return nil
        }
        let options = vowel.choices.map { syllable(target.letter, $0) }
        return choice(skill, .listenForSyllable, options, syllable(target.letter, vowel), &random, audio: audio)
    }

    /// See a syllable, pick its recording among the same letter's vowels.
    func readSyllable(_ skill: SkillID, _ vowel: SyllableVowel, _ random: inout SeededRandom) -> Exercise? {
        let candidates = letters.filter { info in vowel.choices.allSatisfy { clip(info.letter, $0.clipKind) != nil } }
        guard let target = candidates.randomElement(using: &random) else {
            return nil
        }
        return audioChoice(skill, .readSyllable(syllable(target.letter, vowel)), letter: target.letter, vowel: vowel, &random)
    }

    /// A word of `pool` in which exactly one grapheme has `feature`; options are that grapheme and
    /// others of the word without it, each text distinct. `.silentLetter` asks for any letter
    /// written but not read (`ReadableWord.isSilent(at:)`), so a word with two is never used.
    func markInWord(_ skill: SkillID, _ feature: ReadingFeature, pool: WordLetters.Pool, _ random: inout SeededRandom) -> Exercise? {
        let stage = ReadingStage.teaching(feature)
        let candidates = readable.filter { word, reading in
            guard word.pool == pool, reading.allFeatures.isSubset(of: stage.allowed), reading.graphemes.count >= 3 else {
                return false
            }
            let marked = reading.features.indices.filter { has(feature, reading, $0) }
            guard marked.count == 1 else { return false }
            let answer = reading.graphemes[marked[0]].text
            return reading.graphemes.filter { $0.text == answer }.count == 1
        }
        guard let (word, reading) = candidates.randomElement(using: &random),
              let index = reading.features.indices.first(where: { has(feature, reading, $0) })
        else {
            return nil
        }
        let answer = reading.graphemes[index].text
        var others: [String] = []
        for (index, grapheme) in reading.graphemes.enumerated() where !has(feature, reading, index) {
            if grapheme.text != answer, !others.contains(grapheme.text) {
                others.append(grapheme.text)
            }
        }
        let options = [answer] + others.shuffled(using: &random).prefix(optionCount - 1)
        guard options.count >= 2 else {
            return nil
        }
        return choice(skill, .markInWord(word.word, feature), options, answer, &random)
    }

    /// Sound out the start of a Quran word: hear its first syllable and pick the word, or see the
    /// word and pick the recording of its first syllable.
    func decodeWord(_ skill: SkillID, _ stage: ReadingStage, pool: WordLetters.Pool, _ random: inout SeededRandom) -> Exercise? {
        let candidates = readable.filter { $0.word.pool == pool && stage.admits($0.reading) }
        let hearFirst = Bool.random(using: &random)
        let attempts: [(inout SeededRandom) -> Exercise?] = [
            { wordStartingWithSound(skill, candidates, &$0) },
            { firstSoundOfWord(skill, candidates, &$0) },
        ]
        for attempt in hearFirst ? attempts : attempts.reversed() {
            if let exercise = attempt(&random) {
                return exercise
            }
        }
        return nil
    }

    // MARK: Private

    private typealias Candidate = (word: WordLetters, reading: ReadableWord)

    private func has(_ feature: ReadingFeature, _ reading: ReadableWord, _ index: Int) -> Bool {
        feature == .silentLetter ? reading.isSilent(at: index) : reading.features[index].contains(feature)
    }

    private func syllable(_ letter: ArabicLetter, _ vowel: SyllableVowel) -> String {
        letter.rawValue + String(vowel.mark.scalar)
    }

    private func audioChoice(
        _ skill: SkillID,
        _ prompt: ExercisePrompt,
        letter: ArabicLetter,
        vowel: SyllableVowel,
        _ random: inout SeededRandom
    ) -> Exercise? {
        let clips = vowel.choices.compactMap { clip(letter, $0.clipKind) }
        guard clips.count == vowel.choices.count, let answer = clip(letter, vowel.clipKind) else {
            return nil
        }
        let shuffled = clips.shuffled(using: &random)
        return Exercise(skills: [skill], prompt: prompt, kind: .audioChoice(options: shuffled, answer: shuffled.firstIndex(of: answer)!))
    }

    /// Plays the target's first syllable; distractors start with a different syllable, the same
    /// letter with another vowel first.
    private func wordStartingWithSound(_ skill: SkillID, _ candidates: [Candidate], _ random: inout SeededRandom) -> Exercise? {
        let playable = candidates.filter { candidate in
            candidate.reading.onset.flatMap { onset in SyllableVowel.of(onset.vowel).flatMap { clip(onset.letter, $0.clipKind) } } != nil
        }
        guard let target = playable.randomElement(using: &random), let onset = target.reading.onset,
              let vowel = SyllableVowel.of(onset.vowel), let audio = clip(onset.letter, vowel.clipKind)
        else {
            return nil
        }
        let answer = target.word.word.text.text
        var seen: Set<String> = [answer]
        var sameLetter: [String] = []
        var others: [String] = []
        for candidate in candidates.shuffled(using: &random) {
            guard let other = candidate.reading.onset, other.letter != onset.letter || other.vowel != onset.vowel else { continue }
            let text = candidate.word.word.text.text
            guard seen.insert(text).inserted else { continue }
            if other.letter == onset.letter { sameLetter.append(text) } else { others.append(text) }
        }
        let options = [answer] + (sameLetter + others).prefix(optionCount - 1)
        guard options.count >= 2 else {
            return nil
        }
        return choice(skill, .wordStartingWithSound, options, answer, &random, audio: audio)
    }

    private func firstSoundOfWord(_ skill: SkillID, _ candidates: [Candidate], _ random: inout SeededRandom) -> Exercise? {
        let readable = candidates.filter { candidate in
            guard let onset = candidate.reading.onset, let vowel = SyllableVowel.of(onset.vowel) else { return false }
            return vowel.choices.allSatisfy { clip(onset.letter, $0.clipKind) != nil }
        }
        guard let target = readable.randomElement(using: &random), let onset = target.reading.onset,
              let vowel = SyllableVowel.of(onset.vowel)
        else {
            return nil
        }
        return audioChoice(skill, .firstSoundOfWord(target.word.word), letter: onset.letter, vowel: vowel, &random)
    }
}
