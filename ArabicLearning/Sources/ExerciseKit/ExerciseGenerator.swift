//
//  ExerciseGenerator.swift
//  ArabicLearning (Arabican app)
//

import ArabicScript
import LearningModel

/// Builds exercises for skills from the compiled letters. The same seed always gives the same
/// exercise, so tests can pin fixtures and a session can be replayed.
///
/// Practice exercises use only practice words. A unit check (`check.<unit>`) asks the exercise of
/// one of the skills it requires, built from check words the learner never practices and without
/// transliterated text, and scores the check skill.
public struct ExerciseGenerator: Sendable {
    // MARK: Lifecycle

    public init(
        letters: [LetterInfo],
        skillTitles: [SkillID: String] = [:],
        clips: [AudioClip] = [],
        strokes: [ArabicLetter: [LetterForm: [GuideStroke]]] = [:],
        words: [WordLetters] = [],
        checks: [SkillID: [SkillID]] = [:],
        bridges: [BridgeSura] = [],
        lemmas: [Lemma] = [],
        optionCount: Int = 4
    ) {
        self.letters = letters
        self.skillTitles = skillTitles
        self.strokes = strokes
        // A check word whose text a practice word also writes is not unseen; drop it.
        let practiced = Set(words.filter { $0.pool == .practice }.map(\.word.text))
        let words = words.filter { $0.pool == .practice || !practiced.contains($0.word.text) }
        self.words = words
        self.checks = checks
        self.optionCount = optionCount
        bridgesBySura = Dictionary(bridges.map { ($0.sura, $0) }) { first, _ in first }
        self.lemmas = lemmas.filter { !$0.english.isEmpty }
        lemmaIndex = Dictionary(self.lemmas.enumerated().map { ($1.text, $0) }) { first, _ in first }
        readable = words.compactMap { word in ReadableWord(word.word.text.text).map { (word, $0) } }
        byChar = Dictionary(uniqueKeysWithValues: letters.map { ($0.letter.rawValue, $0) })
        clipsByKey = Dictionary(clips.map { (ClipKey(letter: $0.letter, kind: $0.kind), $0) }) { first, _ in first }
    }

    // MARK: Public

    /// An exercise for `skill`, or nil when the skill has no generator yet.
    public func exercise(for skill: SkillID, seed: UInt64) -> Exercise? {
        build(skill, seed: seed, pool: .practice)
    }

    // MARK: Internal

    let letters: [LetterInfo]
    let optionCount: Int
    let bridgesBySura: [Int: BridgeSura]
    /// Glossed lemmas, most frequent first.
    let lemmas: [Lemma]
    let lemmaIndex: [String: Int]
    /// Words ReadableWord accepts, with their analysis.
    let readable: [(word: WordLetters, reading: ReadableWord)]

    /// FNV-1a, stable across launches (Swift's `hashValue` is not).
    static func stableHash(_ string: String) -> UInt64 {
        string.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
    }

    func clip(_ letter: ArabicLetter, _ kind: AudioClip.Kind) -> AudioClip? {
        clipsByKey[ClipKey(letter: letter, kind: kind)]
    }

    func choice(
        _ skill: SkillID,
        _ prompt: ExercisePrompt,
        _ options: [String],
        _ answer: String,
        _ random: inout SeededRandom,
        audio: AudioClip? = nil,
        recitation: RecitationSegment? = nil
    ) -> Exercise {
        let shuffled = options.shuffled(using: &random)
        return Exercise(
            skills: [skill],
            prompt: prompt,
            kind: .choice(options: shuffled, answer: shuffled.firstIndex(of: answer)!),
            audio: audio,
            recitation: recitation
        )
    }

    // MARK: Private

    private struct ClipKey: Hashable {
        let letter: ArabicLetter
        let kind: AudioClip.Kind
    }

    private let skillTitles: [SkillID: String]
    private let strokes: [ArabicLetter: [LetterForm: [GuideStroke]]]
    private let words: [WordLetters]
    private let checks: [SkillID: [SkillID]]
    private let byChar: [String: LetterInfo]
    private let clipsByKey: [ClipKey: AudioClip]

