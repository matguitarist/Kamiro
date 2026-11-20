import Foundation

/// How a folder shows its items: icons, details (rows with columns), or columns.
public enum ViewMode: String, Codable, Sendable, CaseIterable {
    case icons, details, columns
}

/// The icon view's icon sizes, in points.
public enum IconSize {
    public static let range: ClosedRange<Double> = 32...256
    public static let standard: Double = 64

    /// The thumbnail size to ask for: a few fixed steps, so dragging the slider reuses them.
    public static func thumbnailStep(_ points: Double) -> Double {
        [64, 128, 256].first { $0 >= points } ?? 256
    }
}
