// Lists every window on screen: who owns it, its name, where it is and its layer.
import CoreGraphics
import Foundation

let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    let owner = w["kCGWindowOwnerName"] as? String ?? "?"
    let name = w["kCGWindowName"] as? String ?? ""
    let layer = w["kCGWindowLayer"] as? Int ?? 0
    guard let b = w["kCGWindowBounds"] as? [String: Any], let width = b["Width"] as? Double, let height = b["Height"] as? Double,
          let x = b["X"] as? Double, let y = b["Y"] as? Double, width > 60, height > 60 else { continue }
    print("\(owner) | \(name) | \(Int(x)),\(Int(y)) \(Int(width))x\(Int(height)) | layer \(layer)")
}
