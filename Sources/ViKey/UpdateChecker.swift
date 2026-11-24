import Foundation
import ViKeyCore

/// Asks GitHub for the latest ViKey release and compares it with the running version.
/// One unauthenticated GET of the public releases API; nothing about the user is sent (the
/// User-Agent is just "ViKey/<version>"). ViKey never downloads or installs anything itself:
/// it only points the user at the release page.
final class UpdateChecker {
    struct Release {
        let version: AppVersion
        let page: URL
    }

    enum Outcome {
        case upToDate(AppVersion)
        case available(Release)
        case failed(String)
    }

    static let apiURL = URL(string: "https://api.github.com/repos/sunnysideprojects/vikey/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/sunnysideprojects/vikey/releases/latest")!

    /// Nil when running outside the app bundle (swift run).
    let current: AppVersion?
    /// A newer release found by the last successful check.
    private(set) var available: Release?
    /// Called on the main thread when `available` changes.
    var onChange: (() -> Void)?

    private var timer: Timer?
    private let session = URLSession(configuration: .ephemeral)

    init(currentVersion: String?) {
        current = currentVersion.flatMap(AppVersion.init)
    }

    /// Check shortly after launch, then once a day.
    func startAutomatic() {
        guard timer == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, self.timer != nil else { return }
            self.check()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in self?.check() }
        timer?.tolerance = 60 * 60
    }

    func stopAutomatic() {
        timer?.invalidate()
        timer = nil
    }

    /// `completion` runs on the main thread.
    func check(completion: ((Outcome) -> Void)? = nil) {
        guard let current else {
            completion?(.failed("Không rõ phiên bản đang chạy."))
            return
        }
        var request = URLRequest(url: Self.apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ViKey/\(current)", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { [weak self] data, response, error in
            let outcome = Self.outcome(current: current, data: data, response: response, error: error)
            DispatchQueue.main.async {
                guard let self else { return }
                if case .available(let release) = outcome {
                    self.setAvailable(release)
                } else if case .upToDate = outcome {
                    self.setAvailable(nil)
                }  // on failure keep whatever we knew
                completion?(outcome)
            }
        }.resume()
    }

    private func setAvailable(_ release: Release?) {
        let changed = release?.version != available?.version
        available = release
        if changed { onChange?() }
    }

    static func outcome(current: AppVersion, data: Data?, response: URLResponse?, error: Error?) -> Outcome {
        if let error { return .failed(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { return .failed("Không có phản hồi từ GitHub.") }
        guard http.statusCode == 200 else { return .failed("GitHub trả về mã \(http.statusCode).") }
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let latest = AppVersion(tag)
        else { return .failed("Không đọc được thông tin bản phát hành.") }
        guard latest > current else { return .upToDate(current) }
        let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage
        return .available(Release(version: latest, page: page))
    }
}
