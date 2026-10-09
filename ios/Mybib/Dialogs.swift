import SwiftUI
import Observation

/// Info, confirm and prompt dialogs that can be awaited, plus a short toast.
@MainActor
@Observable
final class DialogCenter {
    enum Kind { case info, confirm, prompt }

    struct Dialog: Identifiable {
        let id = UUID()
        let kind: Kind
        let text: String
        let resume: (String?) -> Void
    }

    var current: Dialog?
    var input = ""
    var toastText: String?
    @ObservationIgnored private var lastClosed = Date.distantPast

    func info(_ text: String) async {
        _ = await show(.info, text)
    }

    func confirm(_ text: String) async -> Bool {
        await show(.confirm, text) != nil
    }

    /// The typed text, or nil when cancelled.
    func prompt(_ text: String, initial: String = "") async -> String? {
        await show(.prompt, text, initial: initial)
    }

    private func show(_ kind: Kind, _ text: String, initial: String = "") async -> String? {
        close(nil)
        // an alert that was just dismissed needs a moment before the next one can appear
        let wait = 0.6 - Date().timeIntervalSince(lastClosed)
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        input = initial
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            current = Dialog(kind: kind, text: text) { cont.resume(returning: $0) }
        }
    }

    func close(_ result: String?) {
        guard let d = current else { return }
        current = nil
        lastClosed = Date()
        d.resume(result)
    }

    func toast(_ text: String) {
        toastText = text
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toastText == text { toastText = nil }
        }
    }
}

struct DialogHost: ViewModifier {
    @Bindable var center: DialogCenter
    let ok: String
    let cancel: String

    private var shown: Binding<Bool> {
        Binding(
            get: { center.current != nil },
            set: { show in
                // buttons resolve the dialog themselves; this only catches a dismissal without a button
                guard !show, let id = center.current?.id else { return }
                Task { @MainActor in
                    if center.current?.id == id { center.close(nil) }
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .alert(center.current?.text ?? "", isPresented: shown, presenting: center.current) { d in
                switch d.kind {
                case .info:
                    Button("OK") { center.close("") }
                case .confirm:
                    Button(cancel, role: .cancel) { center.close(nil) }
                    Button(ok) { center.close("") }
                case .prompt:
                    TextField("", text: $center.input)
                    Button(cancel, role: .cancel) { center.close(nil) }
                    Button(ok) { center.close(center.input) }
                }
            }
            .overlay(alignment: .bottom) {
                if let t = center.toastText {
                    Text(t)
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.thickMaterial, in: Capsule())
                        .padding(.bottom, 70)
                        .transition(.opacity)
                }
            }
            .animation(.default, value: center.toastText)
    }
}
