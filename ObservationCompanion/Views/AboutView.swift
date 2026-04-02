import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()

                if let uiImage = UIImage(named: "AppIcon") {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }

                Text("Observation Companion")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("v\(toolkitVersion)")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                VStack(spacing: 16) {
                    Link(destination: URL(string: "https://github.com/klaushofrichter/ObservationCompanion")!) {
                        linkRow(icon: "chevron.left.forwardslash.chevron.right", text: "Observation Companion on GitHub")
                    }

                    Link(destination: URL(string: "https://github.com/klaushofrichter/een-observation-app")!) {
                        linkRow(icon: "globe", text: "EEN Observation Web App on GitHub")
                    }

                    Link(destination: URL(string: "https://github.com/klaushofrichter/een-swift-toolkit")!) {
                        linkRow(icon: "wrench.and.screwdriver", text: "EEN Swift Toolkit on GitHub")
                    }
                }
                .padding(.horizontal, 30)

                Text("Powered by EEN Swift Toolkit \(eenSwiftToolkitVersion)")
                    .font(.footnote)
                    .foregroundColor(.gray)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func linkRow(icon: String, text: String) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
            Text(text)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption)
        }
        .foregroundColor(.blue)
    }
}
