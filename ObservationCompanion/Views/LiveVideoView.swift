import SwiftUI
import AVFoundation

struct LiveVideoView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if appState.isVideoPlaying, let player = appState.hlsPlayer {
                    VideoPlayerView(player: player)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .overlay(boundingBoxOverlay(size: geometry.size))
                }

                if !appState.isVideoPlaying && appState.videoError == nil {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(.white)
                        Text("Loading HD stream...")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    .accessibilityIdentifier("StreamLoadingView")
                }

                if let error = appState.videoError {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 36))
                            .foregroundColor(.red)
                        Text("Stream Error")
                            .foregroundColor(.white)
                            .font(.headline)
                        Text(error)
                            .foregroundColor(.gray)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .accessibilityIdentifier("StreamErrorView")
                }

                if appState.isVideoPlaying {
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("LIVE HD \(Int(appState.hlsLatency))s")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .padding(8)
                            .accessibilityIdentifier("LiveBadge")
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func boundingBoxOverlay(size: CGSize) -> some View {
        let boxes = appState.liveBoundingBoxes
        if !boxes.isEmpty {
            let videoRect = Self.videoRect(viewSize: size)
            ZStack {
                ForEach(Array(boxes.enumerated()), id: \.offset) { _, box in
                    Circle()
                        .stroke(Color.green, lineWidth: 2)
                        .frame(
                            width: min(box.width * videoRect.width, box.height * videoRect.height),
                            height: min(box.width * videoRect.width, box.height * videoRect.height)
                        )
                        .position(
                            x: videoRect.minX + (box.x + box.width / 2) * videoRect.width,
                            y: videoRect.minY + (box.y + box.height / 2) * videoRect.height
                        )
                }
            }
        }
    }

    private static func videoRect(viewSize: CGSize) -> CGRect {
        let videoAspect: CGFloat = 16.0 / 9.0
        let viewAspect = viewSize.width / viewSize.height
        if viewAspect > videoAspect {
            let h = viewSize.height
            let w = h * videoAspect
            return CGRect(x: (viewSize.width - w) / 2, y: 0, width: w, height: h)
        } else {
            let w = viewSize.width
            let h = w / videoAspect
            return CGRect(x: 0, y: (viewSize.height - h) / 2, width: w, height: h)
        }
    }
}

struct VideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView(player: player)
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

class PlayerUIView: UIView {
    let playerLayer: AVPlayerLayer

    init(player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        super.init(frame: .zero)
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
