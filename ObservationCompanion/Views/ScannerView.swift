import SwiftUI
import Vision
import VisionKit
import EENApiToolkit

struct ScannerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var pasteText = ""
    @State private var showPasteField = !DataScannerViewController.isSupported
    @State private var scannerAvailable = DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    @State private var savedURL: String?
    @State private var showOAuthSheet = false
    @State private var oauthError: String?
    @State private var oauthUrl: URL?
    @State private var isWarmupDone = false

    private static let savedURLKey = "lastQRCodeURL"
    private static let minRemainingTTL: TimeInterval = 300

    var body: some View {
        ZStack {
            // Hidden warmup web view — warms the web content process so the
            // real OAuth web view in the sheet renders instantly.
            // Only loads about:blank to avoid interfering with the real OAuth flow.
            if !isWarmupDone {
                OAuthWarmupWebView(url: URL(string: "about:blank")!) {
                    isWarmupDone = true
                }
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
            }

            if verticalSizeClass == .compact {
                landscapeLayout
            } else {
                portraitLayout
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ScannerView")
        .onAppear {
            refreshSavedURL()
            fetchAuthUrl()
        }
        .sheet(isPresented: $showOAuthSheet) {
            oauthSheet
                .presentationDetents([.large])
                .interactiveDismissDisabled()
        }
    }

    // MARK: - Portrait Layout

    private var portraitLayout: some View {
        VStack(spacing: 20) {
            Spacer()
            brandingSection
            cameraScannerSection
            pasteURLSection
            oauthLoginSection
            Spacer()
            Text("v\(toolkitVersion)")
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Landscape Layout

    private var landscapeLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 16) {
                    Spacer()
                    brandingSection
                    oauthLoginSection
                    Spacer()
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    cameraScannerSection
                    pasteURLSection
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Text("v\(toolkitVersion)")
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.bottom, 4)
        }
    }

    // MARK: - Shared Components

    private var brandingSection: some View {
        VStack(spacing: 16) {
            if let uiImage = UIImage(named: "AppIcon") {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Text("Observation Companion")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

            VStack(spacing: 4) {
                Text("Scan the QR code from the")
                    .foregroundColor(.gray)
                Link("EEN Camera Observation App", destination: URL(string: "https://klaushofrichter.github.io/een-observation-app")!)
                    .font(.body)
                Text("or sign in with your EEN account.")
                    .foregroundColor(.gray)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
        }
    }

    private var cameraScannerSection: some View {
        Group {
            if scannerAvailable {
                DataScannerRepresentable { url in
                    handleScannedURL(url)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text("Camera not available")
                                .foregroundColor(.gray)
                            Text("Use paste URL below for testing")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    )
                    .padding(.horizontal, 20)
            }
        }
    }

    private var pasteURLSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                Button(action: { showPasteField.toggle() }) {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text(showPasteField ? "Hide URL Input" : "Paste URL")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }

                if let saved = savedURL {
                    Button {
                        handleScannedURL(saved, persist: false)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Reload")
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                }

                if showPasteField {
                    Button {
                        if let clip = UIPasteboard.general.string, !clip.isEmpty {
                            pasteText = clip
                            showPasteField = false
                            handleScannedURL(clip)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.clipboard.fill")
                            Text("Paste URL")
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                }
            }

            if showPasteField {
                HStack {
                    TextField("eenobserve://view?token=...&cam=...&base=...", text: $pasteText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .colorScheme(.dark)

                    Button("Go") {
                        handleScannedURL(pasteText)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(pasteText.isEmpty)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - OAuth Login

    private var oauthLoginSection: some View {
        VStack(spacing: 8) {
            Button {
                showOAuthSheet = true
            } label: {
                HStack(spacing: 8) {
                    if !isWarmupDone || oauthUrl == nil {
                        ProgressView()
                            .tint(.white)
                    }
                    Image(systemName: "person.crop.circle")
                    Text(isWarmupDone && oauthUrl != nil
                         ? "Sign In with Eagle Eye Networks"
                         : "Preparing Sign In…")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isWarmupDone && oauthUrl != nil ? Color.blue : Color.gray)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!isWarmupDone || oauthUrl == nil)
            .padding(.horizontal, 40)
            .accessibilityIdentifier("OAuthLoginButton")

            if let error = oauthError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }

    @ViewBuilder
    private var oauthSheet: some View {
        NavigationView {
            OAuthWebView(
                authUrl: oauthUrl ?? URL(string: "about:blank")!,
                redirectUri: AppConfig.redirectUri,
                onCallback: { code, state in
                    showOAuthSheet = false
                    handleOAuthCallback(code: code, state: state)
                },
                onError: { error in
                    showOAuthSheet = false
                    oauthError = error
                }
            )
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                            showOAuthSheet = false
                        }
                }
            }
        }
    }

    private func fetchAuthUrl() {
        Task {
            oauthUrl = await appState.toolkit.auth.getAuthUrl()
        }
    }

    // MARK: - Handlers

    private func handleScannedURL(_ urlString: String, persist: Bool = true) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            appState.connectionState = .error("Invalid URL: \(String(trimmed.prefix(60)))...")
            return
        }
        if persist {
            UserDefaults.standard.set(trimmed, forKey: Self.savedURLKey)
            savedURL = trimmed
        }
        appState.handleViewerURL(url)
    }

    private func handleOAuthCallback(code: String, state: String?) {
        Task {
            do {
                try await appState.toolkit.auth.handleCallback(code: code, state: state)
                appState.configureOAuth()
            } catch {
                oauthError = error.localizedDescription
            }
        }
    }

    private func refreshSavedURL() {
        guard let saved = UserDefaults.standard.string(forKey: Self.savedURLKey) else {
            savedURL = nil
            return
        }
        if let components = URLComponents(string: saved),
           let ttlString = components.queryItems?.first(where: { $0.name == "ttl" })?.value,
           let epoch = Double(ttlString),
           Date(timeIntervalSince1970: epoch).timeIntervalSinceNow < Self.minRemainingTTL {
            UserDefaults.standard.removeObject(forKey: Self.savedURLKey)
            savedURL = nil
        } else {
            savedURL = saved
        }
    }
}

// MARK: - DataScanner UIViewControllerRepresentable

struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        if !uiViewController.isScanning {
            try? uiViewController.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var hasScanned = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard !hasScanned else { return }
            switch item {
            case .barcode(let barcode):
                if let value = barcode.payloadStringValue {
                    hasScanned = true
                    dataScanner.stopScanning()
                    onScan(value)
                }
            default:
                break
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasScanned else { return }
            for item in addedItems {
                switch item {
                case .barcode(let barcode):
                    if let value = barcode.payloadStringValue,
                       value.hasPrefix("eenobserve://") {
                        hasScanned = true
                        dataScanner.stopScanning()
                        onScan(value)
                        return
                    }
                default:
                    break
                }
            }
        }
    }
}
