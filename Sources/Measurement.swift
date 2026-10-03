// Delay calibration: clicks on both devices, recorded with a microphone.
import CoreAudio
import Foundation

/// Builds a private aggregate of the given devices. Returns the aggregate and the index of the
/// first input stream belonging to `micUID` (input streams are ordered like the sub-devices).
private func makeAggregate(_ uids: [String], main: String, micUID: String) throws -> (AudioObjectID, Int) {
  var subs: [[String: Any]] = []
  for u in uids where !subs.contains(where: { $0[kAudioSubDeviceUIDKey] as? String == u }) {
    subs.append(u == main ? [kAudioSubDeviceUIDKey: u] : [kAudioSubDeviceUIDKey: u, kAudioSubDeviceDriftCompensationKey: 1])
  }
  var micIndex = 0, found = false
  for s in subs {
    let u = s[kAudioSubDeviceUIDKey] as! String
    guard let d = deviceID(forUID: u) else { throw syncrError("Device not found: \(u)") }
    if u == micUID { found = true; break }
    micIndex += streamCount(d, kAudioObjectPropertyScopeInput)
  }
  guard found else { throw syncrError("Microphone not found") }
  let desc: [String: Any] = [kAudioAggregateDeviceUIDKey: "de.r4sp.syncr.measure.\(UUID().uuidString)",
    kAudioAggregateDeviceNameKey: "syncR Measurement", kAudioAggregateDeviceIsPrivateKey: 1,
    kAudioAggregateDeviceMainSubDeviceKey: main, kAudioAggregateDeviceSubDeviceListKey: subs]
  var agg = AudioObjectID(kAudioObjectUnknown)
  let st = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &agg)
  guard st == noErr else { throw syncrError("Could not create measurement device", st) }
  Thread.sleep(forTimeInterval: 1.0)   // let the aggregate settle
  return (agg, micIndex)
}

struct CalibrationResult {
  let delayMs: Double        // value for Params.delayMs
  let spreadMs: Double       // max - min over all repetitions
  let snr: Double            // click peak vs. background
  var reliable: Bool { spreadMs < 1.0 && snr > 6 }
}

enum Calibrator {
  /// Plays short 2 kHz bursts alternately on the main and the second device and records them
  /// with the microphone. The difference in arrival time is the delay the earlier device needs.
  static func run(mainUID: String, secondUID: String, micUID: String) throws -> CalibrationResult {
    guard let mainDev = deviceID(forUID: mainUID) else { throw syncrError("Main device not found") }
    let (agg, micIndex) = try makeAggregate([mainUID, secondUID, micUID], main: mainUID, micUID: micUID)
    defer { AudioHardwareDestroyAggregateDevice(agg) }
    let mainBuffers = max(1, streamCount(mainDev, kAudioObjectPropertyScopeOutput))

    let sr = 48000.0, period = 24000, reps = 6, start = 24000
    let total = start + reps * 2 * period + 24000
    let burst: [Float] = (0..<144).map { i in
      Float(0.5 * sin(2 * .pi * 2000 * Double(i) / sr) * (0.5 - 0.5 * cos(2 * .pi * Double(i) / 144))) }
    var rec = [Float](repeating: 0, count: total + 4096)
    var outFrame = 0, inFrame = 0

    var io: AudioDeviceIOProcID?
    var st = AudioDeviceCreateIOProcIDWithBlock(&io, agg, nil) { _, inData, _, outData, _ in
      let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
      if micIndex < ins.count, let p = ins[micIndex].mData?.assumingMemoryBound(to: Float.self) {
        let ch = Int(ins[micIndex].mNumberChannels), n = Int(ins[micIndex].mDataByteSize) / 4 / max(1, ch)
        for i in 0..<n where inFrame + i < rec.count { rec[inFrame + i] = p[i * ch] }
        inFrame += n
      }
      let outs = UnsafeMutableAudioBufferListPointer(outData)
      var frames = 0
      for (bi, b) in outs.enumerated() {
        guard let p = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
        let ch = Int(b.mNumberChannels), n = Int(b.mDataByteSize) / 4 / max(1, ch); frames = n
        let isMain = bi < mainBuffers, firstOfDevice = bi == 0 || bi == mainBuffers
        for i in 0..<n {
          var v: Float = 0
          let g = outFrame + i - start
          if firstOfDevice && g >= 0 && g < reps * 2 * period {
            let k = g % (2 * period), forSecond = k >= period, off = forSecond ? k - period : k
            if forSecond != isMain && off < burst.count { v = burst[off] }
          }
          for c in 0..<ch { p[i * ch + c] = c < 2 ? v : 0 }
        }
      }
      outFrame += frames
    }
    guard st == noErr, let proc = io else { throw syncrError("Could not start measurement", st) }
    setStreamUsage(agg, proc, kAudioObjectPropertyScopeInput) { i, _ in i == micIndex }
    st = AudioDeviceStart(agg, proc)
    Thread.sleep(forTimeInterval: Double(total) / sr + 0.4)
    AudioDeviceStop(agg, proc); AudioDeviceDestroyIOProcID(agg, proc)
    guard inFrame > total / 2 else { throw syncrError("No microphone signal") }

    // Find each burst by cross-correlation within the window after it was played.
    func find(_ from: Int) -> (pos: Int, peak: Float, mean: Float) {
      var best: Float = 0, bestPos = from, sum: Float = 0, cnt: Float = 0
      let hi = min(rec.count - burst.count, from + period - 2400)
      var s = from
      while s < hi {
        var acc: Float = 0
        for j in 0..<burst.count { acc += rec[s + j] * burst[j] }
        let a = abs(acc); sum += a; cnt += 1
        if a > best { best = a; bestPos = s }
        s += 1
      }
      return (bestPos, best, sum / max(cnt, 1))
    }
    var diffs: [Double] = [], snrs: [Double] = []
    for r in 0..<reps {
      let emitMain = start + r * 2 * period, emitSecond = emitMain + period
      let m = find(emitMain), s = find(emitSecond)
      let latMain = Double(m.pos - emitMain), latSecond = Double(s.pos - emitSecond)
      diffs.append((latMain - latSecond) / sr * 1000)
      snrs.append(20 * log10(Double(min(m.peak / max(m.mean, 1e-9), s.peak / max(s.mean, 1e-9)))))
    }
    let sorted = diffs.sorted()
    return CalibrationResult(delayMs: sorted[sorted.count / 2], spreadMs: sorted.last! - sorted.first!,
                             snr: snrs.sorted()[snrs.count / 2])
  }
}
