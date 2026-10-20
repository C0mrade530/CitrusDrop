import AppKit
let destination = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let image = NSImage(size:NSSize(width:size,height:size))
    image.lockFocus()
    let scale = CGFloat(size)/1024
    let transform = NSAffineTransform(); transform.scale(by:scale); transform.concat()
    NSColor(calibratedRed:0.055,green:0.071,blue:0.094,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:40,y:40,width:944,height:944),xRadius:220,yRadius:220).fill()
    NSColor(calibratedRed:1,green:0.62,blue:0.27,alpha:1).setStroke()
    let path = NSBezierPath(); path.lineWidth = 65; path.lineCapStyle = .round
    path.appendArc(withCenter:NSPoint(x:512,y:512),radius:240,startAngle:35,endAngle:175)
    path.stroke()
    let lower = NSBezierPath(); lower.lineWidth = 65; lower.lineCapStyle = .round
    lower.appendArc(withCenter:NSPoint(x:512,y:512),radius:240,startAngle:215,endAngle:355); lower.stroke()
    NSColor(calibratedRed:1,green:0.62,blue:0.27,alpha:1).setFill()
    let arrow = NSBezierPath(); arrow.move(to:NSPoint(x:270,y:620)); arrow.line(to:NSPoint(x:242,y:470)); arrow.line(to:NSPoint(x:390,y:510)); arrow.close(); arrow.fill()
    let arrow2 = NSBezierPath(); arrow2.move(to:NSPoint(x:754,y:404)); arrow2.line(to:NSPoint(x:782,y:554)); arrow2.line(to:NSPoint(x:634,y:514)); arrow2.close(); arrow2.fill()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
    let data = bitmap.representation(using:.png,properties:[:])!
    let filename: String
    switch size { case 16: filename="icon_16x16.png";case 32:filename="icon_16x16@2x.png";case 64:filename="icon_32x32@2x.png";case 128:filename="icon_128x128.png";case 256:filename="icon_128x128@2x.png";case 512:filename="icon_256x256@2x.png";default:filename="icon_512x512@2x.png" }
    try data.write(to:destination.appendingPathComponent(filename))
}
