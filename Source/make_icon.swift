import Cocoa
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath:output,withIntermediateDirectories:true)
var chunks = Data()
for size in [16,32,64,128,256,512,1024] {
 let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep)!
 let t = NSAffineTransform(); t.scale(by:CGFloat(size)/1024); t.concat()
 let bg = NSBezierPath(roundedRect:NSRect(x:25,y:25,width:974,height:974),xRadius:210,yRadius:210)
 NSGradient(starting:NSColor(calibratedRed:0.20,green:0.24,blue:0.24,alpha:1),ending:NSColor(white:0.065,alpha:1))!.draw(in:bg,angle:-90)
 let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.6); shadow.shadowBlurRadius = 38; shadow.shadowOffset = NSSize(width:0,height:-20); shadow.set()
 let body = NSBezierPath(roundedRect:NSRect(x:268,y:124,width:488,height:782),xRadius:46,yRadius:46)
 NSGradient(starting:.white,ending:NSColor(white:0.78,alpha:1))!.draw(in:body,angle:-80); NSShadow().set()
 NSColor(white:0.19,alpha:1).setFill(); NSBezierPath(roundedRect:NSRect(x:311,y:511,width:402,height:312),xRadius:12,yRadius:12).fill()
 NSColor(calibratedRed:0.76,green:0.85,blue:0.88,alpha:1).setFill(); NSRect(x:326,y:526,width:372,height:282).fill()
 let ink = NSColor(calibratedRed:0.08,green:0.16,blue:0.25,alpha:1)
 ("Codex" as NSString).draw(at:NSPoint(x:344,y:751),withAttributes:[.font:NSFont.systemFont(ofSize:35,weight:.bold),.foregroundColor:ink])
 ink.setFill(); NSRect(x:338,y:688,width:345,height:44).fill()
 for y in [635,589] { ink.withAlphaComponent(0.7).setFill(); NSBezierPath(roundedRect:NSRect(x:347,y:y,width:210,height:13),xRadius:4,yRadius:4).fill() }
 let wheel = NSBezierPath(ovalIn:NSRect(x:350,y:166,width:324,height:324)); NSGradient(starting:NSColor(white:0.86,alpha:1),ending:NSColor(white:0.66,alpha:1))!.draw(in:wheel,angle:-90)
 NSColor(white:0.95,alpha:1).setFill(); NSBezierPath(ovalIn:NSRect(x:450,y:266,width:124,height:124)).fill()
 ("MENU" as NSString).draw(at:NSPoint(x:475,y:438),withAttributes:[.font:NSFont.systemFont(ofSize:23,weight:.bold),.foregroundColor:NSColor(white:0.35,alpha:1)])
 NSGraphicsContext.restoreGraphicsState()
 let data = rep.representation(using:.png,properties:[:])!
 let type = [16:"icp4",32:"icp5",64:"icp6",128:"ic07",256:"ic08",512:"ic09",1024:"ic10"][size]!
 chunks.append(type.data(using:.ascii)!); var length = UInt32(data.count+8).bigEndian; withUnsafeBytes(of:&length) { chunks.append(contentsOf:$0) }; chunks.append(data)
 let filename = size == 1024 ? "icon_512x512@2x.png":"icon_\(size)x\(size).png"
 try data.write(to:URL(fileURLWithPath:output+"/"+filename))
 if [32,64,256,512].contains(size) { try data.write(to:URL(fileURLWithPath:output+"/icon_\(size/2)x\(size/2)@2x.png")) }
}

var icns = Data("icns".utf8); var total = UInt32(chunks.count+8).bigEndian; withUnsafeBytes(of:&total) { icns.append(contentsOf:$0) }; icns.append(chunks); try icns.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
