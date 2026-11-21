import CryptoKit
import DotFolioModels
import DotFolioSecurity
import Foundation
import LocalAuthentication

/// Development vs staging vs production for one project: which names are
/// missing where, which have no value, and — after Touch ID — whether the
/// values are the same. Values are only fingerprinted (SHA-256) in memory;
/// no plain value ever leaves `compareValues`.
public enum EnvironmentComparison {
    /// One environment's side of a name.
    public enum Cell: Equatable, Sendable {
        case missing
        case noValue
        case hasValue
    }

    /// What the values say once compared.
    public enum Verdict: Equatable, Sendable {
        /// Every environment has the same value.
        case same
        /// Values differ; `groups` lists environment names that share a value.
        case differs(groups: [[String]])
        /// Fewer than two environments have a value, so nothing to compare.
        case notComparable
    }

    public struct Row: Identifiable {
        public var id: String { key }
        public let key: String
        /// Environment name → cell, for every environment of the project.
        public let cells: [String: Cell]
        /// Environment name → variable (when the name exists there).
        public let variables: [String: Variable]
        /// Set by `compareValues`.
        public var verdict: Verdict?

        /// Environments that don't have this name at all.
        public var missingIn: [String] { cells.filter { $0.value == .missing }.map(\.key).sorted() }
        public var isMissingSomewhere: Bool { cells.values.contains(.missing) }
        /// Environments where the name exists.
        public var presentIn: [String] { cells.filter { $0.value != .missing }.map(\.key) }
    }

    /// One row per distinct name, in name order; environments in their order.
    public static func rows(for project: Project) -> [Row] {
        let environments = project.sortedEnvironments
        var byKey: [String: [String: Variable]] = [:]
        for env in environments {
            for v in env.variables ?? [] {
                byKey[v.key, default: [:]][env.name] = v
            }
        }
        return byKey.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { key in
            let vars = byKey[key] ?? [:]
            var cells: [String: Cell] = [:]
            for env in environments {
                if let v = vars[env.name] { cells[env.name] = v.hasValue ? .hasValue : .noValue }
                else { cells[env.name] = .missing }
            }
            return Row(key: key, cells: cells, variables: vars)
        }
    }

    /// Reads every stored value once (with an authenticated context) and
    /// fills in each row's verdict. Only fingerprints are kept.
    public static func compareValues(_ rows: [Row], environmentOrder: [String], secrets: any SecretStore,
                                     context: LAContext) throws(VariableEditor.Failure) -> [Row] {
        try rows.map { row throws(VariableEditor.Failure) in
            var fingerprints: [(env: String, digest: String)] = []
            for env in environmentOrder {
                guard let v = row.variables[env], v.hasValue,
                      let plain = try VariableEditor.value(of: v, secrets: secrets, context: context) else { continue }
                fingerprints.append((env, fingerprint(plain)))
            }
            var copy = row
            copy.verdict = verdict(for: fingerprints)
            return copy
        }
    }

    static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Groups environments by fingerprint, keeping the environment order.
    static func verdict(for fingerprints: [(env: String, digest: String)]) -> Verdict {
        guard fingerprints.count >= 2 else { return .notComparable }
        var order: [String] = []
        var groups: [String: [String]] = [:]
        for (env, digest) in fingerprints {
            if groups[digest] == nil { order.append(digest) }
            groups[digest, default: []].append(env)
        }
        return order.count == 1 ? .same : .differs(groups: order.compactMap { groups[$0] })
    }

    /// Counts for the summary line.
    public struct Summary: Equatable, Sendable {
        public var total = 0
        public var missingSomewhere = 0
        public var onlyInOne = 0
        public var same = 0
        public var differs = 0
    }

    public static func summary(_ rows: [Row]) -> Summary {
        var s = Summary(total: rows.count)
        for row in rows {
            if row.isMissingSomewhere { s.missingSomewhere += 1 }
            if row.presentIn.count == 1 { s.onlyInOne += 1 }
            switch row.verdict {
            case .same: s.same += 1
            case .differs: s.differs += 1
            default: break
            }
        }
        return s
    }
}
