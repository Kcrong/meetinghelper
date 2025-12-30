#!/usr/bin/env swift

import Cocoa

func createIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    
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
    let waveColor = NSColor.white
    waveColor.setStroke()
    
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

func saveIcon(image: NSImage, path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG")
        return
    }
    
    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Created: \(path)")
    } catch {
        print("Error saving \(path): \(error)")
    }
}

let basePath = "MeetingHelper/Assets.xcassets/AppIcon.appiconset"

// macOS requires these exact sizes
let sizes = [
    ("icon_16.png", 16),
    ("icon_32.png", 32),
    ("icon_64.png", 64),
    ("icon_128.png", 128),
    ("icon_256.png", 256),
    ("icon_512.png", 512),
    ("icon_1024.png", 1024)
]

for (filename, size) in sizes {
    let image = createIcon(size: size)
    saveIcon(image: image, path: "\(basePath)/\(filename)")
}

print("Done!")
