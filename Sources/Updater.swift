import AppKit
import UserNotifications

struct ReleaseInfo: Equatable {
    let tag: String
    let build: Int
    let assetURL: URL
    let pageURL: URL
    let notes: String
}

/// Sprawdza i instaluje nowe wersje z GitHub Releases (wydania o tagu „build-N”).
@MainActor
final class Updater: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let repository = "Calizhex/LaunchpadClassic"

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case downloading
        case installing
        case failed(String)
    }

    @Published var status: Status = .idle
    @Published var latest: ReleaseInfo?
    @Published var lastCheck: Date? = Preferences.lastUpdateCheck
    @Published var hasToken: Bool = Preferences.githubToken != nil
    @Published var autoCheck: Bool = Preferences.autoCheckUpdates {
        didSet { Preferences.autoCheckUpdates = autoCheck }
    }

    var onOpenUpdates: (() -> Void)?
    var onStatusChange: (() -> Void)?
    private var timer: Timer?

    var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }

    var currentVersionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return currentBuild > 0 ? "\(short) (build \(currentBuild))" : "\(short) (build lokalny)"
    }

    var updateAvailable: Bool {
        guard let latest else { return false }
        return latest.build > currentBuild
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        let due = lastCheck.map { Date().timeIntervalSince($0) > 6 * 3600 } ?? true
        if autoCheck && due {
            Task { await check(userInitiated: false) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.autoCheck else { return }
                Task { await self.check(userInitiated: false) }
            }
        }
    }

    func setToken(_ token: String) {
        Preferences.githubToken = token
        hasToken = Preferences.githubToken != nil
    }

    // MARK: Sprawdzanie

    func check(userInitiated: Bool) async {
        if status == .checking || status == .downloading || status == .installing { return }
        setStatus(.checking)
        do {
            let release = try await fetchLatest()
            latest = release
            lastCheck = Date()
            Preferences.lastUpdateCheck = lastCheck
            if release.build > currentBuild {
                setStatus(.available)
                if !userInitiated && Preferences.skippedBuild != release.build {
                    notify(release)
                }
            } else {
                setStatus(.upToDate)
            }
        } catch {
            setStatus(.failed(error.localizedDescription))
        }
    }

    private func setStatus(_ s: Status) {
        status = s
        onStatusChange?()
    }

    private func request(_ url: URL, accept: String) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue(accept, forHTTPHeaderField: "Accept")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        r.setValue("LaunchpadClassic", forHTTPHeaderField: "User-Agent")
        if let token = Preferences.githubToken {
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        r.timeoutInterval = 30
        return r
    }

    private struct APIRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let url: URL
        }
        let tag_name: String
        let html_url: URL
        let body: String?
        let assets: [Asset]
    }

    private func fetchLatest() async throws -> ReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
        let (data, response) = try await URLSession.shared.data(for: request(url, accept: "application/vnd.github+json"))
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200: break
        case 401: throw UpdateError("Token GitHuba jest nieprawidłowy albo wygasł.")
        case 403: throw UpdateError("GitHub odmówił dostępu (limit zapytań albo brak uprawnień tokenu).")
        case 404:
            throw UpdateError(Preferences.githubToken == nil
                ? "Repozytorium jest prywatne – dodaj token GitHuba poniżej."
                : "Nie znaleziono wydań albo token nie ma dostępu do repozytorium.")
        default: throw UpdateError("GitHub zwrócił błąd \(code).")
        }
        let api = try JSONDecoder().decode(APIRelease.self, from: data)
        guard let asset = api.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else {
            throw UpdateError("Najnowsze wydanie nie zawiera pliku .dmg.")
        }
        let build = Int(api.tag_name.replacingOccurrences(of: "build-", with: "")) ?? 0
        return ReleaseInfo(tag: api.tag_name, build: build, assetURL: asset.url,
                           pageURL: api.html_url, notes: api.body ?? "")
    }

    // MARK: Powiadomienia

    private func notify(_ release: ReleaseInfo) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Launchpad Classic"
            content.body = "Dostępna jest nowa wersja (build \(release.build)). Kliknij, aby ją zainstalować."
            let req = UNNotificationRequest(identifier: "update-\(release.build)", content: content, trigger: nil)
            center.add(req)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.onOpenUpdates?() }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func skipCurrent() {
        if let latest { Preferences.skippedBuild = latest.build }
    }

    // MARK: Instalacja

    func installLatest() async {
        guard let release = latest, release.build > currentBuild else { return }
        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent()
        guard target.pathExtension == "app", FileManager.default.isWritableFile(atPath: parent.path) else {
            setStatus(.failed("Przenieś aplikację do folderu Aplikacje, aby aktualizować ją automatycznie."))
            return
        }
        setStatus(.downloading)
        do {
            let req = request(release.assetURL, accept: "application/octet-stream")
            let (tmp, response) = try await URLSession.shared.download(for: req, delegate: RedirectStripper())
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError("Nie udało się pobrać pliku (\((response as? HTTPURLResponse)?.statusCode ?? 0)).")
            }
            let dmg = FileManager.default.temporaryDirectory.appendingPathComponent("LaunchpadClassic-\(release.build).dmg")
            try? FileManager.default.removeItem(at: dmg)
            try FileManager.default.moveItem(at: tmp, to: dmg)
            setStatus(.installing)
            try await Task.detached(priority: .userInitiated) {
                try Self.replaceApp(at: target, withAppFrom: dmg)
            }.value
            Self.relaunch(target)
        } catch {
            setStatus(.failed(error.localizedDescription))
        }
    }

    nonisolated private static func replaceApp(at target: URL, withAppFrom dmg: URL) throws {
        let fm = FileManager.default
        let mount = fm.temporaryDirectory.appendingPathComponent("lpc-mount-\(UUID().uuidString)")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-noautoopen", "-readonly", "-mountpoint", mount.path])
        defer {
            _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            try? fm.removeItem(at: mount)
            try? fm.removeItem(at: dmg)
        }
        let items = try fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
        guard let newApp = items.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError("W pliku .dmg nie ma aplikacji.")
        }
        let staged = target.deletingLastPathComponent().appendingPathComponent(".LaunchpadClassic-update.app")
        try? fm.removeItem(at: staged)
        try run("/usr/bin/ditto", [newApp.path, staged.path])
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        try fm.removeItem(at: target)
        try fm.moveItem(at: staged, to: target)
    }

    @discardableResult
    nonisolated private static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else {
            throw UpdateError("\((tool as NSString).lastPathComponent) zakończył się błędem: \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return out
    }

    private static func relaunch(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? p.run()
        NSApp.terminate(nil)
    }
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// GitHub przekierowuje pobieranie pliku na serwer z podpisanym adresem – nagłówka Authorization nie wolno tam wysyłać.
final class RedirectStripper: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        var r = request
        r.setValue(nil, forHTTPHeaderField: "Authorization")
        completionHandler(r)
    }
}
