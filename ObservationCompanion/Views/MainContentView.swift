import SwiftUI
import EENSwiftToolkit

struct MainContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isVideoFullscreen = false
    @State private var showCameraPicker = false
    @State private var showLogoutConfirmation = false

    @ViewBuilder
    private var videoOrPlaceholder: some View {
        if appState.hlsPlayer != nil {
            LiveVideoView()
                .onTapGesture { isVideoFullscreen = true }
        } else {
            Color.black
                .overlay(Text("No video stream").foregroundColor(.gray))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch appState.connectionState {
                case .scanning:
                    ScannerView()

                case .connecting:
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Connecting to camera...")
                            .foregroundColor(.white)
                            .font(.headline)
                        if !appState.cameraId.isEmpty {
                            Text(appState.cameraId)
                                .foregroundColor(.gray)
                                .font(.caption)
                                .monospaced()
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("ConnectingView")

                case .live:
                    VStack(spacing: 0) {
                        // Camera name + countdown header
                        HStack {
                            Button {
                                showCameraPicker = true
                            } label: {
                                HStack(spacing: 4) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(appState.cameraName.isEmpty ? appState.cameraId : appState.cameraName)
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(appState.cameraId)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                            .monospaced()
                                    }
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            .accessibilityIdentifier("CameraNameButton")
                            Spacer()
                            TokenCountdownView()
                            Button {
                                if appState.authMode == .oauth {
                                    showLogoutConfirmation = true
                                } else {
                                    appState.reset()
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.red)
                            }
                            .padding(.leading, 8)
                            .accessibilityIdentifier("CloseButton")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.8))

                        if verticalSizeClass == .compact {
                            GeometryReader { geo in
                                HStack(spacing: 0) {
                                    videoOrPlaceholder
                                        .frame(width: geo.size.width * 0.5)

                                    EventFeedView()
                                        .frame(width: geo.size.width * 0.5)
                                }
                            }
                        } else {
                            videoOrPlaceholder
                                .aspectRatio(16/9, contentMode: .fit)

                            EventFeedView()
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("LiveView")

                case .expired:
                    VStack(spacing: 20) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        Text("Session Expired")
                            .font(.title)
                            .foregroundColor(.white)
                        Text("Scan a new QR code or sign in again to reconnect.")
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Button("Start Over") {
                            appState.reset()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .accessibilityIdentifier("StartOverButton")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("ExpiredView")

                case .error(let message):
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                        Text("Connection Error")
                            .font(.title)
                            .foregroundColor(.white)
                        Text(message)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .font(.body)
                        Button("Try Again") {
                            appState.reset()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .accessibilityIdentifier("TryAgainButton")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("ErrorView")
                }
            }
            .navigationBarHidden(true)
        }
        .fullScreenCover(isPresented: $isVideoFullscreen) {
            FullscreenVideoView(
                onDismiss: { isVideoFullscreen = false }
            )
        }
        .sheet(isPresented: $showCameraPicker) {
            CameraPickerSheet()
        }
        .alert("Sign Out", isPresented: $showLogoutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task {
                    try? await appState.toolkit.auth.revokeToken()
                    appState.reset()
                }
            }
        } message: {
            Text("You will need to sign in again to reconnect.")
        }
    }
}

// MARK: - Fullscreen Video

private struct FullscreenVideoView: View {
    let onDismiss: () -> Void
    @EnvironmentObject var appState: AppState
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing
            let h = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom

            ZStack {
                Color.black.ignoresSafeArea()

                if appState.hlsPlayer != nil {
                    if verticalSizeClass == .compact {
                        LiveVideoView()
                            .ignoresSafeArea()
                    } else {
                        LiveVideoView()
                            .frame(width: h, height: w)
                            .rotationEffect(.degrees(90))
                            .frame(width: w, height: h)
                    }
                }
            }
            .ignoresSafeArea()
            .onTapGesture { onDismiss() }
            .statusBarHidden(true)
        }
        .ignoresSafeArea()
    }
}
