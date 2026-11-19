import Foundation

/// Runs `transform` over `items` with at most `limit` in flight, keeping the input order.
func concurrentMap<T: Sendable, R: Sendable>(_ items: [T], limit: Int = 6,
                                             _ transform: @escaping @Sendable (T) async throws -> R) async throws -> [R] {
    try await withThrowingTaskGroup(of: (Int, R).self) { group in
        var results = [R?](repeating: nil, count: items.count)
        var next = 0
        func add() {
            guard next < items.count else { return }
            let i = next, item = items[i]
            next += 1
            group.addTask { (i, try await transform(item)) }
        }
        for _ in 0..<min(limit, items.count) { add() }
        while let (i, r) = try await group.next() {
            results[i] = r
            add()
        }
        return results.map { $0! }
    }
}
