// Small CoreAudio helpers: device lookup, names, streams, volume.
import CoreAudio
import Foundation

let systemObject = AudioObjectID(kAudioObjectSystemObject)

func addr(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
          _ el: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
  AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: el)
}

func objectList(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
  var a = addr(sel, scope); var size: UInt32 = 0
  guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
  var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
  AudioObjectGetPropertyData(id, &a, 0, nil, &size, &list)
  return list
}

func stringProperty(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
  var a = addr(sel); var s: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<CFString?>.size)
  guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &s) == noErr, let r = s else { return nil }
  return r.takeRetainedValue() as String
}

func deviceID(forUID uid: String) -> AudioObjectID? {
  var a = addr(kAudioHardwarePropertyTranslateUIDToDevice)
  var u = uid as CFString; var d = AudioObjectID(kAudioObjectUnknown); var size = UInt32(MemoryLayout<AudioObjectID>.size)
  let st = withUnsafeMutablePointer(to: &u) {
    AudioObjectGetPropertyData(systemObject, &a, UInt32(MemoryLayout<CFString>.size), $0, &size, &d)
  }
  return st == noErr && d != kAudioObjectUnknown ? d : nil
}

func streamCount(_ dev: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Int {
  objectList(dev, kAudioDevicePropertyStreams, scope).count
}

struct AudioDevice: Identifiable, Hashable {
  let id: AudioObjectID
  let uid: String
  let name: String
}

/// All devices with output (or input) streams, excluding private aggregates.
func listDevices(input: Bool) -> [AudioDevice] {
  objectList(systemObject, kAudioHardwarePropertyDevices).compactMap { d in
    guard streamCount(d, input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput) > 0,
          let uid = stringProperty(d, kAudioDevicePropertyDeviceUID),
          let name = stringProperty(d, kAudioObjectPropertyName) else { return nil }
    return AudioDevice(id: d, uid: uid, name: name)
  }
}

func defaultOutputDevice() -> AudioObjectID {
  var a = addr(kAudioHardwarePropertyDefaultOutputDevice); var d = AudioObjectID(0); var size = UInt32(4)
  AudioObjectGetPropertyData(systemObject, &a, 0, nil, &size, &d); return d
}
func defaultInputDevice() -> AudioObjectID {
  var a = addr(kAudioHardwarePropertyDefaultInputDevice); var d = AudioObjectID(0); var size = UInt32(4)
  AudioObjectGetPropertyData(systemObject, &a, 0, nil, &size, &d); return d
}
func setDefaultOutputDevice(_ d: AudioObjectID) {
  var a = addr(kAudioHardwarePropertyDefaultOutputDevice); var x = d
  AudioObjectSetPropertyData(systemObject, &a, 0, nil, 4, &x)
}

/// Volume elements of an output device: the main element if it has one, otherwise the individual channels.
func volumeElements(_ d: AudioObjectID) -> [AudioObjectPropertyElement] {
  var main = addr(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, 0)
  if AudioObjectHasProperty(d, &main) { return [0] }
  return (1...8).map { AudioObjectPropertyElement($0) }.filter {
    var a = addr(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, $0); return AudioObjectHasProperty(d, &a)
  }
}

/// Output volume in dB and mute state (used to make the second device follow the main device).
func outputVolume(_ d: AudioObjectID) -> (db: Float32, muted: Bool)? {
  guard let el = volumeElements(d).first else { return nil }
  var a = addr(kAudioDevicePropertyVolumeDecibels, kAudioObjectPropertyScopeOutput, el)
  var db: Float32 = 0; var size = UInt32(4)
  guard AudioObjectGetPropertyData(d, &a, 0, nil, &size, &db) == noErr else { return nil }
  var m = addr(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput, 0)
  var mute: UInt32 = 0; size = 4
  if AudioObjectHasProperty(d, &m) { AudioObjectGetPropertyData(d, &m, 0, nil, &size, &mute) }
  return (db, mute != 0)
}

func hardwareVolumeScalar(_ d: AudioObjectID) -> Float32? {
  guard let el = volumeElements(d).first else { return nil }
  var a = addr(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, el)
  var v: Float32 = 0; var size = UInt32(4)
  return AudioObjectGetPropertyData(d, &a, 0, nil, &size, &v) == noErr ? v : nil
}

func setHardwareVolumeScalar(_ d: AudioObjectID, _ v: Float32) {
  for el in volumeElements(d) {
    var a = addr(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, el); var x = v
    AudioObjectSetPropertyData(d, &a, 0, nil, 4, &x)
  }
  var m = addr(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput, 0)
  if AudioObjectHasProperty(d, &m) { var z: UInt32 = 0; AudioObjectSetPropertyData(d, &m, 0, nil, 4, &z) }
}

func ownProcessObject() -> AudioObjectID {
  var a = addr(kAudioHardwarePropertyTranslatePIDToProcessObject)
  var pid = getpid(), proc = AudioObjectID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioObjectID>.size)
  AudioObjectGetPropertyData(systemObject, &a, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &proc)
  return proc
}

/// Enables/disables individual streams of an IOProc. Used to keep the microphones of the
/// output devices off (otherwise macOS shows the orange microphone indicator).
@discardableResult
func setStreamUsage(_ dev: AudioObjectID, _ proc: AudioDeviceIOProcID, _ scope: AudioObjectPropertyScope, _ on: (Int, Int) -> Bool) -> OSStatus {
  let n = streamCount(dev, scope)
  guard n > 0 else { return noErr }
  let bytes = MemoryLayout<UnsafeMutableRawPointer>.size + 4 + 4 * n
  let raw = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 8); defer { raw.deallocate() }
  raw.storeBytes(of: unsafeBitCast(proc, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
  raw.storeBytes(of: UInt32(n), toByteOffset: 8, as: UInt32.self)
  for i in 0..<n { raw.storeBytes(of: on(i, n) ? 1 : 0, toByteOffset: 12 + 4 * i, as: UInt32.self) }
  var a = addr(kAudioDevicePropertyIOProcStreamUsage, scope)
  return AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(bytes), raw)
}

func syncrError(_ msg: String, _ st: OSStatus = 0) -> NSError {
  NSError(domain: "syncR", code: Int(st), userInfo: [NSLocalizedDescriptionKey: st == 0 ? msg : "\(msg) (\(st))"])
}
