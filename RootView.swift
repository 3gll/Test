import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct RootView: View {
    @State private var selectedIPA: URL?
    @State private var report: IPAReport?
    @State private var importedImage: UIImage?
    @State private var imageData: Data?
    @State private var resourcePath = ""
    @State private var showIPAPicker = false
    @State private var showImagePicker = false
    @State private var showExporter = false
    @State private var outputURL: URL?
    @State private var errorMessage: String?
    @State private var status = "Import an IPA to begin."
    @State private var isBusy = false
    @State private var enabledModules: Set<String> = ["Visual resource replacement"]

    private let engine = IPAEngine()
    private let modules = [
        "Visual resource replacement",
        "Developer test configuration",
        "StoreKit sandbox test plan",
        "Mod Menu preview"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    importCard
                    if let report { analysisCard(report) }
                    designerCard
                    modulesCard
                    buildCard
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(18)
            }
            .background(Color(red: 0.035, green: 0.035, blue: 0.055))
            .navigationTitle("IPA MOD ENGINE")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $showIPAPicker, allowedContentTypes: [.data], allowsMultipleSelection: false, onCompletion: handleIPAImport)
            .fileImporter(isPresented: $showExporter, allowedContentTypes: [.data], allowsMultipleSelection: false) { _ in }
            .alert("Operation failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showImagePicker) {
                PhotoPicker(image: $importedImage, data: $imageData)
            }
        }
        .tint(Color(red: 0.62, green: 0.36, blue: 1))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("IPA WORKSTATION")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(.cyan)
            Text("Analyze. Customize. Validate.")
                .font(.title2.bold())
            Text("Non-destructive IPA inspection and authorized resource packaging.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var importCard: some View {
        panel("01  IMPORT IPA", icon: "archivebox") {
            Button {
                showIPAPicker = true
            } label: {
                Label(selectedIPA?.lastPathComponent ?? "Choose IPA from Files", systemImage: "tray.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)

            if let selectedIPA {
                Text(selectedIPA.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("Analyze application", systemImage: "waveform.path.ecg") {
                    Task { await analyze(url: selectedIPA) }
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }
        }
    }

    private func analysisCard(_ report: IPAReport) -> some View {
        panel("02  APP ANALYSIS", icon: "cpu") {
            infoRow("Bundle ID", report.bundleIdentifier ?? "Unavailable")
            infoRow("Version", report.version ?? "Unavailable")
            infoRow("Executable", report.executable ?? "Unavailable")
            infoRow("Architecture", report.architectures.isEmpty ? "Not detected" : report.architectures.joined(separator: ", "))
            infoRow("Frameworks", report.frameworks.isEmpty ? "None listed" : report.frameworks.joined(separator: ", "))
            ForEach(report.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var designerCard: some View {
        panel("03  MOD MENU DESIGNER", icon: "slider.horizontal.3") {
            Button {
                showImagePicker = true
            } label: {
                Label("Import menu artwork", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if let importedImage {
                Image(uiImage: importedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .bottomTrailing) {
                        Text("LIVE PREVIEW")
                            .font(.system(size: 9, weight: .bold))
                            .padding(7)
                            .background(.black.opacity(0.75), in: Capsule())
                            .padding(8)
                    }
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(0.04))
                    .frame(height: 100)
                    .overlay(Text("Menu artwork preview").foregroundStyle(.secondary))
            }

            Text("Optional resource replacement path inside the IPA")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Payload/App.app/Assets.car", text: $resourcePath)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.footnote.monospaced())
        }
    }

    private var modulesCard: some View {
        panel("04  MODULES", icon: "puzzlepiece.extension") {
            ForEach(modules, id: \.self) { module in
                Toggle(module, isOn: Binding(
                    get: { enabledModules.contains(module) },
                    set: { value in
                        if value { enabledModules.insert(module) } else { enabledModules.remove(module) }
                    }
                ))
                .font(.subheadline)
            }
            Text("Gameplay cheats, entitlement bypasses, and protected unlocks are not applied. Test modules are manifests and require developer-provided hooks.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var buildCard: some View {
        panel("05  BUILD & VALIDATE", icon: "hammer") {
            Button {
                Task { await build() }
            } label: {
                HStack {
                    if isBusy { ProgressView().tint(.white) }
                    Text(isBusy ? "Processing…" : "Package authorized changes")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || selectedIPA == nil)

            if let outputURL {
                ShareLink(item: outputURL) {
                    Label("Export \(outputURL.lastPathComponent)", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Text("The output is an IPA archive. Replacing signed app resources invalidates the original signature; installation requires legitimate re-signing and compatible provisioning.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func panel<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.white)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.075, green: 0.075, blue: 0.11), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.07)))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.caption)
    }

    private func handleIPAImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let copied = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
                try FileManager.default.copyItem(at: url, to: copied)
                selectedIPA = copied
                report = nil
                outputURL = nil
                status = "IPA imported into an isolated working copy."
            } catch { errorMessage = error.localizedDescription }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func analyze(url: URL) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("IPAModEngine")
            report = try engine.inspect(ipaURL: url, workspace: workspace)
            status = "Analysis completed. Original archive unchanged."
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func build() async {
        guard let selectedIPA else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("IPAModEngine-\(Date.now.formatted(.dateTime.year().month().day().hour().minute())).ipa")
            try engine.package(
                ipaURL: selectedIPA,
                outputURL: destination,
                replacementImage: imageData,
                replacementRelativePath: resourcePath.isEmpty ? nil : resourcePath
            )
            outputURL = destination
            status = "IPA archive packaged and structurally validated. Signature status remains separate."
        } catch { errorMessage = error.localizedDescription }
    }
}

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var data: Data?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        return PHPickerViewController(configuration: config)
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {
        controller.delegate = context.coordinator
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage, let bytes = image.pngData() else { return }
                DispatchQueue.main.async {
                    self.parent.image = image
                    self.parent.data = bytes
                }
            }
        }
    }
}
