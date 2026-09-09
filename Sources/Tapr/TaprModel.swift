import AppKit
import Combine
import TaprCore

final class TaprModel: ObservableObject {
    @Published var listening = false
    @Published var armed = false { didSet {
        sequence.reset()
        if oldValue != armed { Diagnostics.shared.record("armed", ["enabled": armed]) }
    } }
    @Published var splitSides = false { didSet { armed = false; calibrationSide = nil; sequence.reset(); persist() } }
    @Published var threshold: Double = 0.045 { didSet { detector.threshold = threshold; sequence.reset(); persist() } }
    @Published var tapInterval: Double = 0.38 { didSet { sequence.interval = tapInterval; sequence.reset(); persist() } }
    @Published var ignoreTyping = true { didSet { updateKeyboardMonitor(); persist() } }
    @Published var noiseFloor: Double = 0
    @Published var effectiveThreshold: Double = 0
    @Published var bindings: [String: ActionBinding] = [:] { didSet { sequence.reset(); persist() } }
    @Published var calibration = SideCalibration() { didSet { sequence.reset(); persist() } }
    @Published var calibrationSide: TapSide?
    @Published var calibrationCount = 0
    @Published var status = "Stopped"
    @Published var lastGesture = "Tap gently beside the trackpad"
    @Published var lastAction = "Actions are disarmed"
    @Published var history: [String] = []
    @Published var trace: [Double] = Array(repeating: 0, count: 160)
    @Published var level: Double = 0
    @Published var sampleRate = 0
    @Published var accessibility = false
    @Published var stationary = false
    private let sensor = SensorReader()
    private let capture = ImpactCapture()
    private let keyboard = KeyboardActivity()
    private var typingGuard = TypingGuard()
    private var detector = ImpactDetector()
    private var sequence = TapSequence()
    private var motionGate = MotionGate()
    private var gyro = Vector3()
    private var gyroTime: Double = 0
    private var timer: Timer?
    private var lastSample: Double = 0
    private var latestSensorTime: Double = 0
    private var lastDisplay: Double = 0
    private var lastRate: Double = 0
    private var samples = 0
    private var gyroSamples = 0
    private var maxSensorGap = 0.0
    private var maxSensorDelay = 0.0
    private var healthPeak = 0.0
    private var healthGyroPeak = 0.0
    private var displayPeak: Double = 0
    private var calibrationStart: Double = 0
    private var calibrationLastTap: Double = 0
    private var startedAt: Double = 0
    private var loading = true
    private var actionRunning = false
    private var lastExecution: Double = 0
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var resumeAfterWake = false

