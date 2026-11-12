import Foundation
import CoreGraphics

public struct SpaceNode: Identifiable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let size: Int64
    public let isDirectory: Bool
}

public enum SpaceLens {
    /// Immediate children of `dir` with recursive sizes, largest first.
    public static func children(of dir: URL) async -> [SpaceNode] {
        await offMain {
            let fm = FileManager.default
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return [] }
            let nodes: [SpaceNode] = await withTaskGroup(of: SpaceNode?.self) { g in
                for u in items {
                    g.addTask {
                        let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                        if v?.isSymbolicLink == true { return nil }
                        return SpaceNode(url: u, size: allocatedSize(of: u), isDirectory: v?.isDirectory == true)
                    }
                }
                var out: [SpaceNode] = []
                for await n in g { if let n { out.append(n) } }
                return out
            }
            return nodes.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        }
    }

    /// Slice-and-dice treemap layout. Returns rects in the unit square scaled to `bounds`.
    public static func layout(sizes: [Int64], in bounds: CGRect) -> [CGRect] {
        var rects = [CGRect](repeating: .zero, count: sizes.count)
        func go(_ range: Range<Int>, _ r: CGRect, _ horizontal: Bool) {
            guard !range.isEmpty else { return }
            if range.count == 1 { rects[range.lowerBound] = r; return }
            let total = Double(range.reduce(0) { $0 + sizes[$1] })
            guard total > 0 else { return }
            // split into two halves of roughly equal weight
            var acc = 0.0, split = range.lowerBound + 1
            for i in range { acc += Double(sizes[i]); if acc >= total / 2 { split = max(i + 1, range.lowerBound + 1); break } }
            split = min(split, range.upperBound - 1)
            let leftW = Double((range.lowerBound..<split).reduce(0) { $0 + sizes[$1] }) / total
            if horizontal {
                let w = r.width * leftW
                go(range.lowerBound..<split, CGRect(x: r.minX, y: r.minY, width: w, height: r.height), false)
                go(split..<range.upperBound, CGRect(x: r.minX + w, y: r.minY, width: r.width - w, height: r.height), false)
            } else {
                let h = r.height * leftW
                go(range.lowerBound..<split, CGRect(x: r.minX, y: r.minY, width: r.width, height: h), true)
                go(split..<range.upperBound, CGRect(x: r.minX, y: r.minY + h, width: r.width, height: r.height - h), true)
            }
        }
        go(0..<sizes.count, bounds, bounds.width >= bounds.height)
        return rects
    }
}
