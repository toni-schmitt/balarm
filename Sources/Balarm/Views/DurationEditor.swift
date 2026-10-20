import BalarmCore
import SwiftUI

/// Standard editable controls for pointer input, Voice Control and other assistive tools.
struct DurationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isHoursFocused: Bool
    @ViewState private var hours: String
    @ViewState private var minutes: String
    @ViewState private var seconds: String
    let onSave: (DurationEntry) -> Void

    init(entry: DurationEntry, onSave: @escaping (DurationEntry) -> Void) {
        _hours = ViewState(initialValue: String(entry.hours))
        _minutes = ViewState(initialValue: String(entry.minutes))
        _seconds = ViewState(initialValue: String(entry.seconds))
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit duration")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Form {
                TextField("Hours", text: $hours)
                    .focused($isHoursFocused)
                TextField("Minutes", text: $minutes)
                TextField("Seconds", text: $seconds)
            }
            .onSubmit(save)

            Text("Each field accepts 0–99. Extra minutes and seconds carry over.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if editedEntry == nil {
                Text("Enter whole numbers from 0 to 99.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(editedEntry == nil)
            }
        }
        .padding(24)
        .frame(width: 340)
        .onAppear { isHoursFocused = true }
        // The error line appears silently next to the focused field, so VoiceOver says it.
        .onChange(of: editedEntry == nil) { _, isInvalid in
            guard isInvalid else { return }
            AccessibilityNotification.Announcement("Enter whole numbers from 0 to 99.").post()
        }
    }

    private var editedEntry: DurationEntry? {
        guard let hours = fieldValue(hours) else { return nil }
        guard let minutes = fieldValue(minutes) else { return nil }
        guard let seconds = fieldValue(seconds) else { return nil }
        return DurationEntry(hours: hours, minutes: minutes, seconds: seconds)
    }

    private func fieldValue(_ text: String) -> Int? {
        if text.isEmpty { return 0 }
        guard text.count <= 2 else { return nil }
        guard text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }

    private func save() {
        guard let editedEntry else { return }
        onSave(editedEntry)
        dismiss()
    }
}
