import Cocoa
import Foundation

/// Checks GitHub Releases for a newer version of the app and presents a modal alert.
final class UpdateChecker {
    private static let releasesURL = URL(string: "https://api.github.com/repos/abiheiri/wamp/releases/latest")!
    private static let fallbackReleasesPageURL = URL(string: "https://github.com/abiheiri/wamp/releases")!
    /// Keeps the alert to a reasonable on-screen height. Every release notes
    /// section shipped so far fits well under this; it only kicks in for an
    /// unusually large release (many bundled changes in one version).
    private static let maxReleaseNotesLength = 1200

    /// Fetch the latest release and prompt the user if an update is available.
    /// Call from the main queue; network work is performed asynchronously.
    func checkForUpdates() {
        Task { await performCheck() }
    }

    private func performCheck() async {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            await showAlert(title: "Update Check Failed",
                            message: "Could not read the current app version.")
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: Self.releasesURL)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                await showAlert(title: "Update Check Failed",
                                message: "GitHub returned an unexpected response.")
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

            if isVersion(latestVersion, newerThan: currentVersion) {
                await showUpdateAvailableAlert(release: release, currentVersion: currentVersion)
            } else {
                await showAlert(title: "Wamp is Up to Date",
                                message: "You are running the latest version (\(currentVersion)).")
            }
        } catch {
            await showAlert(title: "Update Check Failed",
                            message: "Could not reach GitHub: \(error.localizedDescription)")
        }
    }

    /// Compares two semantic version strings (e.g. "1.2.1" vs "1.2.2").
    /// Returns `true` if `latest` is strictly newer than `current`.
    private func isVersion(_ latest: String, newerThan current: String) -> Bool {
        let latestComponents = latest.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(latestComponents.count, currentComponents.count)
        for i in 0..<maxCount {
            let latestPart = i < latestComponents.count ? latestComponents[i] : 0
            let currentPart = i < currentComponents.count ? currentComponents[i] : 0
            if latestPart != currentPart {
                return latestPart > currentPart
            }
        }
        return false
    }

    /// Truncates `body` to `maxReleaseNotesLength`, preferring to cut at the
    /// last paragraph break so a bullet is never chopped mid-sentence.
    private func truncatedReleaseNotes(_ body: String) -> String {
        guard body.count > Self.maxReleaseNotesLength else { return body }
        let cutoff = body.index(body.startIndex, offsetBy: Self.maxReleaseNotesLength)
        let truncated = body[..<cutoff]
        let notice = "…\n\n(See full notes on the Releases page.)"
        if let lastParagraphBreak = truncated.range(of: "\n\n", options: .backwards) {
            return String(truncated[..<lastParagraphBreak.lowerBound]) + "\n\n" + notice
        }
        return truncated + notice
    }

    @MainActor
    private func showUpdateAvailableAlert(release: GitHubRelease, currentVersion: String) {
        let alert = NSAlert()
        alert.messageText = "Wamp \(release.tagName) is available"
        let notes = truncatedReleaseNotes(release.body)
        alert.informativeText = "You are currently running Wamp \(currentVersion).\n\n\(notes)"
        alert.alertStyle = .informational

        let openPageButton = alert.addButton(withTitle: "Open Releases Page")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlUrl)
        }
    }

    @MainActor
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private struct GitHubRelease: Codable {
        let tagName: String
        let name: String
        let body: String
        let htmlUrl: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlUrl = "html_url"
        }
    }
}
