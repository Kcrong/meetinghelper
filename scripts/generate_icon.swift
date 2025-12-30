#!/usr/bin/env swift

import Cocoa

func createIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    
    image.lockFocusFlipped(false)
    
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = CGFloat(size) * 0.22
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    
    // Gradient background
    let gradient = NSGradient(colors: [
        NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0),
        NSColor(red: 0.5, green: 0.3, blue: 0.9, alpha: 1.0)
    ])!
    gradient.draw(in: path, angle: -45)
    
    // Waveform icon
    NSColor.white.setStroke()
    
    let centerY = CGFloat(size) / 2
    let barWidth = CGFloat(size) * 0.08
    let spacing = CGFloat(size) * 0.14
    let startX = CGFloat(size) * 0.22
    
    let heights: [CGFloat] = [0.2, 0.4, 0.55, 0.4, 0.2]
    
    for (i, h) in heights.enumerated() {
        let x = startX + CGFloat(i) * spacing
        let barHeight = CGFloat(size) * h
        let barPath = NSBezierPath()
        barPath.move(to: NSPoint(x: x, y: centerY - barHeight/2))
        barPath.line(to: NSPoint(x: x, y: centerY + barHeight/2))
        barPath.lineWidth = barWidth
        barPath.lineCapStyle = .round
        barPath.stroke()
    }
    
    image.unlockFocus()
    return image
}

func saveIcon(image: NSImage, size: Int, path: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    
    rep.size = NSSize(width: size, height: size)
    
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for size \(size)")
        return
    }
    
    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Created \(size)x\(size): \(path)")
    } catch {
        print("Error: \(error)")
    }
}

let basePath = "MeetingHelper/Assets.xcassets/AppIcon.appiconset"

// Exact sizes required by macOS
let sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes {
    let image = createIcon(size: size)
    saveIcon(image: image, size: size, path: "\(basePath)/icon_\(size).png")
}

print("Done!")
