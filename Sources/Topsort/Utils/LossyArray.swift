import Foundation

/// An array that decodes element by element, skipping the elements that no longer decode
/// instead of failing the whole array. Encodes exactly like `[Element]`, so files written as a
/// plain array (by an earlier SDK version) read back unchanged.
///
/// The persisted event queue needs this: one event saved by an older version with a value the
/// current models reject would otherwise make the whole file unreadable and lose every event in it.
struct LossyArray<Element: Codable>: Codable {
    var elements: [Element]

    init(_ elements: [Element]) {
        self.elements = elements
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        var skipped = 0
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                // A failed decode does not advance the container; consume the element.
                _ = try container.decode(Skipped.self)
                skipped += 1
            }
        }
        if skipped > 0 {
            Logger.warning("Skipped \(skipped) persisted events that no longer decode")
        }
        self.elements = elements
    }

    func encode(to encoder: Encoder) throws {
        try elements.encode(to: encoder)
    }

    private struct Skipped: Decodable {
        init(from _: Decoder) throws {}
    }
}
