import Foundation

final class TelemetryManager {
    static let shared = TelemetryManager()

    private let queue = DispatchQueue(label: "telemetry.queue")
    private let deviceIdKey = "telemetry_device_id"
    private let bufferKey = "telemetry_buffer"
    private let appStartUptime: TimeInterval
    private var fcpRecorded = false
    private var lcpRecorded = false
    private var ttiRecorded = false
    private var sessionStartUptime: TimeInterval?

    private(set) var deviceId: String
    private(set) var sessionId: String
    private var events: [TelemetryEvent] = []

    private init() {
        appStartUptime = ProcessInfo.processInfo.systemUptime
        if let existing = UserDefaults.standard.string(forKey: deviceIdKey) {
            deviceId = existing
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: deviceIdKey)
            deviceId = newId
        }
        sessionId = UUID().uuidString
        events = loadBuffer()
    }

    func startSession() {
        sessionId = UUID().uuidString
        sessionStartUptime = ProcessInfo.processInfo.systemUptime
        track(event: "session_start")
    }

    func endSession() {
        guard let start = sessionStartUptime else { return }
        let duration = (ProcessInfo.processInfo.systemUptime - start) * 1000
        trackMetric(name: "session_duration_ms", value: duration)
        track(event: "session_end")
        sessionStartUptime = nil
        persistBuffer()
    }

    func markFCP(screen: String) {
        guard !fcpRecorded else { return }
        fcpRecorded = true
        let value = (ProcessInfo.processInfo.systemUptime - appStartUptime) * 1000
        trackMetric(name: "fcp_ms", value: value, properties: ["screen": screen])
    }

    func markLCP(screen: String) {
        guard !lcpRecorded else { return }
        lcpRecorded = true
        let value = (ProcessInfo.processInfo.systemUptime - appStartUptime) * 1000
        trackMetric(name: "lcp_ms", value: value, properties: ["screen": screen])
    }

    func markTTI() {
        guard !ttiRecorded else { return }
        ttiRecorded = true
        let value = (ProcessInfo.processInfo.systemUptime - appStartUptime) * 1000
        trackMetric(name: "tti_ms", value: value)
    }

    func track(event: String, properties: [String: String] = [:]) {
        let payload = TelemetryEvent(
            id: UUID().uuidString,
            name: event,
            timestamp: Date().timeIntervalSince1970,
            sessionId: sessionId,
            deviceId: deviceId,
            properties: properties
        )
        queue.async {
            self.events.append(payload)
            if self.events.count >= 50 {
                self.persistBuffer()
            }
        }
    }

    func trackMetric(name: String, value: Double, properties: [String: String] = [:]) {
        var props = properties
        props["value"] = String(format: "%.2f", value)
        track(event: name, properties: props)
    }

    private func persistBuffer() {
        let current = events
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: bufferKey)
        }
    }

    private func loadBuffer() -> [TelemetryEvent] {
        guard let data = UserDefaults.standard.data(forKey: bufferKey),
              let decoded = try? JSONDecoder().decode([TelemetryEvent].self, from: data) else {
            return []
        }
        return decoded
    }
}

struct TelemetryEvent: Codable {
    let id: String
    let name: String
    let timestamp: TimeInterval
    let sessionId: String
    let deviceId: String
    let properties: [String: String]
}

final class ExperimentManager {
    static let shared = ExperimentManager()
    private let keyPrefix = "exp_variant_"

    func variant(for key: String, rollout: Double, variants: [String], userId: Int?) -> String {
        let storageKey = keyPrefix + key
        if let stored = UserDefaults.standard.string(forKey: storageKey) {
            return stored
        }
        let seed = "\(key)|\(userId ?? 0)|\(TelemetryManager.shared.deviceId)"
        let bucket = Double(stableHash(seed) % 10000) / 10000.0
        let chosen: String
        if bucket >= rollout {
            chosen = "control"
        } else {
            let normalized = bucket / max(rollout, 0.0001)
            let index = min(Int(normalized * Double(variants.count)), variants.count - 1)
            chosen = variants[index]
        }
        UserDefaults.standard.set(chosen, forKey: storageKey)
        TelemetryManager.shared.track(event: "experiment_exposure", properties: [
            "key": key,
            "variant": chosen
        ])
        return chosen
    }

    func isEnabled(key: String, rollout: Double, userId: Int?) -> Bool {
        variant(for: key, rollout: rollout, variants: ["enabled"], userId: userId) == "enabled"
    }

    private func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return hash
    }
}
