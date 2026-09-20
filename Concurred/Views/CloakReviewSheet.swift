import SwiftUI

struct CloakReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var review: CloakReview
    let usesSearch: Bool
    let onSend: (CloakReview) -> Void
    @State private var candidates: [LocalIdentifierDetector.Candidate] = []
    @State private var detecting = true
    @State private var phrase = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Review Cloak").font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Send reviewed message") { onSend(review); dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            Text("Review the text leaving this Mac. Detection runs locally and may miss details. Only the phrases you choose are additionally hidden.")
                .foregroundStyle(.secondary).font(.callout)
            if usesSearch {
                Text("Web search receives the last outgoing user message. Search results are added afterward and cloaked before the provider request.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if detecting { ProgressView("Checking names, places and organizations on this Mac…").controlSize(.small) }
                    ForEach(candidates) { candidate in
                        Toggle(isOn: Binding(get: { review.hidden.contains(candidate) }, set: { _ in review.toggle(candidate) })) {
                            HStack {
                                Text(candidate.text).textSelection(.enabled)
                                Spacer()
                                Text(candidate.kind.lowercased()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack {
                        TextField("Additional exact phrase to hide", text: $phrase)
                        Button("Hide phrase", action: hidePhrase).disabled(!canHidePhrase)
                    }
                    if !review.vault.substitutions.isEmpty {
                        DisclosureGroup("Replacement map · \(review.vault.substitutions.count)") {
                            ForEach(review.vault.substitutions, id: \.real) { pair in
                                HStack(alignment: .top) {
                                    Text(pair.real)
                                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                    Text(pair.alt)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                            }
                        }
                    }
                    Divider()
                    Text("Outgoing conversation").font(.headline)
                    ForEach(Array(review.outgoing.enumerated()), id: \.offset) { _, message in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(message.role.capitalized).font(.caption.bold()).foregroundStyle(.secondary)
                            Text(message.content).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            Text("Originals stay in your local chat. Hidden phrases apply to this conversation during this app session. Use Alt ID custom pairs to keep them across sessions.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 700, height: 650)
        .task {
            let text = review.original.map(\.content).joined(separator: "\n\n")
            let found = await Task.detached(priority: .userInitiated) { LocalIdentifierDetector.candidates(in: text) }.value
            guard !Task.isCancelled else { return }
            candidates = found.filter { review.needsReview($0.text) }
            detecting = false
        }
    }

    private var canHidePhrase: Bool {
        let value = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && review.original.contains { $0.content.localizedCaseInsensitiveContains(value) }
            && review.needsReview(value) && !candidates.contains { $0.text.caseInsensitiveCompare(value) == .orderedSame }
    }

    private func hidePhrase() {
        guard canHidePhrase else { return }
        let candidate = LocalIdentifierDetector.Candidate(text: phrase.trimmingCharacters(in: .whitespacesAndNewlines), kind: "PRIVATE")
        candidates.append(candidate)
        review.toggle(candidate)
        phrase = ""
    }
}
