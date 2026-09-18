import AppKit
import SwiftUI

/// Right-side inspector panel for the Cloak / Alt ID feature. Loads and saves its own
/// `AltIdentity` in the Keychain, so it needs nothing from the environment.
struct AltIDPanel: View {
    @State private var identity = AltIdentity.load()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                altCard

                manageCard

                Text("When Cloak is on in a chat, your real info is swapped for the alt identity before your message is sent, and swapped back in the reply. Stored only in your Keychain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.badge.shield.checkmark")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Alt ID + Cloak")
                    .font(.title3.weight(.semibold))
                Text("Your stand-in identity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
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
                        identity.save()
                    } label: {
                        Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button("Reset") {
                        identity = .empty
                        identity.save()
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
                    pairFields("Email", real: $identity.realEmail, alt: $identity.altEmail)
                    pairFields("Phone", real: $identity.realPhone, alt: $identity.altPhone)
                    pairFields("Address", real: $identity.realAddress, alt: $identity.altAddress)
                    pairFields("Date of birth", real: $identity.realDOB, alt: $identity.altDOB)

                    customPairsEditor

                    HStack {
                        Spacer()
                        Button("Save") { identity.save() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
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
