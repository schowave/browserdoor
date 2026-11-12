@testable import BrowserdoorCore
import CoreGraphics
import Testing

struct PickerPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let size = CGSize(width: 320, height: 200)

    @Test func opensBelowRightOfTheMouse() {
        let origin = PickerPlacement.origin(mouse: CGPoint(x: 500, y: 500), size: size, visible: screen)
        #expect(origin == CGPoint(x: 476, y: 312)) // top-left corner 24 left of and 12 above the mouse
    }

    @Test func staysInsideTheVisibleFrame() {
        let corner = PickerPlacement.origin(mouse: CGPoint(x: 995, y: 5), size: size, visible: screen)
        #expect(corner == CGPoint(x: 1000 - 320 - 8, y: 8))
        let other = CGRect(x: -1440, y: 100, width: 1440, height: 900) // a second screen on the left
        let top = PickerPlacement.origin(mouse: CGPoint(x: -1430, y: 999), size: size, visible: other)
        #expect(top == CGPoint(x: -1440 + 8, y: 100 + 900 - 200 - 8))
    }

    @Test func resizingKeepsTheTopEdge() {
        let frame = CGRect(x: 10, y: 300, width: 320, height: 200)
        let taller = PickerPlacement.resized(frame, to: CGSize(width: 320, height: 260), visible: screen)
        #expect(taller.maxY == frame.maxY)
        #expect(taller.minX == 10)
        #expect(taller.height == 260)
    }

    @Test func growingAtTheBottomEdgeStaysOnScreen() {
        let frame = CGRect(x: 600, y: 8, width: 320, height: 200)
        let taller = PickerPlacement.resized(frame, to: CGSize(width: 320, height: 300), visible: screen)
        #expect(taller.minY == 8)
        #expect(taller.height == 300)
    }

    @Test func aPanelTooBigForTheScreenKeepsItsTopLeftCorner() {
        let small = CGRect(x: 0, y: 0, width: 300, height: 400)
        let frame = PickerPlacement.clamped(CGRect(x: 50, y: 50, width: 320, height: 600), to: small)
        #expect(frame.minX == 8)
        #expect(frame.maxY == 392) // 400 − 8: the top stays on screen
    }
}
