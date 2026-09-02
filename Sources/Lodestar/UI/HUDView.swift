import SwiftUI

/// State backing the cursor HUD. The controller sets `onSubmit`; the view drives it.
final class HUDModel: ObservableObject {
    @Published var input: String = ""
    @Published var answer: String = ""
    @Published var busy: Bool = false
    var onSubmit: ((String) -> Void)?

    func submit() {
        let text = input
        input = ""
        onSubmit?(text)
    }
}

/// The little bubble that appears next to the cursor.
struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "cursorarrow.rays")
                    .foregroundStyle(.yellow)
                TextField("Ask about what's on screen…", text: $model.input)
                    .textFieldStyle(.plain)
                    .onSubmit { model.submit() }
                if model.busy {
                    ProgressView().controlSize(.small)
                }
            }
            if !model.answer.isEmpty {
                Divider()
                ScrollView {
                    Text(model.answer)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(12)
        .frame(width: 380)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)))
    }
}
