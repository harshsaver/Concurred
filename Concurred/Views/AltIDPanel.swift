import AppKit
import SwiftUI

/// Right-side inspector panel for the Cloak / Alt ID feature. Loads and saves its own
/// `AltIdentity` from local storage, without Keychain authentication.
struct AltIDPanel: View {
    @Binding var cloakEnabled: Bool
    @State private var identity = AltIdentity.empty
    @State private var savedIdentity = AltIdentity.empty
    @State private var errorText: String?
    @State private var loaded = false
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                altCard

                manageCard

                if let error = errorText ?? identity.validationError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                if !loaded {
                    HStack {
                        Button("Retry loading", action: load)
                        Button("Reset stored identity", role: .destructive) { confirmReset = true }
                    }
                }
                HStack {
                    Text(!loaded ? "Identity unavailable" : (identity == savedIdentity ? "Saved" : "Unsaved changes"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save identity", action: save)
                        .buttonStyle(.borderedProminent)
                        .disabled(!loaded || identity == savedIdentity || identity.validationError != nil)
                }
                Text("Alt ID is saved locally for your macOS account and opens without a password. The identity file is not separately encrypted. Cloak replaces configured values and recognized emails, phone numbers, checksum-valid card numbers, SSNs and IPv4 addresses before chat and web search. Use Review Cloak beside the composer toggle to inspect outgoing text and locally detect additional names, places, organizations and addresses. It may miss personal information. Saved chats contain the original text on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .task { load() }
        .confirmationDialog("Reset the saved identity?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset identity", role: .destructive) {
                identity = .empty
                do {
                    try identity.save()
                    savedIdentity = identity
                    loaded = true
                    errorText = nil
                } catch { errorText = error.localizedDescription }
            }
        } message: { Text("This replaces the locally saved identity with empty fields.") }
    }

    private func load() {
        do {
            identity = try AltIdentity.load()
            savedIdentity = identity
            loaded = true
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }

    private func save() {
        do {
            try identity.save()
            savedIdentity = identity
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }

    // MARK: - Header

    private var header: some View {
        AltIDHeader(cloakEnabled: $cloakEnabled)
    }

    // MARK: - Generated identity card

    private var altCard: some View {
        AltIDCardBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(identity.altName.isEmpty ? "No alt identity yet" : identity.altName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 6) {
                    if !identity.altDOB.isEmpty {
                        Label(identity.altDOB, systemImage: "calendar")
                    }
                    if !identity.altAddress.isEmpty {
                        Label {
                            Text(identity.altAddress)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "house")
                        }
                    }
                    if !identity.altEmail.isEmpty {
                        Label(identity.altEmail, systemImage: "envelope")
                    }
                    if !identity.altPhone.isEmpty {
                        Label(identity.altPhone, systemImage: "phone")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 10) {
                    Button {
                        identity.refreshAlt()
                    } label: {
                        Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button("Clear fields") {
                        identity = .empty
                    }
                    Spacer()
                    Button(action: copyAltIdentity) {
                        Label("Copy all", systemImage: "doc.on.doc")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Manage details card

    private var manageCard: some View {
        AltIDCardBox {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    pairFields("Name", real: $identity.realName, alt: $identity.altName)
                    Text("Enter names with the first name first. Cloak matches full names and first names, and restores both in replies. Add custom pairs for first, two-part and middle-name forms. Connected pairs restore together; ambiguous short names are left unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    pairFields("Email", real: $identity.realEmail, alt: $identity.altEmail)
                    pairFields("Phone", real: $identity.realPhone, alt: $identity.altPhone)
                    pairFields("Address", real: $identity.realAddress, alt: $identity.altAddress)
                    pairFields("Date of birth", real: $identity.realDOB, alt: $identity.altDOB)

                    customPairsEditor
                }
                .padding(.top, 10)
            } label: {
                Label("Manage details", systemImage: "slider.horizontal.3")
                    .font(.headline)
            }
        }
    }

    @ViewBuilder private var customPairsEditor: some View {
        Divider()
        Text("Custom pairs")
            .font(.caption)
            .foregroundStyle(.secondary)

        ForEach($identity.customPairs) { $pair in
            HStack(spacing: 8) {
                TextField("Real", text: $pair.real)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("Alt", text: $pair.alt)
                    .textFieldStyle(.roundedBorder)
                Button {
                    identity.customPairs.removeAll { $0.id == pair.id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Remove this pair")
                .accessibilityLabel("Remove custom pair")
            }
        }

        Button {
            identity.customPairs.append(AltIdentity.CustomPair())
        } label: {
            Label("Add pair", systemImage: "plus")
        }
        .buttonStyle(.borderless)
    }

    private func pairFields(_ label: String, real: Binding<String>, alt: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("Real", text: real)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("Alt", text: alt)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func copyAltIdentity() {
        let block = """
        Name: \(identity.altName)
        Date of birth: \(identity.altDOB)
        Address: \(identity.altAddress)
        Email: \(identity.altEmail)
        Phone: \(identity.altPhone)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(block, forType: .string)
    }
}

/// Shares the conversation's live Cloak state with the composer toggle.
struct AltIDHeader: View {
    @Binding var cloakEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            PortraitAvatar(number: cloakEnabled ? 43 : 44, size: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text("Alt ID + Cloak").font(.title3.weight(.semibold))
                Toggle(cloakEnabled ? "Cloak on" : "Cloak off", isOn: $cloakEnabled)
                    .toggleStyle(.switch).controlSize(.small)
                    .font(.callout)
                Text(cloakEnabled ? "Your next message uses your alt identity." : "Your next message uses your original details.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A rounded card container used by the Alt ID panel.
private struct AltIDCardBox<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.quaternary)
            )
    }
}
