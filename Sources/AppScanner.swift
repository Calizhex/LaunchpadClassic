import AppKit
import CoreImage

struct AppInfo: Sendable, Hashable {
    let id: String          // ścieżka do bundla (po rozwiązaniu dowiązań)
    let url: URL
    let name: String        // zlokalizowana nazwa, np. „Kalkulator”
    let bundleID: String?
    let category: String?
    let isSystem: Bool
    let isUtility: Bool
}

enum AppScanner {
    /// Przeszukuje te same miejsca co klasyczny Launchpad.
    static func scan() -> [AppInfo] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let roots: [(String, Int)] = [
            ("/Applications", 2),
            ("/System/Applications", 1),
            (home + "/Applications", 2),
        ]
        let ownID = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var result: [AppInfo] = []

        func add(_ url: URL) {
            let resolved = url.resolvingSymlinksInPath()
            let path = resolved.path
            guard seen.insert(path).inserted else { return }
            let info = Bundle(url: resolved)?.infoDictionary ?? [:]
            if let bg = info["LSBackgroundOnly"] as? Bool, bg { return }
            if let bg = info["LSBackgroundOnly"] as? String, bg == "1" || bg.lowercased() == "yes" { return }
            let bundleID = info["CFBundleIdentifier"] as? String
            if let bundleID, bundleID == ownID { return }
            var name = fm.displayName(atPath: path)
            if name.lowercased().hasSuffix(".app") { name = String(name.dropLast(4)) }
            let isSystem = path.hasPrefix("/System/") || (bundleID?.hasPrefix("com.apple.") ?? false)
            result.append(AppInfo(id: path,
                                  url: resolved,
                                  name: name,
                                  bundleID: bundleID,
                                  category: info["LSApplicationCategoryType"] as? String,
                                  isSystem: isSystem,
                                  isUtility: path.contains("/Utilities/")))
        }

        func visit(_ dir: URL, depth: Int) {
            guard let items = try? fm.contentsOfDirectory(at: dir,
                                                          includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                                                          options: [.skipsHiddenFiles]) else { return }
            for u in items {
                if u.pathExtension.lowercased() == "app" {
                    add(u)
                    continue
                }
                guard depth > 0 else { continue }
                let values = try? u.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                if values?.isDirectory == true && values?.isPackage != true {
                    visit(u, depth: depth - 1)
                }
            }
        }

        for (root, depth) in roots {
            visit(URL(fileURLWithPath: root, isDirectory: true), depth: depth)
        }
        return result
    }

    /// Polskie nazwy folderów tworzonych przez upuszczenie ikony na ikonę (jak w Launchpadzie).
    static func categoryName(_ raw: String) -> String? {
        let key = raw.replacingOccurrences(of: "public.app-category.", with: "")
        if key == "games" || key.hasSuffix("-games") { return "Gry" }
        let map: [String: String] = [
            "productivity": "Produktywność",
            "developer-tools": "Narzędzia dla programistów",
            "utilities": "Narzędzia",
            "graphics-design": "Grafika i projektowanie",
            "photography": "Fotografia",
            "video": "Wideo",
            "music": "Muzyka",
            "entertainment": "Rozrywka",
            "social-networking": "Sieci społecznościowe",
            "business": "Biznes",
            "finance": "Finanse",
            "education": "Edukacja",
            "reference": "Informacje",
            "news": "Wiadomości",
            "lifestyle": "Styl życia",
            "healthcare-fitness": "Zdrowie i fitness",
            "medical": "Medycyna",
            "travel": "Podróże",
            "sports": "Sport",
            "weather": "Pogoda",
        ]
        return map[key]
    }
}

@MainActor
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }

    func purge() { cache.removeAll() }
}

enum Wallpaper {
    /// Rozmyta tapeta – tło jak w klasycznym Launchpadzie.
    static func blurred(url: URL) -> CGImage? {
        guard var image = CIImage(contentsOf: url) else { return nil }
        let w = image.extent.width
        guard w > 0, w.isFinite else { return nil }
        let scale = min(1, 1400 / w)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = image.extent
        let out = image.clampedToExtent()
            .applyingGaussianBlur(sigma: 26)
            .cropped(to: extent)
        return CIContext(options: nil).createCGImage(out, from: extent)
    }
}
