import Combine
import Foundation

struct RimoToast: Identifiable, Equatable {
    enum Kind { case information, success, error }
    let id = UUID()
    let message: String
    let kind: Kind
    let detail: String?

    var symbol: String {
        switch kind {
        case .information: "info.circle"
        case .success: "checkmark.circle"
        case .error: "exclamationmark.circle"
        }
    }
}

@MainActor
final class RimoToastCenter: ObservableObject {
    @Published private(set) var current: RimoToast?
    private var expiry: Task<Void, Never>?

    func show(_ message: String, kind: RimoToast.Kind = .information, detail: String? = nil,
              duration: Duration? = nil) {
        expiry?.cancel()
        let toast = RimoToast(message: message, kind: kind, detail: detail)
        current = toast
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: duration ?? .seconds(kind == .error ? 5 : 3)) }
            catch { return }
            self?.dismiss(id: toast.id)
        }
    }

    func dismiss(id: UUID) {
        guard current?.id == id else { return }
        expiry?.cancel()
        expiry = nil
        current = nil
    }
}
