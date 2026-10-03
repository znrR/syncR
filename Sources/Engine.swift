// Audio engine: captures all system audio with a muted process tap and plays it on two
// output devices in sync, with per-device gain, delay and EQ.
import CoreAudio
import AudioToolbox
import Foundation
import os

struct Params: Equatable {
  var masterDB = 0.0
  var mainDB = 0.0, secondDB = 0.0
  /// Positive: second device is delayed. Negative: main device is delayed.
  var delayMs = 0.0
  var eqOn = false
  var mainLow = 0.0, mainMid = 0.0, mainHigh = 0.0
  var secondLow = 0.0, secondMid = 0.0, secondHigh = 0.0
  var muted = false
}

final class Engine: @unchecked Sendable {
  private var lock = os_unfair_lock()
  private var pending = Params(), cur = Params()
  private var version = 1, applied = 0
  private var sr = 48000.0

  private var eqMain = ThreeBandEQ(), eqSecond = ThreeBandEQ()
  private var gMaster: Float = 1, gMain: Float = 1, gSecond: Float = 1
  private var smMaster: Float = 0, smMain: Float = 0, smSecond: Float = 0, smFollow: Float = 0

  /// The second device follows the main device's hardware volume (keyboard, menu bar, device buttons).
  var followGain: Float = 1
  var followMute = false

  // Delay line (stereo) for whichever device has to wait
  private let ringSize = 1 << 15
  private var ringL = [Float](repeating: 0, count: 1 << 15), ringR = [Float](repeating: 0, count: 1 << 15)
  private var ringPos = 0
  private var delaySamples = 0, delaySecond = true

  // Meters (read by the UI thread, reset after reading)
  var inPeak: Float = 0, outPeakMain: Float = 0, outPeakSecond: Float = 0

  private var tapID = AudioObjectID(kAudioObjectUnknown)
  private var aggID = AudioObjectID(kAudioObjectUnknown)
  private var ioProc: AudioDeviceIOProcID?
  private var mainBuffers = 1      // number of output buffers belonging to the main device
  private(set) var running = false

  func update(_ p: Params) {
    os_unfair_lock_lock(&lock); pending = p; version += 1; os_unfair_lock_unlock(&lock)
  }

  private func applyIfNeeded() {
    guard os_unfair_lock_trylock(&lock) else { return }
    guard version != applied else { os_unfair_lock_unlock(&lock); return }
    cur = pending; applied = version
    os_unfair_lock_unlock(&lock)
    let p = cur
    eqMain.set(low: p.mainLow, mid: p.mainMid, high: p.mainHigh, sr: sr)
    eqSecond.set(low: p.secondLow, mid: p.secondMid, high: p.secondHigh, sr: sr)
    gMaster = p.muted ? 0 : dbToGain(p.masterDB); gMain = dbToGain(p.mainDB); gSecond = dbToGain(p.secondDB)
    delaySecond = p.delayMs >= 0
    delaySamples = max(0, min(ringSize - 1, Int((abs(p.delayMs) * sr / 1000).rounded())))
  }

