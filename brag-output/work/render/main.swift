// Renders the Spacewise brag video frame by frame.
// Usage: render video <shots> <demoRoot> <icon>            -> raw BGRA frames on stdout
//        render stills <shots> <demoRoot> <icon> <outDir> t1 t2 ...  -> PNG stills
import AppKit
import CoreGraphics
import Foundation

let W = 1920.0, H = 1080.0, FPS = 30.0, DURATION = 21.0
let args = CommandLine.arguments
let mode = args[1], shotsDir = args[2], demoRoot = args[3], iconPath = args[4]

// MARK: - Assets

func loadImage(_ path: String) -> CGImage {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)!
}
var shots: [String: CGImage] = [:]
for name in ["01-overview-empty", "02-overview", "03-explore", "07-cleanup", "08-duplicates"] {
    shots[name] = loadImage("\(shotsDir)/\(name).png")
}
let icon = loadImage(iconPath)
let shotW = 2560.0, shotH = 1600.0

// The app's own treemap of the sample home folder.
let scanRoot = DiskScanner().scan(rootPath: demoRoot)!
var tmOptions = TreemapOptions()
tmOptions.headerHeight = 0
tmOptions.padding = 4
tmOptions.minSide = 6
let tmRect = TreemapRect(x: 36, y: 36, width: W - 72, height: H - 72)
let tiles = Treemap.layout(root: scanRoot, in: tmRect, options: tmOptions)
    .filter { $0.isLeaf }
    .sorted { $0.rect.area > $1.rect.area }

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
// macOS dark-mode system colours, as used by CategoryStyle.swift.
func categoryColor(_ c: FileCategory?) -> (Double, Double, Double) {
    switch c {
    case .applications: return (94, 92, 230)
    case .videos: return (191, 90, 242)
    case .images: return (255, 159, 10)
    case .audio: return (255, 55, 95)
    case .documents: return (10, 132, 255)
    case .archives: return (172, 142, 104)
    case .developer: return (48, 209, 88)
    case .system: return (152, 152, 157)
    case .other: return (64, 200, 224)
    case nil: return (152, 152, 157)
    }
}

// MARK: - Easing

func clamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(b, max(a, x)) }
func prog(_ t: Double, _ start: Double, _ dur: Double) -> Double { clamp((t - start) / dur) }
func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
func easeIn(_ x: Double) -> Double { x * x * x }
func easeInOut(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
func backOut(_ x: Double) -> Double { let c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2) }
func lerp(_ a: Double, _ b: Double, _ x: Double) -> Double { a + (b - a) * x }

// MARK: - Drawing helpers (top-left origin)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
func makeContext() -> CGContext {
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: Int(W) * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.translateBy(x: 0, y: H)
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    return ctx
}

func drawImage(_ ctx: CGContext, _ img: CGImage, _ rect: CGRect) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
    ctx.restoreGState()
}

func font(_ size: Double, _ weight: NSFont.Weight) -> NSFont { NSFont.systemFont(ofSize: size, weight: weight) }

/// Draws one line of text centred on `cx`, with its top at `y`.
func text(_ ctx: CGContext, _ s: String, _ f: NSFont, _ color: NSColor, cx: Double, y: Double, alpha: Double = 1, kern: Double = 0) {
    guard alpha > 0.001 else { return }
    let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color.withAlphaComponent(color.alphaComponent * alpha), .kern: kern]
    let str = NSAttributedString(string: s, attributes: attrs)
    let size = str.size()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    str.draw(at: NSPoint(x: cx - size.width / 2, y: y))
    NSGraphicsContext.restoreGraphicsState()
}

func roundedRect(_ r: CGRect, _ radius: Double) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil)
}

// MARK: - Background

