/// Document-wide selection.
public enum Selection: Equatable {
    case none
    case rect(IRect)

    public var isActive: Bool {
        if case .rect(let r) = self, !r.isEmpty { return true }
        return false
    }
}
