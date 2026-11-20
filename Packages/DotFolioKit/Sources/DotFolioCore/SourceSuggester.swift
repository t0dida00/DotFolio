import DotFolioModels
import Foundation
import SwiftData

/// Service / Provider the user already chose for each variable name,
/// anywhere (other environments, projects, the Library). Built once per
/// import so a long .env doesn't fetch every variable per line.
public struct SourceHistory: Sendable {
    public struct Choice: Equatable, Sendable {
        public var service: String?
        public var provider: String?
    }

    private var byKey: [String: Choice] = [:]

    public init() {}

    @MainActor
    public init(context: ModelContext) {
        let variables = (try? context.fetch(FetchDescriptor<Variable>())) ?? []
        var services: [String: [String: Int]] = [:]
        var providers: [String: [String: Int]] = [:]
        for v in variables {
            if !v.serviceCategory.isEmpty { services[v.key, default: [:]][v.serviceCategory, default: 0] += 1 }
            if !v.serviceLabel.isEmpty { providers[v.key, default: [:]][v.serviceLabel, default: 0] += 1 }
        }
        // Most used wins; ties go to the alphabetically first, so results are stable.
        func top(_ counts: [String: Int]?) -> String? {
            counts?.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
        }
        for key in Set(services.keys).union(providers.keys) {
            byKey[key] = Choice(service: top(services[key]), provider: top(providers[key]))
        }
    }

    public func choice(for key: String) -> Choice? { byKey[key] }
}

/// Guesses where variables come from: the user's own earlier choices for
/// the same name first, then `SourceGuesser` (name words, value formats).
/// Only empty fields are ever filled; nothing typed by the user is replaced.
public enum SourceSuggester {
    public static func suggest(key: String, value: String? = nil, history: SourceHistory) -> SourceGuess? {
        let past = history.choice(for: key)
        let guess = SourceGuesser.guess(key: key, value: value)
        let service = past?.service ?? guess?.service
        let provider = past?.provider ?? guess?.provider
        guard service != nil || provider != nil else { return nil }

        var reasons: [String] = []
        if past?.service != nil || past?.provider != nil { reasons.append("Same name used elsewhere") }
        let guessUsed = (past?.service == nil && guess?.service != nil) || (past?.provider == nil && guess?.provider != nil)
        if guessUsed, let reason = guess?.reason, !reason.isEmpty { reasons.append(reason) }
        return SourceGuess(service: service, provider: provider, reason: reasons.joined(separator: " · "))
    }

    /// What would actually be written: a provider only when none shows yet
    /// (and, for a Library key, the name stays unique under it); a service
    /// only when none was chosen and it adds something beyond what the
    /// provider already implies.
    @MainActor
    static func planned(_ variable: Variable, _ guess: SourceGuess, context: ModelContext) -> (service: String?, provider: String?) {
        var provider: String?
        if variable.displayService.isEmpty, let p = guess.provider {
            if variable.inLibrary {
                let siblings = Library.keys(provider: p, context: context)
                if !siblings.contains(where: { $0.key == variable.key && $0.persistentModelID != variable.persistentModelID }) {
                    provider = p
                }
            } else {
                provider = p
            }
        }
        var service: String?
        if variable.serviceCategory.isEmpty, let s = guess.service {
            let implied = ServiceCategory.suggested(forProvider: provider ?? variable.displayService)?.displayName
            if s != implied { service = s }
        }
        return (service, provider)
    }

    // MARK: Review existing variables

    public struct Item: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let key: String
        /// "Shop · production" or "Library".
        public let place: String
        public let service: String?
        public let provider: String?
        public let reason: String
    }

    /// Suggestions for variables with an empty Service or Provider, in a
    /// stable order (place, then name).
    @MainActor
    public static func review(_ variables: [Variable], context: ModelContext) -> [Item] {
        let history = SourceHistory(context: context)
        var items: [Item] = []
        for v in variables {
            guard let guess = suggest(key: v.key, history: history) else { continue }
            let plan = planned(v, guess, context: context)
            guard plan.service != nil || plan.provider != nil else { continue }
            let place = v.inLibrary ? "Library"
                : "\(v.environment?.project?.name ?? "?") · \(v.environment?.name ?? "?")"
            items.append(Item(id: v.id, key: v.key, place: place, service: plan.service,
                              provider: plan.provider, reason: guess.reason))
        }
        return items.sorted { ($0.place, $0.key) < ($1.place, $1.key) }
    }

    /// Every variable of every project plus the Library.
    @MainActor
    public static func reviewAll(context: ModelContext) -> [Item] {
        review((try? context.fetch(FetchDescriptor<Variable>())) ?? [], context: context)
    }

    /// Writes the picked items. Returns how many variables changed.
    @MainActor
    @discardableResult
    public static func apply(_ items: [Item], context: ModelContext) -> Int {
        let ids = Set(items.map(\.id))
        let variables = ((try? context.fetch(FetchDescriptor<Variable>())) ?? []).filter { ids.contains($0.id) }
        let byID = Dictionary(variables.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = 0
        for item in items {
            guard let v = byID[item.id] else { continue }
            if VariableEditor.fill(v, with: SourceGuess(service: item.service, provider: item.provider, reason: item.reason),
                                   context: context) {
                changed += 1
            }
        }
        return changed
    }
}

extension VariableEditor {
    /// Fills an empty Service / Provider of a new variable from its name, its
    /// value (looked at in memory only) and earlier choices for the same name.
    @MainActor
    public static func fillMissingSource(_ variable: Variable, value: String? = nil, context: ModelContext,
                                         history: SourceHistory? = nil) {
        let history = history ?? SourceHistory(context: context)
        guard let guess = SourceSuggester.suggest(key: variable.key, value: value, history: history) else { return }
        fill(variable, with: guess, context: context)
    }

    /// Applies a guess to the empty fields only (see `SourceSuggester.planned`).
    @MainActor
    @discardableResult
    static func fill(_ variable: Variable, with guess: SourceGuess, context: ModelContext) -> Bool {
        let plan = SourceSuggester.planned(variable, guess, context: context)
        if let provider = plan.provider { setService(variable, to: provider) }
        if let service = plan.service { setCategory(variable, to: service) }
        return plan.provider != nil || plan.service != nil
    }
}