  private func render(_ inList: UnsafePointer<AudioBufferList>, _ outList: UnsafeMutablePointer<AudioBufferList>) {
    applyIfNeeded()
    let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inList))
    let outs = UnsafeMutableAudioBufferListPointer(outList)
    for b in outs { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }

    // The tap is the last input stream (the devices' own microphones are switched off).
    guard let tb = ins.last, let tp = tb.mData?.assumingMemoryBound(to: Float.self), outs.count > mainBuffers else { return }
    let tapCh = Int(tb.mNumberChannels)
    let mb = outs[0], sb = outs[mainBuffers]
    guard let mo = mb.mData?.assumingMemoryBound(to: Float.self), let so = sb.mData?.assumingMemoryBound(to: Float.self) else { return }
    let mCh = Int(mb.mNumberChannels), sCh = Int(sb.mNumberChannels)
    let n = min(Int(tb.mDataByteSize) / 4 / max(1, tapCh), Int(mb.mDataByteSize) / 4 / max(1, mCh), Int(sb.mDataByteSize) / 4 / max(1, sCh))
    let eq = cur.eqOn
    let k: Float = 0.002   // gain smoothing against clicks
    for i in 0..<n {
      smMaster += k * (gMaster - smMaster); smMain += k * (gMain - smMain); smSecond += k * (gSecond - smSecond)
      smFollow += k * ((followMute ? 0 : followGain) - smFollow)
      let l = tp[i * tapCh], r = tapCh > 1 ? tp[i * tapCh + 1] : l
      inPeak = max(inPeak, abs(l), abs(r))
      var ml = l, mr = r, sl = l, sr2 = r
      if eq { ml = eqMain.run(ml, 0); mr = eqMain.run(mr, 1); sl = eqSecond.run(sl, 0); sr2 = eqSecond.run(sr2, 1) }
      // delay whichever device is earlier
      if delaySecond {
        ringL[ringPos] = sl; ringR[ringPos] = sr2
        let rp = (ringPos - delaySamples + ringSize) & (ringSize - 1); sl = ringL[rp]; sr2 = ringR[rp]
      } else {
        ringL[ringPos] = ml; ringR[ringPos] = mr
        let rp = (ringPos - delaySamples + ringSize) & (ringSize - 1); ml = ringL[rp]; mr = ringR[rp]
      }
      ringPos = (ringPos + 1) & (ringSize - 1)
      // main device: its hardware volume is the system volume, so no follow gain here
      let gm = smMaster * smMain, gs = smMaster * smSecond * smFollow
      ml *= gm; mr *= gm; sl *= gs; sr2 *= gs
      outPeakMain = max(outPeakMain, abs(ml), abs(mr)); outPeakSecond = max(outPeakSecond, abs(sl), abs(sr2))
      if mCh >= 2 { mo[i * mCh] = softLimit(ml); mo[i * mCh + 1] = softLimit(mr) } else { mo[i] = softLimit(0.5 * (ml + mr)) }
      if sCh >= 2 { so[i * sCh] = softLimit(sl); so[i * sCh + 1] = softLimit(sr2) } else { so[i] = softLimit(0.5 * (sl + sr2)) }
    }
  }

  func start(mainUID: String, secondUID: String) throws {
    if running { return }
    guard let mainDev = deviceID(forUID: mainUID) else { throw syncrError("Main device not found") }
    guard deviceID(forUID: secondUID) != nil else { throw syncrError("Second device not found") }
    guard mainUID != secondUID else { throw syncrError("Choose two different devices") }

    let proc = ownProcessObject()
    let desc = CATapDescription(__stereoGlobalTapButExcludeProcesses: proc != 0 ? [NSNumber(value: proc)] : [])
    desc.uuid = UUID(); desc.name = "syncR"; desc.isPrivate = true; desc.muteBehavior = .muted
    var st = AudioHardwareCreateProcessTap(desc, &tapID)
    guard st == noErr else { throw syncrError("System audio capture failed – check the “System Audio Recording” permission", st) }

    let agg: [String: Any] = [
      kAudioAggregateDeviceUIDKey: "de.r4sp.syncr.\(UUID().uuidString)", kAudioAggregateDeviceNameKey: "syncR",
      kAudioAggregateDeviceIsPrivateKey: 1, kAudioAggregateDeviceMainSubDeviceKey: mainUID,
      kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: mainUID],
                                              [kAudioSubDeviceUIDKey: secondUID, kAudioSubDeviceDriftCompensationKey: 1]],
      kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString, kAudioSubTapDriftCompensationKey: 1]],
      kAudioAggregateDeviceTapAutoStartKey: 1]
    st = AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID)
    guard st == noErr else { cleanup(); throw syncrError("Could not combine the devices", st) }

    mainBuffers = max(1, streamCount(mainDev, kAudioObjectPropertyScopeOutput))
    var a = addr(kAudioDevicePropertyNominalSampleRate); var rate = 48000.0; var size = UInt32(8)
    AudioObjectGetPropertyData(aggID, &a, 0, nil, &size, &rate); sr = rate
    os_unfair_lock_lock(&lock); version += 1; os_unfair_lock_unlock(&lock)

    st = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggID, nil) { [unowned self] _, inData, _, outData, _ in
      self.render(inData, outData)
    }
    guard st == noErr, let io = ioProc else { cleanup(); throw syncrError("Could not start audio", st) }
    setStreamUsage(aggID, io, kAudioObjectPropertyScopeInput) { i, n in i == n - 1 }   // only the tap
    AudioDeviceStart(aggID, io)
    running = true
  }

  private func cleanup() {
    if let p = ioProc { AudioDeviceStop(aggID, p); AudioDeviceDestroyIOProcID(aggID, p); ioProc = nil }
    if aggID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggID); aggID = AudioObjectID(kAudioObjectUnknown) }
    if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
  }

  func stop() { cleanup(); running = false }
}
