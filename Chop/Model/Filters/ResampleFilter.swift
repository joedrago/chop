import Foundation

/// Resampling filter for image resize. Bilinear is the sane default.
public enum ResampleFilter: String, CaseIterable {
    case nearest
    case bilinear
    case lanczos3

    public var displayName: String {
        switch self {
        case .nearest: return "Nearest"
        case .bilinear: return "Bilinear"
        case .lanczos3: return "Lanczos3"
        }
    }
}
