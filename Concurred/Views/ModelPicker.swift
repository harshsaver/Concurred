import SwiftUI

struct ModelPicker: View {
    @Bindable var vm: ChatViewModel
    @State private var isPresented = false
    @State private var query = ""
    @State private var customID = ""

    private var filtered: [String] {
        vm.models.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Button {
            customID = vm.selectedModel
            isPresented = true
        } label: {
            HStack(spacing: 6) {
                Text("Model").foregroundStyle(.secondary)
                Text(vm.selectedModel.isEmpty ? "Choose a model" : vm.selectedModel).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.1)))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
        .frame(maxWidth: 280, alignment: .leading)
        .disabled(vm.isStreaming)
        .help(vm.selectedModel.isEmpty ? "Choose or enter a model" : "Model: \(vm.selectedModel)")
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Models").font(.headline)
                    Spacer()
                    if vm.isLoadingModels { ProgressView().controlSize(.small) }
                    Button { Task { await vm.loadModels() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(vm.isLoadingModels)
                }
                TextField("Search models", text: $query).textFieldStyle(.roundedBorder)
                if let error = vm.modelsError {
                    Text(error).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                List(filtered, id: \.self) { model in
                    Button {
                        vm.selectModel(model)
                        isPresented = false
                    } label: {
                        HStack {
                            Text(model).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            if model == vm.selectedModel { Image(systemName: "checkmark") }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(model)
                }
                .overlay {
                    if filtered.isEmpty && !vm.isLoadingModels {
                        Text(query.isEmpty ? "No models loaded" : "No matching models").foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text("Enter a model ID").font(.subheadline.weight(.medium))
                HStack {
                    TextField("Model ID from your provider", text: $customID)
                        .textFieldStyle(.roundedBorder).onSubmit(useCustomID)
                    Button("Use", action: useCustomID)
                        .disabled(customID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
            .frame(width: 420, height: 480)
        }
    }

    private func useCustomID() {
        guard !customID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        vm.selectModel(customID)
        isPresented = false
    }
}
