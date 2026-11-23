import AppKit

// Run against the launched app: PNG source files alone cannot catch the
// gray compatibility plate that macOS may add when rendering a legacy icon.
@main
struct DockIconTest {
    @MainActor
    static func main() {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "cn.yohoia.rimo"
        }), let icon = app.icon else {
            fail("Launch Rimo before checking its system-rendered Dock icon.")
        }

        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        icon.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512),
                  from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        var channels: [[CGFloat]] = [[], [], []]
        for x in 240...272 {
            for y in 74...90 {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.99 else {
                    fail("The Dock background must be opaque white.")
                }
                channels[0].append(color.redComponent)
                channels[1].append(color.greenComponent)
                channels[2].append(color.blueComponent)
            }
        }
        let median = channels.map { values in values.sorted()[values.count / 2] }
        let rgb = median.map { Int(($0 * 255).rounded()) }
        // Native white is slightly tone-mapped by macOS (about #F9F9F9).
        // The unwanted legacy plate is #DBDBDB here, well below this bound.
        guard median.allSatisfy({ $0 >= 245.0 / 255.0 }) else {
            fail("System-rendered Dock icon still has a gray background: \(rgb)")
        }
        print("PASS: running Rimo Dock icon has a white background: \(rgb)")
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data(("FAIL: " + message + "\n").utf8))
        exit(1)
    }
}
