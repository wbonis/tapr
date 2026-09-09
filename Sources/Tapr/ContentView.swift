import AppKit
import SwiftUI
import TaprCore

struct ContentView: View {
    @ObservedObject var model: TaprModel
    private let accent = Color(red: 0.23, green: 0.66, blue: 0.54)
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("A little tap. A useful action.").font(.system(size: 27, weight: .semibold, design: .rounded))
                            Text("Tap gently on the palm rest beside your trackpad.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("PROOF OF CONCEPT").font(.system(size: 9, weight: .bold)).tracking(1.2)
                            .padding(8).background(accent.opacity(0.12), in: Capsule())
                    }
                    signalCard
                    mappingCard
                    tuningCard
                    if model.splitSides { calibrationCard }
                    HStack {
                        Image(systemName: model.accessibility ? "checkmark.shield" : "keyboard")
                        Text(model.accessibility ? "Keyboard & media controls are permitted" : "Keyboard & media actions need Accessibility access")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if !model.accessibility { Button("Enable…", action: ActionRunner.requestAccessibility) }
                    }
                    Text("Experimental sensor support. Side recognition needs calibration and may vary with desk position. Tapr keeps settings on this Mac.")
                        .font(.caption).foregroundStyle(.tertiary)
                }.padding(28)
            }.background(Color(nsColor: .windowBackgroundColor))
        }.frame(minWidth: 900, minHeight: 700)
        .tint(accent)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path").font(.title).foregroundStyle(accent)
                Text("tapr").font(.system(size: 32, weight: .bold, design: .rounded))
            }.padding(.top, 10)
            VStack(alignment: .leading, spacing: 10) {
                Label(model.listening ? "Listening" : "Paused", systemImage: model.listening ? "dot.radiowaves.left.and.right" : "pause.circle")
                    .font(.headline)
                Text(model.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(model.listening ? "Pause sensor" : "Start listening") {
                    if model.listening { model.stop() } else { model.start() }
                }.controlSize(.large)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable actions", isOn: $model.armed)
                    .toggleStyle(.switch)
                    .disabled(!model.listening || model.sampleRate == 0 || model.calibrationSide != nil || (model.splitSides && !model.calibration.isReady))
                Text(model.armed ? "Recognized taps run your actions." : "Watch your taps first. Enable actions when detection feels right.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Text("TRY THE INTERFACE").font(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(.secondary)
                HStack { ForEach(1...3, id: \.self) { count in Button("\(count)×") { model.simulate(count) } } }
                Text("Demo buttons show feedback only.").font(.caption2).foregroundStyle(.tertiary)
            }
            Divider()
            Text("Native macOS · Local settings").font(.caption2).foregroundStyle(.secondary)
        }.padding(22).frame(width: 190).frame(maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))
    }
    private var signalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Live motion", systemImage: "waveform.path.ecg").font(.headline)
                Spacer()
                Text("\(model.sampleRate) samples/s").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button("Show log") { NSWorkspace.shared.activateFileViewerSelecting([Diagnostics.shared.fileURL]) }
                    .controlSize(.small)
            }
            SignalGraph(values: model.trace, threshold: model.effectiveThreshold).frame(height: 88)
                .background(accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.lastGesture).font(.system(.body, design: .rounded).weight(.medium))
                    Text(model.lastAction).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Text(String(format: "%.3f g · noise %.3f g", model.level, model.noiseFloor))
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
        }.card()
    }
    private var mappingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your tap actions").font(.headline)
                Spacer()
                Toggle("Separate left / right", isOn: $model.splitSides).toggleStyle(.switch).controlSize(.small)
            }
            let sides: [TapSide] = model.splitSides ? [.left, .right] : [.any]
            ForEach(sides, id: \.self) { side in
                if model.splitSides { Text(side.label.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                ForEach(1...3, id: \.self) { count in
                    ActionRow(model: model, key: "\(side.rawValue)-\(count)", count: count)
                    if count < 3 { Divider() }
                }
            }
            if model.splitSides && !model.calibration.isReady {
                Label("Calibrate both sides below before enabling actions.", systemImage: "hand.tap")
                    .font(.caption).foregroundStyle(.orange)
            }
        }.card()
    }
    private var tuningCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Make it feel right").font(.headline)
            HStack {
                Text("Tap strength").frame(width: 110, alignment: .leading)
                Text("Gentle").font(.caption).foregroundStyle(.secondary)
                Slider(value: $model.threshold, in: 0.01...0.3)
                Text("Firm").font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%.3f g", model.threshold)).font(.caption.monospacedDigit()).frame(width: 60)
            }
            HStack {
                Text("Time between taps").font(.caption).frame(width: 110, alignment: .leading)
                Slider(value: $model.tapInterval, in: 0.25...0.65)
                Text("\(Int(model.tapInterval*1000)) ms").font(.caption.monospacedDigit()).frame(width: 60)
            }
            Text("The dashed trigger line rises by itself above a noisy desk. Singles and doubles run after this quiet interval; a triple runs at once.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Ignore taps while typing", isOn: $model.ignoreTyping).toggleStyle(.switch).controlSize(.small)
            Text(model.ignoreTyping && !model.accessibility
                 ? "Key presses are only visible with Accessibility access. Bursts of six or more impacts are ignored either way."
                 : "Impacts within 180 ms of a key press and bursts of six or more impacts are ignored. Only the time of a key press is used.")
                .font(.caption).foregroundStyle(model.ignoreTyping && !model.accessibility ? .orange : .secondary)
        }.card()
    }
    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Teach Tapr left and right").font(.headline)
            Text("Keep the Mac still on a desk. Learn eight gentle taps on each side, one second apart. Actions stay disarmed during learning. Relearning once also teaches the lateral direction of each side. If the sides remain uncertain, use unified taps.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Learn left (\(model.calibration.left.count)/\(SideCalibration.requiredSamples))") { model.beginCalibration(.left) }
                Button("Learn right (\(model.calibration.right.count)/\(SideCalibration.requiredSamples))") { model.beginCalibration(.right) }
                if model.calibrationSide != nil { Button("Cancel") { model.cancelCalibration() } }
            }.disabled(!model.listening)
            if model.calibration.isReady {
                Label("Calibration saved. Test both sides with actions disarmed.", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
            } else if model.calibration.left.count >= SideCalibration.requiredSamples && model.calibration.right.count >= SideCalibration.requiredSamples {
                Text("These samples are too similar. Relearn each side, or turn off separate sides.").font(.caption).foregroundStyle(.orange)
            }
        }.card()
    }
}
private struct ActionRow: View {
    @ObservedObject var model: TaprModel
    let key: String
    let count: Int
    private var selected: ActionBinding { model.binding(for: key) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("\(count)×").font(.system(size: 18, weight: .semibold, design: .rounded))
                    .frame(width: 38, height: 34).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                Text(count == 1 ? "Single tap" : count == 2 ? "Double tap" : "Triple tap").frame(width: 88, alignment: .leading)
                Picker("Action", selection: Binding(get: { selected.kind }, set: { kind in
                    var binding = selected; binding.kind = kind; model.setBinding(binding, for: key)
                })) {
                    ForEach(ActionKind.allCases) { kind in Text(kind.title).tag(kind) }
                }.labelsHidden()
                Button { model.run(selected) } label: { Image(systemName: "play.fill") }
                    .help("Run this action now, even while actions are disarmed. Keyboard actions target the focused app.")
            }
            if selected.kind.needsValue {
                HStack {
                    TextField(selected.kind.placeholder, text: Binding(get: { selected.value }, set: { value in
                        var binding = selected; binding.value = value; model.setBinding(binding, for: key)
                    })).textFieldStyle(.roundedBorder)
                    if selected.kind == .application {
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = true; panel.canChooseDirectories = false
                            panel.allowedContentTypes = [.application]
                            panel.directoryURL = URL(fileURLWithPath: "/Applications")
                            if panel.runModal() == .OK, let url = panel.url {
                                var binding = selected; binding.value = url.path; model.setBinding(binding, for: key)
                            }
                        }
                    }
                }.padding(.leading, 50)
            }
        }
    }
}
private struct SignalGraph: View {
    var values: [Double]
    var threshold: Double
    var body: some View {
        Canvas { context, size in
            let ceiling = max(threshold * 2.5, values.max() ?? 0, 0.06)
            let height = size.height - 12
            let y = 6 + height * (1 - threshold / ceiling)
            var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(.orange.opacity(0.65)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            var path = Path()
            for (i, value) in values.enumerated() {
                let point = CGPoint(x: size.width * Double(i) / Double(max(1, values.count-1)), y: 6 + height * (1 - min(value / ceiling, 1)))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(Color(red: 0.23, green: 0.66, blue: 0.54)), lineWidth: 1.8)
        }.accessibilityLabel("Live motion graph. Dashed line shows the tap threshold.")
    }
}
private extension View {
    func card() -> some View {
        padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.06)))
    }
}
