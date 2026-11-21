// Prints "id x y width height" of the biggest window of the process whose id is given.
import CoreGraphics
import Foundation

let pid = Int(CommandLine.arguments.last ?? "") ?? -1
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var best = ""
var bestArea = 0.0
for w in list where (w["kCGWindowOwnerPID"] as? Int) == pid {
    guard let b = w["kCGWindowBounds"] as? [String: Any], let n = w["kCGWindowNumber"] as? Int,
          let width = b["Width"] as? Double, let height = b["Height"] as? Double,
          let x = b["X"] as? Double, let y = b["Y"] as? Double else { continue }
    if width * height > bestArea { bestArea = width * height; best = "\(n) \(Int(x)) \(Int(y)) \(Int(width)) \(Int(height))" }
}
print(best)
