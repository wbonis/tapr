import Foundation
import CSensor
import TaprCore

final class SensorReader {
    private var handle: OpaquePointer?
    var onSample: ((Int, Double, Vector3) -> Void)?
    var message: String { handle.map { String(cString: tapr_sensor_message($0)) } ?? "Cannot allocate sensor reader" }
    init() {
        handle = tapr_sensor_create({ context, kind, time, x, y, z in
            guard let context else { return }
            let reader = Unmanaged<SensorReader>.fromOpaque(context).takeUnretainedValue()
            reader.onSample?(Int(kind), time, Vector3(x, y, z))
        }, Unmanaged.passUnretained(self).toOpaque())
    }
    func start() -> Bool { handle.map { tapr_sensor_start($0) != 0 } ?? false }
    func stop() { if let handle { tapr_sensor_stop(handle) } }
    deinit { if let handle { tapr_sensor_destroy(handle) } }
}
