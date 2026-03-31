import SwiftUI

struct WatchLiveImageView: View {
    @EnvironmentObject var connectivityManager: WatchConnectivityManager
    @State private var imageData: Data?
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var autoRefresh = false
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else if let imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                        .onTapGesture {
                            Task { await loadLiveImage() }
                        }
                } else if loadFailed {
                    VStack(spacing: 4) {
                        Image(systemName: "video.slash")
                            .font(.title3)
                        Text("No image available")
                            .font(.caption2)
                    }
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .onTapGesture {
                        Task { await loadLiveImage() }
                    }
                }

                Text(connectivityManager.cameraName)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .lineLimit(1)

                if imageData != nil || loadFailed {
                    Button {
                        autoRefresh.toggle()
                    } label: {
                        Text(autoRefresh ? "auto-refresh" : "tap to refresh")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("")
        .task {
            await loadLiveImage()
        }
        .onChange(of: autoRefresh) {
            refreshTask?.cancel()
            refreshTask = nil
            if autoRefresh {
                refreshTask = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(2.5))
                        guard !Task.isCancelled else { break }
                        await loadLiveImage(showSpinner: false)
                    }
                }
            }
        }
        .onDisappear {
            refreshTask?.cancel()
        }
    }

    private func loadLiveImage(showSpinner: Bool = true) async {
        if showSpinner {
            isLoading = true
            loadFailed = false
        }
        await withCheckedContinuation { continuation in
            connectivityManager.requestLiveImage { data in
                Task { @MainActor in
                    if let data {
                        imageData = data
                        loadFailed = false
                    } else if showSpinner {
                        loadFailed = true
                    }
                    if showSpinner {
                        isLoading = false
                    }
                    continuation.resume()
                }
            }
        }
    }
}
