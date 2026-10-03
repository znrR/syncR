// syncR – menu bar app. Plays all system audio on two output devices in sync,
// with one volume for both (keyboard, menu bar, device buttons).
import SwiftUI
import CoreAudio
import AVFoundation
import ServiceManagement

let logDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/syncR")

@MainActor final class Model: ObservableObject {
  let engine = Engine()
  @Published var p: Params { didSet { engine.update(p); save() } }
  @Published var active = false
  @Published var status = ""
  @Published var mainUID: String { didSet { UserDefaults.standard.set(mainUID, forKey: "mainUID"); restartIfActive() } }
  @Published var secondUID: String { didSet { UserDefaults.standard.set(secondUID, forKey: "secondUID"); restartIfActive() } }
  @Published var micUID: String { didSet { UserDefaults.standard.set(micUID, forKey: "micUID") } }
  @Published var calibratedDelay: Double { didSet { UserDefaults.standard.set(calibratedDelay, forKey: "calibratedDelay") } }
  @Published var calibration = ""
  @Published var calibrating = false
  @Published var remoteMeasurements = false   // allow `syncrctl measure` (uses the microphone)
  @Published var outputs: [AudioDevice] = []
  @Published var inputs: [AudioDevice] = []
  @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
  private var listening = false
  private var meterTimer: Timer?
  private var observers: [NSObjectProtocol] = []

  init() {
    let d = UserDefaults.standard
    var q = Params()
    func r(_ k: String, _ v: inout Double) { if d.object(forKey: k) != nil { v = d.double(forKey: k) } }
    r("masterDB", &q.masterDB); r("mainDB", &q.mainDB); r("secondDB", &q.secondDB); r("delayMs", &q.delayMs)
    r("mainLow", &q.mainLow); r("mainMid", &q.mainMid); r("mainHigh", &q.mainHigh)
    r("secondLow", &q.secondLow); r("secondMid", &q.secondMid); r("secondHigh", &q.secondHigh)
    q.eqOn = d.bool(forKey: "eqOn")
    p = q
    mainUID = d.string(forKey: "mainUID") ?? ""
    secondUID = d.string(forKey: "secondUID") ?? ""
    micUID = d.string(forKey: "micUID") ?? ""
    calibratedDelay = d.object(forKey: "calibratedDelay") != nil ? d.double(forKey: "calibratedDelay") : 0
    engine.update(q)
    refreshDevices()
    setupRemote()
    if d.bool(forKey: "active") && !mainUID.isEmpty && !secondUID.isEmpty { setActive(true) }
    else { status = mainUID.isEmpty || secondUID.isEmpty ? "Choose two devices in Setup" : "off" }
  }

  var mainName: String { outputs.first { $0.uid == mainUID }?.name ?? "Main" }
  var secondName: String { outputs.first { $0.uid == secondUID }?.name ?? "Second" }

  func refreshDevices() {
    outputs = listDevices(input: false)
    inputs = listDevices(input: true)
  }

  func save() {
    let d = UserDefaults.standard
    for (k, v) in [("masterDB", p.masterDB), ("mainDB", p.mainDB), ("secondDB", p.secondDB), ("delayMs", p.delayMs),
                   ("mainLow", p.mainLow), ("mainMid", p.mainMid), ("mainHigh", p.mainHigh),
                   ("secondLow", p.secondLow), ("secondMid", p.secondMid), ("secondHigh", p.secondHigh)] { d.set(v, forKey: k) }
    d.set(p.eqOn, forKey: "eqOn")
    writeState()
  }

  // MARK: on / off

