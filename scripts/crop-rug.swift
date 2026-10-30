import AppKit
// usage: crop in.jpg out.jpg [maxWidth]
// Finds the rug in a museum photo: background from the corners, rug = rows/cols mostly unlike it.
let a = CommandLine.arguments
guard let src = NSImage(contentsOfFile: a[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("bad image") }
let maxW = a.count > 3 ? Int(a[3])! : 2400
// work on a small copy for detection
let dw = 400, dh = Int(Double(src.height) * 400 / Double(src.width))
var px = [UInt8](repeating: 0, count: dw * dh * 4)
let dctx = CGContext(data: &px, width: dw, height: dh, bitsPerComponent: 8, bytesPerRow: dw * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
dctx.draw(src, in: CGRect(x: 0, y: 0, width: dw, height: dh))
func p(_ x: Int, _ y: Int) -> (Double, Double, Double) { let i = (y * dw + x) * 4; return (Double(px[i]), Double(px[i+1]), Double(px[i+2])) }
var bg = [(Double, Double, Double)]()
for (cx, cy) in [(0, 0), (dw - 6, 0), (0, dh - 6), (dw - 6, dh - 6)] { for y in cy..<cy+6 { for x in cx..<cx+6 { bg.append(p(x, y)) } } }
func far(_ c: (Double, Double, Double)) -> Bool { bg.allSatisfy { b in abs(c.0-b.0) + abs(c.1-b.1) + abs(c.2-b.2) > 60 } }
/// Rows and columns where at least `share` of the span between lo and hi isn't backdrop.
func span(_ lo: (Int, Int), _ hi: (Int, Int), _ share: Double) -> (x: ClosedRange<Int>, y: ClosedRange<Int>)? {
    var colHit = [Int](repeating: 0, count: dw), rowHit = [Int](repeating: 0, count: dh)
    for y in lo.1...hi.1 { for x in lo.0...hi.0 where far(p(x, y)) { colHit[x] += 1; rowHit[y] += 1 } }
    let h = Double(hi.1 - lo.1 + 1), w = Double(hi.0 - lo.0 + 1)
    let cols = colHit.indices.filter { Double(colHit[$0]) > h * share }, rows = rowHit.indices.filter { Double(rowHit[$0]) > w * share }
    guard let x0 = cols.first, let x1 = cols.last, let y0 = rows.first, let y1 = rows.last else { return nil }
    return (x0...x1, y0...y1)
}
// First the rough box, measured against the whole photo. Then again against the rug's own width and
// height: 80% of the rug, so a worn row still counts but a row of fringe strands, with backdrop
// showing between them, does not (Underrug draws its own fringe).
guard let rough = span((0, 0), (dw - 1, dh - 1), 0.5),
      let fine = span((rough.x.lowerBound, rough.y.lowerBound), (rough.x.upperBound, rough.y.upperBound), 0.8) else { fatalError("no rug found") }
let x0 = fine.x.lowerBound, x1 = fine.x.upperBound, y0 = fine.y.lowerBound, y1 = fine.y.upperBound
let s = Double(src.width) / Double(dw)
// trim a hair more so no background sliver survives
let inset = 0.012
let w = Double(x1 - x0), h = Double(y1 - y0)
var r = CGRect(x: (Double(x0) + w * inset) * s, y: (Double(y0) + h * inset) * s, width: w * (1 - 2 * inset) * s, height: h * (1 - 2 * inset) * s)
r = r.integral.intersection(CGRect(x: 0, y: 0, width: src.width, height: src.height))
// a bitmap context's first row in memory is the top of the image, and cropping(to:) also measures
// from the top-left, so the rows found above map straight across
guard let cut = src.cropping(to: r) else { fatalError("crop failed") }
// landscape, long side capped
let rotate = cut.height > cut.width
let ow = rotate ? cut.height : cut.width, oh = rotate ? cut.width : cut.height
let k = min(1, Double(maxW) / Double(ow))
let W = Int(Double(ow) * k), H = Int(Double(oh) * k)
let octx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
octx.interpolationQuality = .high
if rotate { octx.translateBy(x: CGFloat(W), y: 0); octx.rotate(by: .pi / 2); octx.draw(cut, in: CGRect(x: 0, y: 0, width: H, height: W)) }
else { octx.draw(cut, in: CGRect(x: 0, y: 0, width: W, height: H)) }
let rep = NSBitmapImageRep(cgImage: octx.makeImage()!)
try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.78])!.write(to: URL(fileURLWithPath: a[2]))
print(a[2], W, "x", H, "aspect", String(format: "%.2f", Double(W) / Double(H)))
