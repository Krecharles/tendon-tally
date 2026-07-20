import SwiftUI
import AppKit

struct AboutTabView: View {
    private static let sourceCodeURL = URL(string: "https://github.com/Krecharles/tendon-tally")!

    private var versionLabel: String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty:
            return "Version \(version) (\(build))"
        case let (version?, _):
            return "Version \(version)"
        case let (_, build?) where !build.isEmpty:
            return "Build \(build)"
        default:
            return "Development build"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)

            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    AppIconView(size: 112)

                    VStack(spacing: 5) {
                        Text("TendonTally")
                            .font(.system(size: 30, weight: .bold))

                        Text(versionLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 14) {
                    Text("TendonTally is open source under the MIT License. If you find it useful, you’re welcome to leave a star on GitHub.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)

                    Link(destination: Self.sourceCodeURL) {
                        Label {
                            Text("GitHub")
                        } icon: {
                            Image("GitHubMark", bundle: .appResources)
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 13, height: 13)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 32)

            Text("Made with ❤️ in London")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}