  func setActive(_ on: Bool) {
    if on {
      guard let main = deviceID(forUID: mainUID), let second = deviceID(forUID: secondUID) else {
        status = "Choose two devices in Setup"; active = false; return }
      // The main device becomes the system output: keyboard, menu bar and device buttons control it.
      if defaultOutputDevice() != main { setDefaultOutputDevice(main) }
      // The second device's own volume stays at 100 %; syncR sets its level.
      setHardwareVolumeScalar(second, 1.0)
      attachListeners(main: main, second: second)
      followMain()
      do { try engine.start(mainUID: mainUID, secondUID: secondUID); active = true; status = "on" }
      catch { active = false; status = error.localizedDescription }
    } else {
      engine.stop(); active = false; status = "off"
    }
    UserDefaults.standard.set(active, forKey: "active")
    writeState()
  }

  func restartIfActive() {
    guard active else { return }
    engine.stop(); listening = false
    setActive(true)
  }

  func followMain() {
    guard let d = deviceID(forUID: mainUID), let v = outputVolume(d) else { engine.followGain = 1; return }
    engine.followGain = dbToGain(Double(v.db)); engine.followMute = v.muted
  }

  private func attachListeners(main: AudioObjectID, second: AudioObjectID) {
    guard !listening else { return }
    listening = true
    for el in volumeElements(main) + [0] {
      for sel in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
        var a = addr(sel, kAudioObjectPropertyScopeOutput, el)
        guard AudioObjectHasProperty(main, &a) else { continue }
        AudioObjectAddPropertyListenerBlock(main, &a, .main) { _, _ in MainActor.assumeIsolated { self.followMain() } }
      }
    }
    for el in volumeElements(second) {
      var a = addr(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, el)
      AudioObjectAddPropertyListenerBlock(second, &a, .main) { _, _ in MainActor.assumeIsolated {
        if self.active, let v = hardwareVolumeScalar(second), v < 0.999 { setHardwareVolumeScalar(second, 1.0) } } }
    }
    var dl = addr(kAudioHardwarePropertyDevices)
    AudioObjectAddPropertyListenerBlock(systemObject, &dl, .main) { _, _ in MainActor.assumeIsolated { self.refreshDevices() } }
  }

  // MARK: calibration

  func calibrate() {
    guard !micUID.isEmpty else { calibration = "Choose a measurement microphone first"; return }
    requestMic { ok in
      guard ok else { self.calibration = "Microphone access denied"; return }
      let wasActive = self.active
      if wasActive { self.engine.stop() }
      self.calibrating = true; self.calibration = "Measuring … keep quiet for 8 seconds"
      let (m, s, mic) = (self.mainUID, self.secondUID, self.micUID)
      DispatchQueue.global().async {
        let result = Result { try Calibrator.run(mainUID: m, secondUID: s, micUID: mic) }
        DispatchQueue.main.async { MainActor.assumeIsolated {
          self.calibrating = false
          switch result {
          case .success(let r):
            self.calibratedDelay = (r.delayMs * 10).rounded() / 10
            self.p.delayMs = self.calibratedDelay
            self.calibration = String(format: "%.1f ms (spread %.2f ms, signal %.0f dB)%@", r.delayMs, r.spreadMs, r.snr,
                                      r.reliable ? "" : " – unreliable, try again closer / louder")
          case .failure(let e): self.calibration = e.localizedDescription
          }
          if wasActive { try? self.engine.start(mainUID: m, secondUID: s) }
        } }
      }
    }
  }

  private func requestMic(_ done: @escaping @MainActor (Bool) -> Void) {
    if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { done(true); return }
    AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { MainActor.assumeIsolated { done(ok) } } }
  }

  func setLaunchAtLogin(_ on: Bool) {
    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
    catch { calibration = "Launch at login: \(error.localizedDescription)" }
    launchAtLogin = SMAppService.mainApp.status == .enabled
  }

  // MARK: remote control (syncrctl) and state file

  private func setupRemote() {
    let c = DistributedNotificationCenter.default()
    observers.append(c.addObserver(forName: .init("de.r4sp.syncr.set"), object: nil, queue: .main) { n in
      let json = n.object as? String ?? "{}"; MainActor.assumeIsolated { self.applyRemote(json) } })
    observers.append(c.addObserver(forName: .init("de.r4sp.syncr.measure"), object: nil, queue: .main) { n in
      let arg = n.object as? String ?? "30"; MainActor.assumeIsolated { self.remoteMeasure(arg) } })
    meterTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in MainActor.assumeIsolated { self.meter() } }
  }

  private func applyRemote(_ json: String) {
    guard let d = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return }
    var q = p
    func num(_ k: String) -> Double? { (d[k] as? NSNumber)?.doubleValue }
    if let v = num("masterDB") { q.masterDB = v }; if let v = num("mainDB") { q.mainDB = v }; if let v = num("secondDB") { q.secondDB = v }
    if let v = num("delayMs") { q.delayMs = v }; if let v = d["eqOn"] as? Bool { q.eqOn = v }
    if let v = num("mainLow") { q.mainLow = v }; if let v = num("mainMid") { q.mainMid = v }; if let v = num("mainHigh") { q.mainHigh = v }
    if let v = num("secondLow") { q.secondLow = v }; if let v = num("secondMid") { q.secondMid = v }; if let v = num("secondHigh") { q.secondHigh = v }
    if q != p { p = q } else { writeState() }
    if let a = d["active"] as? Bool, a != active { setActive(a) }
  }

  private func remoteMeasure(_ arg: String) {
    let reply = { (msg: String) in
      DistributedNotificationCenter.default().postNotificationName(.init("de.r4sp.syncr.measured"), object: msg, userInfo: nil, deliverImmediately: true) }
    guard remoteMeasurements else { reply("Remote measurements are off – enable them in Setup"); return }
    guard !micUID.isEmpty else { reply("No measurement microphone selected"); return }
    let parts = arg.split(separator: " "), secs = Double(parts.first ?? "30") ?? 30
    let name = parts.count > 1 ? String(parts[1]) : "measurement"
    requestMic { ok in
      guard ok else { reply("Microphone access denied"); return }
      let dir = logDir.appendingPathComponent("measurements")
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let (m, mic) = (self.mainUID, self.micUID)
      DispatchQueue.global().async {
        let url = dir.appendingPathComponent("\(name).f32")
        let msg: String
        do { let frames = try Recorder.record(seconds: secs, to: url, mainUID: m, micUID: mic); msg = "done: \(url.path) (\(frames / 48000) s)" }
        catch { msg = "failed: \(error.localizedDescription)" }
        DispatchQueue.main.async { reply(msg) }
      }
    }
  }

  func writeState() {
    func r(_ x: Double) -> Double { (x * 10).rounded() / 10 }
    let d: [String: Any] = ["active": active, "mainUID": mainUID, "secondUID": secondUID, "micUID": micUID,
      "masterDB": r(p.masterDB), "mainDB": r(p.mainDB), "secondDB": r(p.secondDB), "delayMs": r(p.delayMs), "eqOn": p.eqOn,
      "mainLow": r(p.mainLow), "mainMid": r(p.mainMid), "mainHigh": r(p.mainHigh),
      "secondLow": r(p.secondLow), "secondMid": r(p.secondMid), "secondHigh": r(p.secondHigh), "calibratedDelay": r(calibratedDelay)]
    try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys]).write(to: logDir.appendingPathComponent("state.json"))
  }

  /// Level meter, written to the log only while remote measurements are enabled.
  private func meter() {
    let e = engine
    let line = String(format: "%@ in %.1f dBFS | out main %.1f, second %.1f dBFS\n", ISO8601DateFormatter().string(from: Date()),
                      20 * log10(max(e.inPeak, 1e-6)), 20 * log10(max(e.outPeakMain, 1e-6)), 20 * log10(max(e.outPeakSecond, 1e-6)))
    e.inPeak = 0; e.outPeakMain = 0; e.outPeakSecond = 0
    guard remoteMeasurements else { return }
    let url = logDir.appendingPathComponent("levels.log")
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true); try? Data(line.utf8).write(to: url) }
  }
}