    private struct Settings: Codable {
        var threshold: Double
        var interval: Double
        var splitSides: Bool
        var bindings: [String: ActionBinding]
        var calibration: SideCalibration
        var ignoreTyping: Bool?
    }
    init() {
        if let data = UserDefaults.standard.data(forKey: "tapr.settings.v1"), let saved = try? JSONDecoder().decode(Settings.self, from: data) {
            threshold = min(0.3, max(0.01, saved.threshold))
            tapInterval = min(0.65, max(0.25, saved.interval))
            splitSides = saved.splitSides
            ignoreTyping = saved.ignoreTyping ?? true
            bindings = saved.bindings
            if saved.calibration.signatureVersion == 2 {
                calibration = saved.calibration
            } else {
                lastGesture = "Updated side detection — please relearn left and right."
            }
        }
        detector.threshold = threshold
        sequence.interval = tapInterval
        loading = false
        Diagnostics.shared.record("launch", ["version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            "threshold": threshold, "interval": tapInterval, "split_sides": splitSides, "ignore_typing": ignoreTyping,
            "left_samples": calibration.left.count, "right_samples": calibration.right.count,
            "calibration_ready": calibration.isReady])
        sensor.onSample = { [weak self] kind, time, value in self?.sample(kind: kind, time: time, value: value) }
        timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Diagnostics.shared.record("sleep", ["listening": self.listening])
            self.resumeAfterWake = self.listening
            self.stop()
        }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Diagnostics.shared.record("wake", ["resume": self.resumeAfterWake])
            if self.resumeAfterWake { self.start() }
            self.resumeAfterWake = false
        }
    }
    func start() {
        detector.reset(); sequence.reset(); motionGate.reset(); capture.reset(); typingGuard.reset(); stationary = false; gyro = .init(); gyroTime = 0
        samples = 0; sampleRate = 0; lastSample = 0; latestSensorTime = 0; displayPeak = 0
        gyroSamples = 0; maxSensorGap = 0; maxSensorDelay = 0; healthPeak = 0; healthGyroPeak = 0
        startedAt = ProcessInfo.processInfo.systemUptime
        lastRate = startedAt
        listening = sensor.start()
        updateKeyboardMonitor()
        status = sensor.message
        Diagnostics.shared.record("sensor_start", ["opened": listening, "message": status])
    }
    func stop() {
        Diagnostics.shared.record("sensor_stop")
        sensor.stop()
        keyboard.stop()
        listening = false; armed = false; calibrationSide = nil
        detector.reset(); sequence.reset(); motionGate.reset(); stationary = false; sampleRate = 0
        status = "Paused"
    }
    func shutdown() { stop(); timer?.invalidate(); Diagnostics.shared.flush() }
    private func sample(kind: Int, time: Double, value: Vector3) {
        guard listening else { return }
        if kind == 9 { gyro = value; gyroTime = time; gyroSamples += 1; healthGyroPeak = max(healthGyroPeak, value.magnitude); return }
        guard kind == 3 else { return }
        guard time > latestSensorTime else { return }
        if latestSensorTime > 0 { maxSensorGap = max(maxSensorGap, time-latestSensorTime) }
        latestSensorTime = time
        lastSample = ProcessInfo.processInfo.systemUptime
        maxSensorDelay = max(maxSensorDelay, lastSample-time)
        samples += 1
        let recentGyro = abs(time-gyroTime) < 0.05 ? gyro : .init()
        if let window = capture.push(time: time, acceleration: value, gyro: recentGyro) { Diagnostics.shared.recordImpact(window) }
        let settled = motionGate.ingest(time: time, acceleration: value, gyro: recentGyro)
        if stationary != settled {
            Diagnostics.shared.record("motion_gate", ["settled": settled, "reason": motionGate.reason,
                "rotation_dps": motionGate.rotationRate, "translation_g": motionGate.translationLevel,
                "cancelled_taps": sequence.pendingCount, "cancelled_impact": detector.hasPendingImpact])
            stationary = settled
        }
        let impact = detector.ingest(time: time, acceleration: value, gyro: recentGyro)
        displayPeak = max(displayPeak, detector.level)
        healthPeak = max(healthPeak, detector.level)
        guard settled else {
            sequence.reset()
            detector.suppress()
            return
        }
        if let impact { receive(impact) }
    }
    private func receive(_ impact: Impact) {
        if let side = calibrationSide {
            guard impact.time >= calibrationStart, impact.time - calibrationLastTap > 0.65 else {
                Diagnostics.shared.record("calibration_skip", ["reason": "countdown_or_spacing", "strength_g": impact.strength])
                return
            }
            calibrationLastTap = impact.time
            capture.schedule(onset: impact.time, fields: ["label": side.rawValue, "strength_g": impact.strength, "signature": impact.signature])
            if side == .left { calibration.left.append(impact.signature); calibrationCount = calibration.left.count }
            else { calibration.right.append(impact.signature); calibrationCount = calibration.right.count }
            Diagnostics.shared.record("calibration_sample", ["side": side.rawValue, "count": calibrationCount,
                "strength_g": impact.strength, "signature": impact.signature, "ready": calibration.isReady])
            lastGesture = "Learned \(side.label.lowercased()) tap \(calibrationCount) of \(SideCalibration.requiredSamples)"
            if calibrationCount >= SideCalibration.requiredSamples {
                calibrationSide = nil
                lastGesture = "\(side.label) learned. \(calibration.isReady ? "Both sides are ready to try." : "Learn the other side or retry if the samples overlap.")"
            }
            return
        }
        let measured: [String: Any] = ["strength_g": impact.strength, "snr": impact.snr, "noise_g": impact.noise,
            "attack_x_g": impact.attackX, "attack_z_g": impact.attackZ, "signature": impact.signature, "threshold": threshold]
        if let reason = rejection(for: impact) {
            Diagnostics.shared.record("tap_rejected", measured.merging(["sensor_time": impact.time, "reason": reason]) { $1 })
            capture.schedule(onset: impact.time, fields: measured.merging(["label": "rejected", "reason": reason]) { $1 })
            if reason == "typing_burst" { sequence.reset() }
            lastGesture = "Ignored · \(reason.replacingOccurrences(of: "_", with: " "))"
            return
        }
        let assessment = splitSides ? calibration.assess(impact.signature) : nil
        let evidence: TapEvidence = assessment.map { .side(vote: $0.vote) } ?? .unified
        let fields = measured.merging(["side": assessment?.side?.rawValue ?? (splitSides ? "unknown" : "any"),
            "vote": assessment?.vote ?? 0, "reason": assessment?.reason ?? "unified"]) { $1 }
        Diagnostics.shared.record("tap", fields.merging(["sensor_time": impact.time]) { $1 })
        capture.schedule(onset: impact.time, fields: fields.merging(["label": "none"]) { $1 })
        if let assessment { lastGesture = Self.describe(assessment) }
        // Hardware timestamps and systemUptime both use the monotonic awake-time clock.
        if let gesture = sequence.register(evidence, at: impact.time) { recognized(gesture) }
        if let drop = sequence.lastDrop {
            Diagnostics.shared.record("tap_rejected", ["sensor_time": impact.time, "reason": drop, "strength_g": impact.strength])
        }
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastRate >= 1 { accessibility = AXIsProcessTrusted() }
        guard listening else { return }
        if now - lastDisplay >= 0.05 {
            level = displayPeak
            noiseFloor = detector.noiseFloor
            effectiveThreshold = detector.effectiveThreshold
            trace.append(displayPeak)
            if trace.count > 160 { trace.removeFirst(trace.count - 160) }
            displayPeak = 0
            lastDisplay = now
        }
        if now - lastRate >= 1 {
            sampleRate = Int(Double(samples) / (now-lastRate))
            Diagnostics.shared.record("sensor_health", ["accel_hz": sampleRate,
                "gyro_hz": Int(Double(gyroSamples) / (now-lastRate)), "peak_g": healthPeak,
                "gyro_peak_dps": healthGyroPeak, "max_gap_ms": maxSensorGap * 1000,
                "max_delay_ms": maxSensorDelay * 1000, "sample_age_s": lastSample > 0 ? now-lastSample : -1,
                "settled": stationary, "gate_reason": motionGate.reason, "armed": armed,
                "pending_taps": sequence.pendingCount, "threshold": threshold, "noise_g": detector.noiseFloor,
                "trigger_g": detector.effectiveThreshold, "typing_locked": typingGuard.isLocked(at: latestSensorTime)])
            gyroSamples = 0; maxSensorGap = 0; maxSensorDelay = 0; healthPeak = 0; healthGyroPeak = 0
            samples = 0; lastRate = now
        }
        if now - max(lastSample, startedAt) > 2 {
            status = "No sensor samples. Pause and restart; check hardware access."
            sequence.reset()
            armed = false
        } else if lastSample > 0 { status = stationary ? "Live motion sensor" : "Hold the laptop still — taps paused" }
        // Advance gesture deadlines only through samples already processed, so a
        // busy UI cannot expire a sequence ahead of queued sensor reports.
        if stationary, !detector.hasPendingImpact {
            let pendingCount = sequence.pendingCount
            if let gesture = sequence.flush(at: latestSensorTime) { recognized(gesture) }
            else if pendingCount > 0 && sequence.pendingCount == 0 {
                let reason = sequence.lastRejection ?? "unknown"
                Diagnostics.shared.record("sequence_rejected", ["count": pendingCount, "reason": reason])
                lastGesture = "Ignored \(pendingCount)× · \(reason.replacingOccurrences(of: "_", with: " "))"
            }
        }
    }
    private func recognized(_ gesture: Gesture) {
        Diagnostics.shared.record("gesture", ["side": gesture.side.rawValue, "count": gesture.count, "armed": armed])
        let label = "\(gesture.side == .any ? "Tap" : gesture.side.label): \(gesture.count)×"
        lastGesture = label
        history.insert(label, at: 0)
        history = Array(history.prefix(5))
        guard armed else { lastAction = "Detected only · actions disarmed"; return }
        run(binding(for: gesture.key))
    }
    /// Same order as MacTap: SNR, then key presses, then typing bursts. Key presses are
    /// only known while the monitor runs; the burst lockout works without it.
    private func rejection(for impact: Impact) -> String? {
        if impact.snr < 1.6 { return "low_snr" }
        let vertical = abs(impact.attackZ) > abs(impact.attackX) * 3.8 && impact.attackPeakX < 0.006
        return typingGuard.check(time: impact.time, lastKeyTime: ignoreTyping ? keyboard.lastKeyTime : nil, vertical: vertical)
    }
    private func updateKeyboardMonitor() {
        if listening && ignoreTyping { keyboard.start() } else { keyboard.stop() }
    }
    private static func describe(_ assessment: SideCalibration.Assessment) -> String {
        guard let side = assessment.side else { return String(format: "Tap · side uncertain (%+.2f)", assessment.vote) }
        return String(format: "Tap · %@ (%.2f)", side.label.lowercased(), abs(assessment.vote))
    }
    func binding(for key: String) -> ActionBinding { bindings[key] ?? .init() }
    func setBinding(_ binding: ActionBinding, for key: String) { bindings[key] = binding }
    func run(_ binding: ActionBinding) {
        let now = ProcessInfo.processInfo.systemUptime
        guard !actionRunning, now - lastExecution > 0.7 else {
            Diagnostics.shared.record("action_skipped", ["kind": binding.kind.rawValue,
                "reason": actionRunning ? "busy" : "cooldown", "seconds_since_last": now-lastExecution])
            lastAction = "Action already running or cooling down"; return
        }
        Diagnostics.shared.record("action_start", ["kind": binding.kind.rawValue])
        actionRunning = true; lastExecution = now
        lastAction = "Running \(binding.kind.title.lowercased())…"
        ActionRunner.run(binding) { [weak self] message in
            Diagnostics.shared.record("action_finished", ["kind": binding.kind.rawValue])
            self?.lastAction = message
            self?.actionRunning = false
        }
    }
    func beginCalibration(_ side: TapSide) {
        guard listening else { return }
        Diagnostics.shared.record("calibration_start", ["side": side.rawValue])
        armed = false; sequence.reset(); detector.reset()
        calibrationSide = side; calibrationCount = 0
        calibrationStart = ProcessInfo.processInfo.systemUptime + 1.5
        calibrationLastTap = 0
        if side == .left { calibration.left = [] } else { calibration.right = [] }
        lastGesture = "Wait two seconds, then tap the \(side.label.lowercased()) side \(SideCalibration.requiredSamples) times, one second apart."
    }
    func cancelCalibration() { calibrationSide = nil; sequence.reset(); lastGesture = "Calibration cancelled" }
    func simulate(_ count: Int) {
        // UI demonstration never executes an action or contributes calibration data.
        lastGesture = "Demo: \(count)× tap"
        lastAction = "Demo only · no action executed"
    }
    private func persist() {
        guard !loading else { return }
        let settings = Settings(threshold: threshold, interval: tapInterval, splitSides: splitSides, bindings: bindings,
                                calibration: calibration, ignoreTyping: ignoreTyping)
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "tapr.settings.v1") }
    }
    deinit {
        timer?.invalidate()
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
