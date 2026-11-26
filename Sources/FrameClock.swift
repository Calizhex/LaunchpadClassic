import AppKit
import QuartzCore

/// Zegar animacji napędzany przez CADisplayLink ekranu, na którym jest nakładka.
/// ProMotion → do 120 Hz, MacBook Air / zwykły monitor → 60 Hz, monitor 144 Hz → 144 Hz.
/// W trybie niskiego zużycia energii ograniczamy się do 60 Hz.
@MainActor
final class FrameClock: ObservableObject {
    /// Czas dla „trzęsienia” ikon – publikowany tylko w trybie edycji.
    @Published private(set) var time: Double = 0
    /// Zmierzona liczba klatek na sekundę – publikowana tylko, gdy licznik jest włączony.
    @Published private(set) var fps: Int = 0
    @Published private(set) var screenMaxFPS: Int = 60
    @Published private(set) var targetFPS: Int = 60
    @Published var showCounter: Bool = Preferences.showFPS {
        didSet { Preferences.showFPS = showCounter }
    }

    private var frameCount = 0
    private var windowStart: CFTimeInterval = 0

    var isLowPowerMode: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
    var isHighRefresh: Bool { screenMaxFPS > 60 }

    /// Ustala docelową częstotliwość dla danego ekranu.
    func configure(for screen: NSScreen) -> CAFrameRateRange {
        let maxFPS = max(screen.maximumFramesPerSecond, 30)
        screenMaxFPS = maxFPS
        let target = isLowPowerMode ? min(maxFPS, 60) : maxFPS
        targetFPS = target
        let minimum = Float(min(target, 60))
        return CAFrameRateRange(minimum: minimum, maximum: Float(target), preferred: Float(target))
    }

    func frame(timestamp: CFTimeInterval, animating: Bool) {
        if animating { time = timestamp }
        frameCount += 1
        if windowStart == 0 { windowStart = timestamp }
        let elapsed = timestamp - windowStart
        if elapsed >= 0.5 {
            let measured = Int((Double(frameCount) / elapsed).rounded())
            frameCount = 0
            windowStart = timestamp
            if showCounter && measured != fps { fps = measured }
        }
    }

    func reset() {
        frameCount = 0
        windowStart = 0
    }
}

/// Pozycja przeciąganej ikony w osobnym obiekcie – ruch myszy przerysowuje tylko tę ikonę,
/// a nie całą siatkę.
@MainActor
final class DragLayer: ObservableObject {
    @Published var position: CGPoint = .zero
}