    private func build(_ skill: SkillID, seed: UInt64, pool: WordLetters.Pool) -> Exercise? {
        var random = SeededRandom(seed: seed ^ Self.stableHash(skill.rawValue))
        let parts = skill.rawValue.split(separator: ".").map(String.init)
        let checking = pool == .check
        switch (parts.first, parts.count > 1 ? parts[1] : nil) {
        case ("check", _):
            guard !checking, let required = checks[skill] else { return nil }
            for (index, part) in required.shuffled(using: &random).enumerated() {
                if let exercise = build(part, seed: seed &+ UInt64(index), pool: .check) {
                    return exercise.scoring([skill])
                }
            }
            return nil
        case ("orientation", _):
            guard !checking else { return nil }
            return Exercise(skills: [skill], prompt: .explanation(skillTitles[skill] ?? skill.rawValue), kind: .explanation)
        case ("letter", "recognize"):
            guard let target = info(parts, 2) else { return nil }
            let options = distractors(for: target, random: &random)
            // A check never shows the transliterated name: it plays the name instead.
            if checking {
                guard let audio = clip(target.letter, .name) else { return nil }
                return choice(skill, .listenForLetter, options.map(\.letter.rawValue), target.letter.rawValue, &random, audio: audio)
            }
            return choice(
                skill, .findLetterNamed(target.name), options.map(\.letter.rawValue), target.letter.rawValue, &random,
                audio: clip(target.letter, .name)
            )
        case ("letter", "sound"):
            guard let target = info(parts, 2) else { return nil }
            let options = distractors(for: target, random: &random)
            // Hear the letter with fatha and pick it; alif, which writes no consonant, keeps the text prompt.
            if let audio = clip(target.letter, .fatha) {
                return choice(skill, .listenForLetter, options.map(\.letter.rawValue), target.letter.rawValue, &random, audio: audio)
            }
            guard !checking else { return nil }
            return choice(skill, .soundOfLetter(target.letter), options.map(\.sound), target.sound, &random)
        case ("letter", "form"):
            guard let target = info(parts, 2), parts.count == 4, let form = LetterForm(rawValue: parts[3]) else { return nil }
            let options = distractors(for: target, random: &random)
            return choice(skill, .letterInForm(target.letter, form), options.map(\.letter.rawValue), target.letter.rawValue, &random)
        case ("sound", "discriminate"):
            guard parts.count == 3 else { return nil }
            let group = parts[2].split(separator: "-").compactMap { byChar[String($0)] }
            guard group.count >= 2, let target = group.randomElement(using: &random) else { return nil }
            if let audio = clip(target.letter, .fatha) {
                return choice(skill, .listenForLetter, group.map(\.letter.rawValue), target.letter.rawValue, &random, audio: audio)
            }
            guard !checking else { return nil }
            return choice(skill, .letterForSound(target.sound), group.map(\.letter.rawValue), target.letter.rawValue, &random)
        case ("letter", "inword"):
            guard let target = info(parts, 2) else { return nil }
            return letterInWord(skill, target, pool: pool, &random)
        case ("letter", "write"):
            guard !checking, let target = info(parts, 2), let guide = strokes[target.letter]?[.isolated], !guide.isEmpty else { return nil }
            return Exercise(skills: [skill], prompt: .traceLetter(target.letter), kind: .trace(guide: guide), audio: clip(target.letter, .name))
        case ("vowel", "listen"):
            guard parts.count == 3, let vowel = SyllableVowel(rawValue: parts[2]) else { return nil }
            return listenForSyllable(skill, vowel, &random)
        case ("vowel", "read"):
            guard parts.count == 3, let vowel = SyllableVowel(rawValue: parts[2]) else { return nil }
            return readSyllable(skill, vowel, &random)
        case ("mark", "spot"):
            guard parts.count == 3, let feature = ReadingFeature(rawValue: parts[2]) else { return nil }
            return markInWord(skill, feature, pool: pool, &random)
        case ("decode", "words"):
            guard parts.count == 3, let stage = ReadingStage(rawValue: parts[2]) else { return nil }
            return decodeWord(skill, stage, pool: pool, &random)
        case ("bridge", "listen"):
            guard !checking, parts.count == 3, let sura = Int(parts[2]).flatMap({ bridgesBySura[$0] }) else { return nil }
            return listenForWord(skill, sura, &random)
        case ("bridge", "meaning"):
            guard !checking, parts.count == 3, let sura = Int(parts[2]).flatMap({ bridgesBySura[$0] }) else { return nil }
            return meaningInAyah(skill, sura, &random)
        case ("lemma", "meaning"):
            guard !checking, parts.count == 3 else { return nil }
            return meaningOfLemma(skill, parts[2], &random)
        default:
            return nil
        }
    }

    /// Match the letters of `skills` (letter.recognize.*) to their names; nil for fewer than two letters.
    public func matchExercise(for skills: [SkillID], seed: UInt64) -> Exercise? {
        let pairs = skills.compactMap { skill -> (SkillID, LetterInfo)? in
            let parts = skill.rawValue.split(separator: ".").map(String.init)
            guard parts.count == 3, parts[0] == "letter", parts[1] == "recognize", let info = byChar[parts[2]] else { return nil }
            return (skill, info)
        }
        guard pairs.count >= 2 else { return nil }
        var random = SeededRandom(seed: seed)
        let order = Array(pairs.indices).shuffled(using: &random)
        let right = order.map { pairs[$0].1.name }
        let answers = pairs.indices.map { order.firstIndex(of: $0)! }
        return Exercise(
            skills: pairs.map(\.0),
            prompt: .matchLettersToNames,
            kind: .match(left: pairs.map(\.1.letter.rawValue), right: right, answers: answers)
        )
    }

    /// A Quran word that plainly writes `target`, and distractors the word holds in no spelling:
    /// same shape family first (they look alike), then others.
    private func letterInWord(_ skill: SkillID, _ target: LetterInfo, pool: WordLetters.Pool, _ random: inout SeededRandom) -> Exercise? {
        let candidates = words.filter { $0.pool == pool && $0.exact.contains(target.letter) }
        guard let word = candidates.randomElement(using: &random) else { return nil }
        let absent = letters.filter { !word.holds($0.letter) }
        let family = absent.filter { $0.family == target.family }.shuffled(using: &random)
        let others = absent.filter { $0.family != target.family }.shuffled(using: &random)
        let options = [target] + (family + others).prefix(optionCount - 1)
        guard options.count >= 2 else { return nil }
        return choice(skill, .letterInWord(word.word), options.map(\.letter.rawValue), target.letter.rawValue, &random)
    }

    private func info(_ parts: [String], _ index: Int) -> LetterInfo? {
        parts.count > index ? byChar[parts[index]] : nil
    }

    /// The target plus distractors: same shape family first (the confusions that matter), then
    /// random others. Order is not yet shuffled.
    private func distractors(for target: LetterInfo, random: inout SeededRandom) -> [LetterInfo] {
        let family = letters.filter { $0.family == target.family && $0.letter != target.letter }.shuffled(using: &random)
        let others = letters.filter { $0.family != target.family }.shuffled(using: &random)
        return [target] + (family + others).prefix(optionCount - 1)
    }
}

/// SplitMix64: a small, fast, seedable generator. Not for security.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    private var state: UInt64
}
