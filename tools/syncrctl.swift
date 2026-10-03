// syncrctl – remote control for syncR.
//   syncrctl set '{"secondDB": 4, "delayMs": 81}'   change parameters (keys: see state.json)
//   syncrctl state                                  print ~/Library/Logs/syncR/state.json
//   syncrctl measure <seconds> <name>               record system audio + measurement mic
//                                                    (enable "Allow remote measurements" in Setup)
import Foundation

let args = CommandLine.arguments
let center = DistributedNotificationCenter.default()
let stateURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/syncR/state.json")

switch args.count > 1 ? args[1] : "" {
case "set" where args.count > 2:
  center.postNotificationName(.init("de.r4sp.syncr.set"), object: args[2], userInfo: nil, deliverImmediately: true)
  Thread.sleep(forTimeInterval: 0.3)
case "state":
  print((try? String(contentsOf: stateURL, encoding: .utf8)) ?? "no state file – is syncR running?")
case "measure" where args.count > 3:
  let secs = Double(args[2]) ?? 30
  var done = false
  let o = center.addObserver(forName: .init("de.r4sp.syncr.measured"), object: nil, queue: .main) { n in
    print(n.object as? String ?? "done"); done = true }
  center.postNotificationName(.init("de.r4sp.syncr.measure"), object: "\(args[2]) \(args[3])", userInfo: nil, deliverImmediately: true)
  let end = Date().addingTimeInterval(secs + 15)
  while !done && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
  if !done { print("no answer – is syncR running?") }
  center.removeObserver(o)
default:
  print("usage: syncrctl set '<json>' | state | measure <seconds> <name>")
}
