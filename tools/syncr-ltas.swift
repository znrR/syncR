// syncr-ltas – long-term average spectrum of the microphone relative to the system audio,
// in 1/3 octaves, normalized to 400 Hz–2.5 kHz. Works with music and needs no time alignment.
//   syncr-ltas ~/Library/Logs/syncR/measurements/a.f32 [b.f32 ...]
import Foundation
import Accelerate

let nfft = 16384
func spectra(_ path: String) -> ([Double], [Double]) {
  let d = try! Data(contentsOf: URL(fileURLWithPath: path))
  let f = d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
  let ref = stride(from: 0, to: f.count - 1, by: 2).map { f[$0] }, mic = stride(from: 1, to: f.count, by: 2).map { f[$0] }
  var win = [Float](repeating: 0, count: nfft); vDSP_hann_window(&win, vDSP_Length(nfft), Int32(vDSP_HANN_NORM))
  let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(nfft), .FORWARD)!
  var sRef = [Double](repeating: 0, count: nfft / 2), sMic = sRef
  let zeros = [Float](repeating: 0, count: nfft)
  var s = 0
  while s + nfft <= ref.count {
    for (src, isRef) in [(ref, true), (mic, false)] {
      let x = zip(src[s..<s + nfft], win).map(*)
      var re = [Float](repeating: 0, count: nfft), im = re
      vDSP_DFT_Execute(setup, x, zeros, &re, &im)
      for k in 0..<nfft / 2 { let p = Double(re[k] * re[k] + im[k] * im[k]); if isRef { sRef[k] += p } else { sMic[k] += p } }
    }
    s += nfft / 2
  }
  return (sRef, sMic)
}
var bands = [Double](); var fq = 31.5; while fq < 17000 { bands.append(fq); fq *= pow(2, 1.0 / 3) }
let files = Array(CommandLine.arguments.dropFirst())
guard !files.isEmpty else { print("usage: syncr-ltas file.f32 [...]"); exit(1) }
let results: [[Double]] = files.map { p in
  let (r, m) = spectra(p)
  return bands.map { f in
    let lo = Int(f / pow(2, 1.0 / 6) * Double(nfft) / 48000), hi = max(lo + 1, Int(f * pow(2, 1.0 / 6) * Double(nfft) / 48000))
    var R = 0.0, M = 0.0; for k in lo..<min(hi, nfft / 2) { R += r[k]; M += m[k] }
    return 10 * log10(max(M, 1e-30) / max(R, 1e-30))
  }
}
let refBands = bands.indices.filter { bands[$0] > 400 && bands[$0] < 2600 }
print("    Hz" + files.map { " | " + URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent.padding(toLength: 10, withPad: " ", startingAt: 0) }.joined())
for (i, f) in bands.enumerated() {
  var line = String(format: "%6.0f", f)
  for r in results { let n = refBands.map { r[$0] }.reduce(0, +) / Double(refBands.count); line += String(format: " | %+7.1f   ", r[i] - n) }
  print(line)
}
