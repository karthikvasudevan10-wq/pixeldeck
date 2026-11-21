// Sends mouse clicks, drags and key presses to whatever is on screen. Used by Tools/ci/monkey.py
// to try the Mac app by itself on the build machine.
//
//   pdinput access                      prints whether this process may send events
//   pdinput click X Y                   click at a point of the screen
//   pdinput drag X1 Y1 X2 Y2            press, move and release
//   pdinput key CODE [cmd] [shift] [opt] [ctrl]  press a key by its virtual key code
import CoreGraphics
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
let source = CGEventSource(stateID: .hidSystemState)

func mouse(_ type: CGEventType, _ point: CGPoint) {
    CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(25_000)
}

func number(_ i: Int) -> Double { Double(args[i]) ?? 0 }

switch args.first {
case "access":
    print("may send events: \(CGPreflightPostEventAccess())")
case "click":
    let p = CGPoint(x: number(1), y: number(2))
    mouse(.mouseMoved, p)
    mouse(.leftMouseDown, p)
    mouse(.leftMouseUp, p)
case "drag":
    let a = CGPoint(x: number(1), y: number(2)), b = CGPoint(x: number(3), y: number(4))
    mouse(.mouseMoved, a)
    mouse(.leftMouseDown, a)
    for step in 1...8 {
        let t = Double(step) / 8
        mouse(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
    }
    mouse(.leftMouseUp, b)
case "key":
    var flags: CGEventFlags = []
    if args.contains("cmd") { flags.insert(.maskCommand) }
    if args.contains("shift") { flags.insert(.maskShift) }
    if args.contains("opt") { flags.insert(.maskAlternate) }
    if args.contains("ctrl") { flags.insert(.maskControl) }
    let code = CGKeyCode(UInt16(args[1]) ?? 0)
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
        usleep(25_000)
    }
default:
    print("usage: pdinput access | click X Y | drag X1 Y1 X2 Y2 | key CODE [cmd] [shift] [opt]")
}