func background(_ ctx: CGContext, _ t: Double) {
    ctx.setFillColor(rgb(13, 13, 16))
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    // Two soft glows in the app's category colours, drifting slowly.
    let glows: [(Double, Double, Double, (Double, Double, Double), Double)] = [
        (420 + 60 * sin(t * 0.35), 260, 900, (191, 90, 242), 0.20),
        (1520 - 60 * sin(t * 0.3), 860, 950, (10, 132, 255), 0.18),
    ]
    for (x, y, r, c, a) in glows {
        let g = CGGradient(colorsSpace: space, colors: [rgb(c.0, c.1, c.2, a), rgb(c.0, c.1, c.2, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
    }
}

// MARK: - Treemap (hook and outro)

func drawTreemap(_ ctx: CGContext, appearStart: Double, t: Double, collapse: Double, alphaScale: Double, labels: Bool) {
    let n = Double(tiles.count)
    let step = min(0.022, 1.2 / max(1, n))
    let center = CGPoint(x: W / 2, y: H / 2)
    for (i, tile) in tiles.enumerated() {
        let start = appearStart + Double(i) * step
        let p = prog(t, start, 0.38)
        guard p > 0 else { continue }
        var s = lerp(0.55, 1, backOut(p))
        var a = clamp(p * 2.2) * alphaScale
        var r = CGRect(x: tile.rect.x, y: tile.rect.y, width: tile.rect.width, height: tile.rect.height).insetBy(dx: 1, dy: 1)
        // Collapse every block into the centre (transition into the reveal).
        if collapse > 0 {
            let c = easeIn(collapse)
            let mid = CGPoint(x: lerp(r.midX, center.x, c), y: lerp(r.midY, center.y, c))
            s *= (1 - c)
            a *= 1 - clamp(c * 1.3)
            r = CGRect(x: mid.x - r.width / 2, y: mid.y - r.height / 2, width: r.width, height: r.height)
        }
        guard a > 0.002, s > 0.01 else { continue }
        let sr = CGRect(x: r.midX - r.width * s / 2, y: r.midY - r.height * s / 2, width: r.width * s, height: r.height * s)
        let (cr, cg, cb) = categoryColor(tile.category)
        let opacity = max(0.55, 0.92 - Double(tile.depth) * 0.07)
        ctx.addPath(roundedRect(sr, min(8, min(sr.width, sr.height) / 3)))
        ctx.setFillColor(rgb(cr, cg, cb, opacity * a))
        ctx.fillPath()
        if labels && collapse == 0 && sr.width > 170 && sr.height > 64 {
            text(ctx, tile.node.name, font(22, .semibold), .white, cx: sr.minX + 12 + Double(tile.node.name.size(withAttributes: [.font: font(22, .semibold)]).width) / 2,
                 y: sr.minY + 10, alpha: a * 0.95)
            text(ctx, ByteCountFormatter.string(fromByteCount: tile.node.size, countStyle: .file), font(19, .regular), NSColor(white: 1, alpha: 0.8),
                 cx: sr.minX + 12 + Double(ByteCountFormatter.string(fromByteCount: tile.node.size, countStyle: .file).size(withAttributes: [.font: font(19, .regular)]).width) / 2,
                 y: sr.minY + 38, alpha: a * 0.95)
        }
    }
}

// MARK: - App window with a camera inside it

let winRect = CGRect(x: (W - 1400) / 2, y: 182, width: 1400, height: 875)

struct Shot { let name: String; let zoom: Double; let focus: CGPoint }

/// Maps a point in screenshot pixels to frame coordinates for the current camera.
func mapPoint(_ p: CGPoint, zoom: Double, focus: CGPoint, frame: CGRect) -> CGPoint {
    let s = frame.width / shotW * zoom
    // `focus` is placed at the window centre; zoom 1 shows the whole screenshot.
    let fx = lerp(shotW / 2, focus.x, clamp((zoom - 1) / 0.5 + (zoom > 1 ? 0.0001 : 0)))
    let fy = lerp(shotH / 2, focus.y, clamp((zoom - 1) / 0.5 + (zoom > 1 ? 0.0001 : 0)))
    var ox = frame.midX - fx * s
    var oy = frame.midY - fy * s
    // Keep the screenshot covering the window.
    ox = min(frame.minX, max(frame.maxX - shotW * s, ox))
    oy = min(frame.minY, max(frame.maxY - shotH * s, oy))
    return CGPoint(x: ox + p.x * s, y: oy + p.y * s)
}

func drawWindow(_ ctx: CGContext, shot: Shot, frame: CGRect, windowAlpha: Double, contentAlpha: Double, contentScale: Double) {
    guard windowAlpha > 0.001 else { return }
    ctx.saveGState()
    ctx.setAlpha(windowAlpha)
    // Shadow (offsets are in device space: negative y is down).
    ctx.setShadow(offset: CGSize(width: 0, height: -28), blur: 70, color: rgb(0, 0, 0, 0.7))
    ctx.addPath(roundedRect(frame, 22))
    ctx.setFillColor(rgb(32, 32, 34))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(roundedRect(frame, 22))
    ctx.clip()
    if contentAlpha > 0.001, let img = shots[shot.name] {
        ctx.setAlpha(windowAlpha * contentAlpha)
        let s = frame.width / shotW * shot.zoom
        let origin = mapPoint(.zero, zoom: shot.zoom, focus: shot.focus, frame: frame)
        var r = CGRect(x: origin.x, y: origin.y, width: shotW * s, height: shotH * s)
        if contentScale != 1 {
            r = CGRect(x: frame.midX + (r.minX - frame.midX) * contentScale, y: frame.midY + (r.minY - frame.midY) * contentScale,
                       width: r.width * contentScale, height: r.height * contentScale)
        }
        drawImage(ctx, img, r)
    }
    ctx.restoreGState()
    // Thin edge, like a real window.
    ctx.saveGState()
    ctx.setAlpha(windowAlpha)
    ctx.addPath(roundedRect(frame.insetBy(dx: 0.5, dy: 0.5), 22))
    ctx.setStrokeColor(rgb(255, 255, 255, 0.12))
    ctx.setLineWidth(1)
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - Cursor

func cursorPath(at p: CGPoint, scale: Double) -> CGPath {
    let pts: [(Double, Double)] = [(0, 0), (0, 25.5), (6, 20), (10.4, 29.6), (14.4, 27.8), (10.2, 18.6), (18, 18.4)]
    let path = CGMutablePath()
    for (i, q) in pts.enumerated() {
        let pt = CGPoint(x: p.x + q.0 * scale, y: p.y + q.1 * scale)
        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
    }
    path.closeSubpath()
    return path
}

func drawCursor(_ ctx: CGContext, _ p: CGPoint, alpha: Double, press: Double) {
    guard alpha > 0.001 else { return }
    let scale = 1.55 * (1 - 0.14 * press)
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 8, color: rgb(0, 0, 0, 0.5))
    ctx.addPath(cursorPath(at: p, scale: scale))
    ctx.setFillColor(rgb(0, 0, 0))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(cursorPath(at: p, scale: scale))
    ctx.setStrokeColor(rgb(255, 255, 255))
    ctx.setLineWidth(2.4)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()
}

func drawRipple(_ ctx: CGContext, _ p: CGPoint, _ x: Double) {
    guard x > 0, x < 1 else { return }
    let r = lerp(10, 70, easeOut(x))
    ctx.setStrokeColor(rgb(10, 132, 255, 0.85 * (1 - x)))
    ctx.setLineWidth(5 * (1 - x) + 1)
    ctx.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
}

/// Accent ring around a region given in screenshot pixels.
func drawHighlight(_ ctx: CGContext, region: CGRect, shot: Shot, frame: CGRect, x: Double, pulse: Double) {
    guard x > 0 else { return }
    let a = mapPoint(CGPoint(x: region.minX, y: region.minY), zoom: shot.zoom, focus: shot.focus, frame: frame)
    let b = mapPoint(CGPoint(x: region.maxX, y: region.maxY), zoom: shot.zoom, focus: shot.focus, frame: frame)
    let grow = (1 - easeOut(x)) * 14
    let r = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y).insetBy(dx: -8 - grow, dy: -6 - grow)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 18 + 8 * pulse, color: rgb(10, 132, 255, 0.9 * x))
    ctx.addPath(roundedRect(r, 12))
    ctx.setStrokeColor(rgb(64, 156, 255, x))
    ctx.setLineWidth(3.5)
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - Captions

func caption(_ ctx: CGContext, _ s: String, t: Double, start: Double, end: Double) {
    let inP = easeOut(prog(t, start, 0.3))
    let outP = prog(t, end - 0.2, 0.2)
    let a = inP * (1 - outP)
    guard a > 0 else { return }
    text(ctx, s, font(62, .bold), .white, cx: W / 2, y: 62 + 24 * (1 - inP), alpha: a, kern: -0.5)
}

// MARK: - Scenes

func windowShot(_ t: Double) -> (shot: Shot, contentAlpha: Double, contentScale: Double) {
    // Step the old screen out, then the new one in (no muddy crossfades).
    func swap(_ cut: Double) -> (Double, Double)? {
        if t >= cut - 0.15 && t < cut { let x = prog(t, cut - 0.15, 0.15); return (1 - easeIn(x), 1 - 0.03 * x) }
        if t >= cut && t < cut + 0.22 { let x = easeOut(prog(t, cut, 0.22)); return (x, 1.03 - 0.03 * x) }
        return nil
    }
    let shot: Shot
    var cut: Double = .nan
    if t < 7.0 {
        shot = Shot(name: "01-overview-empty", zoom: 1, focus: CGPoint(x: 1280, y: 800))
        cut = 7.0
    } else if t < 9.5 {
        let z = lerp(1, 1.5, easeInOut(prog(t, 7.35, 1.9)))
        shot = Shot(name: "02-overview", zoom: z, focus: CGPoint(x: 1200, y: 330))
        cut = t < 8.5 ? 7.0 : 9.5
    } else if t < 13.0 {
        let z = lerp(1, 1.22, easeInOut(prog(t, 9.75, 3.1)))
        shot = Shot(name: "03-explore", zoom: z, focus: CGPoint(x: 1000, y: 820))
        cut = t < 11 ? 9.5 : 13.0
    } else if t < 15.5 {
        let z = lerp(1, 1.3, easeInOut(prog(t, 13.25, 2.1)))
        shot = Shot(name: "08-duplicates", zoom: z, focus: CGPoint(x: 2300, y: 520))
        cut = t < 14 ? 13.0 : 15.5
    } else {
        let z = lerp(1, 1.16, easeInOut(prog(t, 15.75, 2.0)))
        shot = Shot(name: "07-cleanup", zoom: z, focus: CGPoint(x: 1800, y: 1180))
        cut = 15.5
    }
    if let (a, s) = swap(cut) { return (shot, a, s) }
    return (shot, 1, 1)
}

func renderFrame(_ t: Double) -> CGContext {
    let ctx = makeContext()
    background(ctx, t)

    // 1. Hook: the treemap.
    if t < 3.1 {
        let collapse = prog(t, 2.72, 0.32)
        drawTreemap(ctx, appearStart: 0.0, t: t, collapse: collapse, alphaScale: 1, labels: true)
        let dim = clamp((t - 0.15) / 0.4) * 0.64 * (1 - collapse)
        ctx.setFillColor(rgb(8, 8, 10, dim))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let out = 1 - prog(t, 2.7, 0.2)
        let l1 = easeOut(prog(t, 0.3, 0.32)), l2 = easeOut(prog(t, 1.0, 0.32))
        text(ctx, "Your Mac is full.", font(132, .heavy), .white, cx: W / 2, y: 340 + 30 * (1 - l1), alpha: l1 * out, kern: -2)
        text(ctx, "Of what?", font(132, .heavy), NSColor(srgbRed: 0.80, green: 0.50, blue: 1.0, alpha: 1), cx: W / 2, y: 520 + 30 * (1 - l2), alpha: l2 * out, kern: -2)
    }

    // 2. Reveal.
    if t >= 2.95 && t < 5.6 {
        let out = prog(t, 5.3, 0.2)
        let lift = -40 * easeIn(out)
        let ip = prog(t, 3.0, 0.5)
        let size = 250 * backOut(ip)
        if ip > 0 {
            ctx.saveGState()
            ctx.setAlpha(clamp(ip * 3) * (1 - out))
            ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 50, color: rgb(10, 80, 255, 0.55))
            drawImage(ctx, icon, CGRect(x: W / 2 - size / 2, y: 330 - size / 2 + lift, width: size, height: size))
            ctx.restoreGState()
        }
        let w1 = easeOut(prog(t, 3.15, 0.3)), w2 = easeOut(prog(t, 3.4, 0.3))
        text(ctx, "Spacewise", font(120, .bold), .white, cx: W / 2, y: 490 + 24 * (1 - w1) + lift, alpha: w1 * (1 - out), kern: -2)
        text(ctx, "See and free up your storage.", font(52, .medium), NSColor(white: 1, alpha: 0.72), cx: W / 2, y: 660 + 20 * (1 - w2) + lift, alpha: w2 * (1 - out))
    }

    // 3–6. The app.
    if t >= 5.5 && t < 18.05 {
        let enter = easeOut(prog(t, 5.5, 0.45))
        let exit = easeIn(prog(t, 17.82, 0.2))
        let frame = winRect.offsetBy(dx: 0, dy: 110 * (1 - enter) + 40 * exit)
        let scale = (0.94 + 0.06 * enter) * (1 - 0.04 * exit)
        let sframe = CGRect(x: frame.midX - frame.width * scale / 2, y: frame.midY - frame.height * scale / 2,
                            width: frame.width * scale, height: frame.height * scale)
        let (shot, ca, cs) = windowShot(t)
        let wa = enter * (1 - exit)
        drawWindow(ctx, shot: shot, frame: sframe, windowAlpha: wa, contentAlpha: ca, contentScale: cs)

        caption(ctx, "Scan your whole disk in seconds.", t: t, start: 5.65, end: 9.45)
        caption(ctx, "Bigger blocks use more space.", t: t, start: 9.6, end: 12.95)
        caption(ctx, "Exact duplicates, found by content.", t: t, start: 13.1, end: 15.45)
        caption(ctx, "Labelled Safe or Review. Trash first.", t: t, start: 15.6, end: 17.95)

        // Cursor: click Home on the beat.
        if t >= 5.9 && t < 7.0 {
            let m = easeInOut(prog(t, 5.95, 0.5))
            let from = CGPoint(x: 1750, y: 1180), to = CGPoint(x: 600, y: 452)
            let p = mapPoint(CGPoint(x: lerp(from.x, to.x, m), y: lerp(from.y, to.y, m)), zoom: shot.zoom, focus: shot.focus, frame: sframe)
            let press = t >= 6.5 && t < 6.62 ? 1.0 : 0.0
            drawRipple(ctx, p, prog(t, 6.5, 0.45))
            drawCursor(ctx, p, alpha: clamp((t - 5.9) / 0.15) * (1 - prog(t, 6.85, 0.15)), press: press)
        }
        // Explore: glide onto the biggest video block.
        if t >= 10.1 && t < 12.95 {
            let m = easeInOut(prog(t, 10.15, 0.9))
            let from = CGPoint(x: 2150, y: 1350), to = CGPoint(x: 720, y: 960)
            var q = CGPoint(x: lerp(from.x, to.x, m), y: lerp(from.y, to.y, m))
            q.x += 10 * sin((t - 11) * 2.4) * clamp(t - 11)
            let p = mapPoint(q, zoom: shot.zoom, focus: shot.focus, frame: sframe)
            drawCursor(ctx, p, alpha: clamp((t - 10.1) / 0.15) * (1 - prog(t, 12.75, 0.18)), press: 0)
        }
        // Duplicates: ring the first set and what it frees.
        if t >= 13.0 && t < 15.4 {
            let x = prog(t, 13.55, 0.35) * (1 - prog(t, 15.2, 0.18))
            drawHighlight(ctx, region: CGRect(x: 2330, y: 210, width: 205, height: 50), shot: shot, frame: sframe, x: x,
                          pulse: 0.5 + 0.5 * sin((t - 13.5) * .pi * 2))
        }
        // Cleanup: glide to Move to Trash and rest there.
        if t >= 15.95 && t < 17.85 {
            let m = easeInOut(prog(t, 16.0, 0.85))
            let from = CGPoint(x: 1300, y: 1000), to = CGPoint(x: 2405, y: 1550)
            let p = mapPoint(CGPoint(x: lerp(from.x, to.x, m), y: lerp(from.y, to.y, m)), zoom: shot.zoom, focus: shot.focus, frame: sframe)
            drawHighlight(ctx, region: CGRect(x: 2330, y: 1530, width: 160, height: 42), shot: shot, frame: sframe,
                          x: prog(t, 16.9, 0.25) * (1 - prog(t, 17.65, 0.18)), pulse: 0.5 + 0.5 * sin((t - 17) * .pi * 2))
            drawCursor(ctx, CGPoint(x: p.x - 4, y: p.y - 2), alpha: clamp((t - 15.95) / 0.15) * (1 - prog(t, 17.65, 0.18)), press: 0)
        }
    }

    // 7. Outro.
    if t >= 17.95 {
        drawTreemap(ctx, appearStart: 18.0, t: t, collapse: 0, alphaScale: 0.16, labels: false)
        let ip = prog(t, 18.0, 0.5)
        let size = 210 * backOut(ip)
        if ip > 0 {
            ctx.saveGState()
            ctx.setAlpha(clamp(ip * 3))
            ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 46, color: rgb(10, 80, 255, 0.55))
            drawImage(ctx, icon, CGRect(x: W / 2 - size / 2, y: 300 - size / 2, width: size, height: size))
            ctx.restoreGState()
        }
        let a1 = easeOut(prog(t, 18.15, 0.3)), a2 = easeOut(prog(t, 18.35, 0.3)), a3 = easeOut(prog(t, 18.55, 0.3))
        text(ctx, "Spacewise", font(124, .bold), .white, cx: W / 2, y: 440 + 24 * (1 - a1), alpha: a1, kern: -2)
        text(ctx, "Native for macOS. No tracking.", font(50, .medium), NSColor(white: 1, alpha: 0.72), cx: W / 2, y: 612 + 20 * (1 - a2), alpha: a2)
        text(ctx, "github.com/avinashchavan1/spacewise", NSFont.monospacedSystemFont(ofSize: 40, weight: .medium),
             NSColor(srgbRed: 0.38, green: 0.65, blue: 1.0, alpha: 1), cx: W / 2, y: 735 + 20 * (1 - a3), alpha: a3)
    }
    return ctx
}

// MARK: - Output

if mode == "video" {
    let frames = Int(DURATION * FPS)
    let out = FileHandle.standardOutput
    // Optional poster time: frame 0 shows that settled frame (platform thumbnails).
    let poster = args.count > 5 ? Double(args[5]) : nil
    for i in 0..<frames {
        let ctx = renderFrame(i == 0 ? (poster ?? 0) : Double(i) / FPS)
        let data = Data(bytes: ctx.data!, count: Int(W) * Int(H) * 4)
        out.write(data)
    }
} else {
    let outDir = args[5]
    for ts in args.dropFirst(6) {
        let t = Double(ts)!
        let img = renderFrame(t).makeImage()!
        let url = URL(fileURLWithPath: "\(outDir)/still-\(ts).png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }
}
