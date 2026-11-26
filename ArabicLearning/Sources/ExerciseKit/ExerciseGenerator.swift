//
//  ExerciseGenerator.swift
//  ArabicLearning (Arabican app)
//

import ArabicScript
import LearningModel

/// Builds exercises for skills from the compiled letters. The same seed always gives the same
/// exercise, so tests can pin fixtures and a session can be replayed.
public struct ExerciseGenerator: Sendable {
    // MARK: Lifecycle

    public init(letters: [LetterInfo], skillTitles: [SkillID: String] = [:], optionCount: Int = 4) {
        self.letters = letters
        self.skillTitles = skillTitles
        self.optionCount = optionCount
        byChar = Dictionary(uniqueKeysWithValues: letters.map { ($0.letter.rawValue, $0) })
    }

    // MARK: Public

    /// An exercise for `skill`, or nil when the skill has no generator yet.
    public func exercise(for skill: SkillID, seed: UInt64) -> Exercise? {
        var random = SeededRandom(seed: seed ^ Self.stableHash(skill.rawValue))
        let parts = skill.rawValue.split(separator: ".").map(String.init)
        switch (parts.first, parts.count > 1 ? parts[1] : nil) {
        case ("orientation", _):
            return Exercise(skills: [skill], prompt: .explanation(skillTitles[skill] ?? skill.rawValue), kind: .explanation)
        case ("letter", "recognize"):
            guard let target = info(parts, 2) else { return nil }
            let options = distractors(for: target, random: &random)
            return choice(skill, .findLetterNamed(target.name), options.map(\.letter.rawValue), target.letter.rawValue, &random)
        case ("letter", "sound"):
            guard let target = info(parts, 2) else { return nil }
            let options = distractors(for: target, random: &random)
            return choice(skill, .soundOfLetter(target.letter), options.map(\.sound), target.sound, &random)
        case ("letter", "form"):
            guard let target = info(parts, 2), parts.count == 4, let form = LetterForm(rawValue: parts[3]) else { return nil }
            let options = distractors(for: target, random: &random)
            return choice(skill, .letterInForm(target.letter, form), options.map(\.letter.rawValue), target.letter.rawValue, &random)
        case ("sound", "discriminate"):
            guard parts.count == 3 else { return nil }
            let group = parts[2].split(separator: "-").compactMap { byChar[String($0)] }
            guard group.count >= 2, let target = group.randomElement(using: &random) else { return nil }
            return choice(skill, .letterForSound(target.sound), group.map(\.letter.rawValue), target.letter.rawValue, &random)
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

    // MARK: Internal

    /// FNV-1a, stable across launches (Swift's `hashValue` is not).
    static func stableHash(_ string: String) -> UInt64 {
        string.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
    }

    // MARK: Private

    private let letters: [LetterInfo]
    private let skillTitles: [SkillID: String]
    private let optionCount: Int
    private let byChar: [String: LetterInfo]

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

    private func choice(
        _ skill: SkillID,
        _ prompt: ExercisePrompt,
        _ options: [String],
        _ answer: String,
        _ random: inout SeededRandom
    ) -> Exercise {
        let shuffled = options.shuffled(using: &random)
        return Exercise(skills: [skill], prompt: prompt, kind: .choice(options: shuffled, answer: shuffled.firstIndex(of: answer)!))
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
