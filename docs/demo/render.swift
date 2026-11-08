// Renders SVG frames into an animated GIF with macOS's own SVG renderer and ImageIO.
// Usage: swift render.swift <output.gif> <scale> < frame-list
// where each stdin line is "<frame.svg> <delay-seconds>" (as printed by frames.py).
import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3, let scale = Double(args[2]) else {
    FileHandle.standardError.write(Data("usage: render.swift <output.gif> <scale> < frames\n".utf8))
    exit(2)
}

var frames: [(URL, Double)] = []
while let line = readLine(), !line.isEmpty {
    let parts = line.split(separator: " ")
    guard parts.count == 2, let delay = Double(parts[1]) else { continue }
    frames.append((URL(fileURLWithPath: String(parts[0])), delay))
}

guard let dest = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: args[1]) as CFURL, UTType.gif.identifier as CFString, frames.count, nil
) else { fatalError("cannot create \(args[1])") }
CGImageDestinationSetProperties(dest, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
] as CFDictionary)

for (url, delay) in frames {
    guard let svg = NSImage(contentsOf: url) else { fatalError("cannot read \(url.path)") }
    let width = Int(svg.size.width * scale), height = Int(svg.size.height * scale)
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("context") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    svg.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    guard let image = context.makeImage() else { fatalError("image") }
    CGImageDestinationAddImage(dest, image, [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay],
    ] as CFDictionary)
}

guard CGImageDestinationFinalize(dest) else { fatalError("could not write GIF") }
print("wrote \(args[1]) (\(frames.count) frames)")
