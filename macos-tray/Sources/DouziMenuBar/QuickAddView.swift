import SwiftUI

struct QuickAddView: View {
    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    var onSubmit: (String) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("✨ 快速添加待办")
                .font(.headline)
                .foregroundColor(.primary)

            TextField("例如：明天上午9点给产品经理发邮件", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .focused($isFocused)
                .onSubmit {
                    submit()
                }

            HStack {
                Button(action: { onCancel() }) {
                    Text("取消")
                        .frame(minWidth: 60)
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: submit) {
                    Text("添加 ✅")
                        .frame(minWidth: 80)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Text("💡 回车确认，Esc 取消；该事项将会被添加到 Inbox，随后可以使用 AI 一键整理")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            isFocused = true
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        text = ""
    }
}
