// Menu bar panel, detachable window and setup window.
import SwiftUI

struct Row: View {
  let title: String
  @Binding var v: Double
  let range: ClosedRange<Double>
  let step: Double
  let unit: String
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack {
        Text(title); Spacer()
        Button("−") { v = max(range.lowerBound, v - step) }.buttonStyle(.borderless)
        Text(String(format: "%.1f", v) + " " + unit).monospacedDigit().frame(width: 74, alignment: .trailing)
        Button("+") { v = min(range.upperBound, v + step) }.buttonStyle(.borderless)
      }
      Slider(value: $v, in: range, step: step).controlSize(.small)
    }
  }
}

struct Panel: View {
  @ObservedObject var m: Model
  var detached = false
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Toggle("syncR on", isOn: Binding(get: { m.active }, set: { m.setActive($0) })).toggleStyle(.switch)
        Spacer()
        Toggle("Mute", isOn: $m.p.muted).toggleStyle(.button)
        Button { m.refreshDevices(); openWindow(id: "setup"); NSApp.activate(ignoringOtherApps: true) } label: {
          Image(systemName: "gearshape") }.buttonStyle(.borderless).help("Setup")
        if !detached {
          Button { openWindow(id: "panel"); NSApp.activate(ignoringOtherApps: true) } label: {
            Image(systemName: "macwindow.on.rectangle") }.buttonStyle(.borderless).help("Open as window")
        }
      }
      if m.status != "on" && m.status != "off" {
        Text(m.status).font(.caption).foregroundStyle(.orange)
      }
      GroupBox {
        Row(title: "Master Volume", v: $m.p.masterDB, range: -60...12, step: 0.5, unit: "dB")
        Row(title: "\(m.mainName) Volume", v: $m.p.mainDB, range: -30...12, step: 0.5, unit: "dB")
        Row(title: "\(m.secondName) Volume", v: $m.p.secondDB, range: -30...12, step: 0.5, unit: "dB")
        HStack { Spacer(); Button("Reset") { m.p.masterDB = 0; m.p.mainDB = 0; m.p.secondDB = 0 }.controlSize(.small) }
      }
      GroupBox {
        HStack(spacing: 6) {
          ForEach([-1.0, -0.1], id: \.self) { s in Button(s == -1 ? "−1" : "−0.1") { m.p.delayMs = max(-300, m.p.delayMs + s) } }
          Spacer()
          VStack(spacing: 0) {
            Text(String(format: "%.1f ms", abs(m.p.delayMs))).font(.title3).monospacedDigit()
            Text("\(m.p.delayMs >= 0 ? m.secondName : m.mainName) delay").font(.caption2).foregroundStyle(.secondary)
          }
          Spacer()
          ForEach([0.1, 1.0], id: \.self) { s in Button(s == 1 ? "+1" : "+0.1") { m.p.delayMs = min(300, m.p.delayMs + s) } }
        }
        HStack { Spacer(); Button("Reset") { m.p.delayMs = m.calibratedDelay }.controlSize(.small).help("Back to the measured value") }
      }
      GroupBox {
        HStack { Toggle("Simple EQ", isOn: $m.p.eqOn).toggleStyle(.checkbox); Spacer() }
        Group {
          Text(m.mainName).font(.caption.bold())
          Row(title: "Bass", v: $m.p.mainLow, range: -12...12, step: 0.5, unit: "dB")
          Row(title: "Mid", v: $m.p.mainMid, range: -12...12, step: 0.5, unit: "dB")
          Row(title: "Treble", v: $m.p.mainHigh, range: -12...12, step: 0.5, unit: "dB")
          Text(m.secondName).font(.caption.bold()).padding(.top, 4)
          Row(title: "Bass", v: $m.p.secondLow, range: -12...12, step: 0.5, unit: "dB")
          Row(title: "Mid", v: $m.p.secondMid, range: -12...12, step: 0.5, unit: "dB")
          Row(title: "Treble", v: $m.p.secondHigh, range: -12...12, step: 0.5, unit: "dB")
        }.disabled(!m.p.eqOn).opacity(m.p.eqOn ? 1 : 0.4)
        HStack { Spacer()
          Button("Reset") { m.p.mainLow = 0; m.p.mainMid = 0; m.p.mainHigh = 0; m.p.secondLow = 0; m.p.secondMid = 0; m.p.secondHigh = 0 }
            .controlSize(.small) }
      }
      HStack { Spacer(); Button("Quit") { m.setActive(false); NSApp.terminate(nil) } }
    }
    .padding(14).frame(width: 340)
  }
}

struct SetupView: View {
  @ObservedObject var m: Model
  var body: some View {
    Form {
      Section {
        Picker("Main device", selection: $m.mainUID) {
          Text("–").tag("")
          ForEach(m.outputs) { Text($0.name).tag($0.uid) }
        }
        Text("Becomes the system output. Keyboard, menu bar and its own buttons control the volume of both devices.")
          .font(.caption).foregroundStyle(.secondary)
        Picker("Second device", selection: $m.secondUID) {
          Text("–").tag("")
          ForEach(m.outputs.filter { $0.uid != m.mainUID }) { Text($0.name).tag($0.uid) }
        }
      }
      Section {
        Picker("Measurement mic", selection: $m.micUID) {
          Text("–").tag("")
          ForEach(m.inputs) { Text($0.name).tag($0.uid) }
        }
        HStack {
          Button(m.calibrating ? "Measuring …" : "Measure delay") { m.calibrate() }
            .disabled(m.calibrating || m.mainUID.isEmpty || m.secondUID.isEmpty || m.micUID.isEmpty)
          Text(m.calibration).font(.caption).foregroundStyle(.secondary)
        }
        Text("Pause all audio, set a moderate volume and place the mic where you listen. syncR plays short clicks on both devices and sets the delay.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section {
        Toggle("Launch at login", isOn: Binding(get: { m.launchAtLogin }, set: { m.setLaunchAtLogin($0) }))
      }
    }
    .formStyle(.grouped)
    .frame(width: 440)
  }
}

@main
struct SyncRApp: App {
  @StateObject private var m = Model()
  var body: some Scene {
    MenuBarExtra { Panel(m: m) } label: { Image(systemName: m.active ? "hifispeaker.2.fill" : "hifispeaker.2") }
      .menuBarExtraStyle(.window)
    Window("syncR", id: "panel") { Panel(m: m, detached: true) }
      .windowResizability(.contentSize).windowLevel(.floating).defaultLaunchBehavior(.suppressed)
    Window("syncR Setup", id: "setup") { SetupView(m: m) }
      .windowResizability(.contentSize).defaultLaunchBehavior(.suppressed)
  }
}
