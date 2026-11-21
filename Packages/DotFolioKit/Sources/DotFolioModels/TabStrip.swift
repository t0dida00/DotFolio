/// Projects open as tabs above the detail column, in opening order, and the
/// active one. Plain value logic (no UI), so the Safari-like rules are tested.
public struct TabStrip<ID: Hashable>: Equatable {
    public var ids: [ID]
    public var active: ID?

    public init(ids: [ID] = [], active: ID? = nil) {
        self.ids = ids
        self.active = active
    }

    public var isEmpty: Bool { ids.isEmpty }

    /// Adds `id` at the end if it isn't open yet (does not activate it).
    public mutating func add(_ id: ID) {
        if !ids.contains(id) { ids.append(id) }
    }

    /// Opens several at once; the first becomes active.
    public mutating func open(_ many: [ID]) {
        for id in many { add(id) }
        if let first = many.first { active = first }
    }

    /// Closes a tab; when it was active, the tab to its right (or left)
    /// becomes active, like Safari.
    public mutating func close(_ id: ID) {
        guard let index = ids.firstIndex(of: id) else { return }
        ids.remove(at: index)
        if active == id {
            active = ids.isEmpty ? nil : ids[min(index, ids.count - 1)]
        }
    }

    public mutating func closeOthers(keeping id: ID) {
        ids = [id]
        active = id
    }

    /// Keeps the active tab if it survives; otherwise activates `id`.
    public mutating func closeRight(of id: ID) {
        guard let index = ids.firstIndex(of: id) else { return }
        ids.removeSubrange((index + 1)...)
        if let active, !ids.contains(active) { self.active = id }
    }

    public mutating func closeAll() {
        ids = []
        active = nil
    }

    /// Drops tabs whose item no longer exists.
    public mutating func prune(keeping existing: Set<ID>) {
        ids.removeAll { !existing.contains($0) }
    }
}
