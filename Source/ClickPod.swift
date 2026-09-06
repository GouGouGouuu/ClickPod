import Cocoa
import SwiftUI
import SceneKit
import SQLite3

struct ThreadItem: Identifiable {
    let id: String, title: String, cwd: String, preview: String, model: String
    let updated: Double, archived: Bool, pinned: Bool, tokens: Int
    var project: String { URL(fileURLWithPath: cwd).lastPathComponent }
}
struct MenuItem { let title: String; let subtitle: String; let action: String }
struct Page { var title: String; var items: [MenuItem]; var selected = 0; var thread: ThreadItem? = nil; var offset = 0 }

final class Library: ObservableObject {
    @Published var threads: [ThreadItem] = []
    @Published var pages: [Page] = []
    @Published var error: String? = nil
    @Published var refreshed: Date? = nil
    @Published var sound = true
    @Published var inspection = false
    @Published var query = ""
    var screenChanged: (() -> Void)?
    var resetPose: (() -> Void)?
    var timer: Timer?
    var clickSound: NSSound?
    var page: Page { pages.last ?? homePage() }
    var projects: [String] { Array(Set(threads.map(\.project))).sorted() }
    init() {
        // A short, quiet click generated locally. No system volume is modified.
        var pcm = [Int16](repeating: 0, count: 240)
        for i in pcm.indices { pcm[i] = Int16(sin(Double(i) * 2.1) * exp(-Double(i)/35) * 4200) }
        var wav = Data(); func str(_ s: String) { wav.append(s.data(using: .ascii)!) }; func u32(_ n: UInt32) { var v = n.littleEndian; withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) } }; func u16(_ n: UInt16) { var v = n.littleEndian; withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) } }
        str("RIFF"); u32(UInt32(36+pcm.count*2)); str("WAVEfmt "); u32(16); u16(1); u16(1); u32(24000); u32(48000); u16(2); u16(16); str("data"); u32(UInt32(pcm.count*2)); pcm.withUnsafeBytes { wav.append(contentsOf: $0) }; clickSound = NSSound(data: wav)
        reload(); pages = [homePage()]
        timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in self?.reload() }
    }
    func homePage() -> Page {
        Page(title: "Codex", items: [
            MenuItem(title: "所有任务", subtitle: "\(threads.count)", action: "all"),
            MenuItem(title: "工作目录", subtitle: "\(projects.count)", action: "projects"),
            MenuItem(title: "置顶", subtitle: "\(threads.filter(\.pinned).count)", action: "pinned"),
            MenuItem(title: "归档", subtitle: "\(threads.filter(\.archived).count)", action: "archived"),
            MenuItem(title: "最近更新", subtitle: "", action: "recent"),
            MenuItem(title: "设置", subtitle: "", action: "settings")])
    }
    func reload() {
        let root = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex"
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: root).filter { $0.hasPrefix("state_") && $0.hasSuffix(".sqlite") }.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            guard let file = files.first else { throw NSError(domain: "ClickPod", code: 1, userInfo: [NSLocalizedDescriptionKey: "未找到 Codex 本地任务数据库"]) }
            var db: OpaquePointer?
            guard sqlite3_open_v2(root+"/"+file, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { if db != nil { sqlite3_close(db) }; throw NSError(domain: "ClickPod", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法读取 Codex 数据目录"]) }
            defer { sqlite3_close(db) }; sqlite3_busy_timeout(db, 1500)
            var statement: OpaquePointer?
            let sql = "SELECT id,title,cwd,preview,model,updated_at,archived,is_pinned,tokens_used,first_user_message FROM threads ORDER BY updated_at DESC"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw NSError(domain: "ClickPod", code: 3, userInfo: [NSLocalizedDescriptionKey: "Codex 数据格式已更改："+String(cString: sqlite3_errmsg(db))]) }
            defer { sqlite3_finalize(statement) }
            func field(_ i: Int32) -> String { sqlite3_column_text(statement,i).map { String(cString: $0) } ?? "" }
            var result: [ThreadItem] = []; var rc = sqlite3_step(statement)
            while rc == SQLITE_ROW {
                let title = field(1).isEmpty ? "未命名任务" : field(1)
                result.append(ThreadItem(id:field(0),title:title,cwd:field(2),preview:field(3).isEmpty ? field(9) : field(3),model:field(4),updated:sqlite3_column_double(statement,5),archived:sqlite3_column_int(statement,6) != 0,pinned:sqlite3_column_int(statement,7) != 0,tokens:Int(sqlite3_column_int64(statement,8))))
                rc = sqlite3_step(statement)
            }
            guard rc == SQLITE_DONE else { throw NSError(domain: "ClickPod", code: 4, userInfo: [NSLocalizedDescriptionKey: "读取任务失败，请重试"]) }
            threads = result; error = nil; refreshed = Date()
            if pages.count == 1 { let selected = pages[0].selected; pages[0] = homePage(); pages[0].selected = selected }
            if pages.count > 1, pages.last?.thread == nil { rebuildCurrentList() }
            if let current = pages.last?.thread, let latest = result.first(where: { $0.id == current.id }) { pages[pages.count-1].thread = latest }
            screenChanged?()
        } catch { self.error = error.localizedDescription; screenChanged?() }
    }
    func tick() { if sound { clickSound?.stop(); clickSound?.play() } }
    func move(_ delta: Int) {
        guard !pages.isEmpty else { return }; tick()
        if pages[pages.count-1].thread != nil { pages[pages.count-1].offset = max(0,min(detailLines().count-9,pages[pages.count-1].offset+delta)) }
        else { let n = page.items.count; if n > 0 { pages[pages.count-1].selected = max(0,min(n-1,page.selected+delta)) } }
        screenChanged?()
    }
    func back() { tick(); if pages.count > 1 { pages.removeLast() }; screenChanged?() }
    func home() { pages = [homePage()]; screenChanged?() }
    func list(_ title: String, _ ts: [ThreadItem]) { pages.append(Page(title:title,items:ts.map { MenuItem(title:$0.title,subtitle:$0.pinned ? "★" : "",action:"thread:"+$0.id) })); screenChanged?() }
    func rebuildCurrentList() {
        guard let last = pages.last else { return }; let selectedID = last.items.indices.contains(last.selected) ? last.items[last.selected].action : ""
        var ts: [ThreadItem]?
        switch last.title { case "所有任务": ts = threads; case "置顶": ts = threads.filter(\.pinned); case "归档": ts = threads.filter(\.archived); case "最近更新": ts = Array(threads.prefix(20)); case "搜索结果": ts = filtered; default: if projects.contains(last.title) { ts = threads.filter { $0.project == last.title } } }
        if let ts { pages[pages.count-1].items = ts.map { MenuItem(title:$0.title,subtitle:$0.pinned ? "★" : "",action:"thread:"+$0.id) }; pages[pages.count-1].selected = pages[pages.count-1].items.firstIndex { $0.action == selectedID } ?? min(last.selected,max(0,ts.count-1)) }
    }
    var filtered: [ThreadItem] { threads.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.project.localizedCaseInsensitiveContains(query) } }
    func search() { home(); list("搜索结果",filtered) }
    func select() {
        tick()
        if page.thread != nil { openThread(); return }
        guard page.items.indices.contains(page.selected) else { return }
        let a = page.items[page.selected].action
        switch a {
        case "all": list("所有任务",threads)
        case "projects": pages.append(Page(title:"工作目录",items:projects.map { p in MenuItem(title:p,subtitle:"\(threads.filter { $0.project == p }.count)",action:"project:"+p) }))
        case "pinned": list("置顶",threads.filter(\.pinned))
        case "archived": list("归档",threads.filter(\.archived))
        case "recent": list("最近更新",Array(threads.prefix(20)))
        case "settings": pages.append(Page(title:"设置",items:[MenuItem(title:"滚轮声音",subtitle:sound ? "开" : "关",action:"sound"),MenuItem(title:"立即同步",subtitle:"",action:"refresh"),MenuItem(title:"回到正面",subtitle:"",action:"reset")]))
        case "sound": sound.toggle(); pages[pages.count-1].items[0] = MenuItem(title:"滚轮声音",subtitle:sound ? "开" : "关",action:"sound")
        case "refresh": reload()
        case "reset": resetPose?()
        default:
            if a.hasPrefix("thread:"), let t = threads.first(where: { "thread:"+$0.id == a }) { pages.append(Page(title:"任务详情",items:[],thread:t)) }
            if a.hasPrefix("project:") { let p = String(a.dropFirst(8)); list(p,threads.filter { $0.project == p }) }
        }
        screenChanged?()
    }
    func openThread() { if let t = page.thread, let url = URL(string:"codex://threads/"+t.id) { NSWorkspace.shared.open(url) } }
    func detailLines() -> [String] {
        guard let t = page.thread else { return [] }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
        let text = t.title+"\n\n目录 · "+t.project+"\n更新 · "+df.string(from:Date(timeIntervalSince1970:t.updated))+"\n模型 · "+(t.model.isEmpty ? "默认" : t.model)+"\n状态 · "+(t.archived ? "已归档" : "未归档")+"\n\n"+(t.preview.isEmpty ? "暂无摘要。按中央键在 Codex 中打开。" : t.preview)
        var lines: [String] = []
        for paragraph in text.components(separatedBy:"\n") {
            var line = ""; var width: CGFloat = 0
            for c in paragraph { let s = String(c); let w = (s as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:22,weight:.medium)]).width
                if width+w > 580 { lines.append(line); line = ""; width = 0 }; line += s; width += w }
            lines.append(line)
        }; return lines
    }
}

struct Mesh: Decodable { let name: String; let vertices, normals: [Float]; let indices: [Int32]; let color: [Double]; let metalness, roughness: Double }

final class PodView: SCNView {
    let library: Library; let pod = SCNNode(); let lcd = SCNMaterial()
    var startPoint = CGPoint.zero; var lastPoint = CGPoint.zero; var lastAngle: CGFloat?; var angleAccum: CGFloat = 0; var wheelGesture = false; var moved = false; var scrollAccum: CGFloat = 0
    init(_ library: Library) {
        self.library = library; super.init(frame:.zero,options:[SCNView.Option.preferredRenderingAPI.rawValue:SCNRenderingAPI.metal.rawValue])
        let scene = SCNScene(); self.scene = scene
        backgroundColor = .clear; antialiasingMode = .multisampling4X; rendersContinuously = false
        scene.rootNode.addChildNode(pod)
        do {
            guard let url = Bundle.main.url(forResource:"ipod-mesh",withExtension:"json") else { throw NSError(domain:"ClickPod",code:5,userInfo:[NSLocalizedDescriptionKey:"缺少模型资源，请重新构建应用"]) }
            let meshes = try JSONDecoder().decode([Mesh].self,from:Data(contentsOf:url))
            for mesh in meshes {
                var vs: [SCNVector3] = []; var ns: [SCNVector3] = []
                for i in stride(from:0,to:mesh.vertices.count,by:3) { vs.append(SCNVector3(mesh.vertices[i],mesh.vertices[i+1],mesh.vertices[i+2])); ns.append(SCNVector3(mesh.normals[i],mesh.normals[i+1],mesh.normals[i+2])) }
                let g = SCNGeometry(sources:[SCNGeometrySource(vertices:vs),SCNGeometrySource(normals:ns)],elements:[SCNGeometryElement(indices:mesh.indices,primitiveType:.triangles)])
                let m = SCNMaterial(); m.lightingModel = .physicallyBased; m.diffuse.contents = NSColor(calibratedRed:mesh.color[0],green:mesh.color[1],blue:mesh.color[2],alpha:1); m.metalness.contents = mesh.metalness; m.roughness.contents = mesh.roughness
                g.materials = [m]; let n = SCNNode(geometry:g); n.name = mesh.name; pod.addChildNode(n)
            }
        } catch { library.error = "3D 模型加载失败：\(error.localizedDescription)" }
        let display = SCNPlane(width:4.60,height:3.44); display.cornerRadius = 0.035
        lcd.lightingModel = .constant; lcd.diffuse.magnificationFilter = .linear; lcd.diffuse.minificationFilter = .linear; lcd.isDoubleSided = false
        display.materials = [lcd]; let screen = SCNNode(geometry:display); screen.position = SCNVector3(0,2.12,0.618); screen.name = "LCD"; pod.addChildNode(screen)
        addLabel("MENU",x:0,y:-0.99,size:0.30)
        addLabel("◀◀",x:-1.48,y:-2.36,size:0.30)
        addLabel("▶▶",x:1.48,y:-2.36,size:0.30)
        addLabel("▶Ⅱ",x:0,y:-3.79,size:0.30)
        let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera!.usesOrthographicProjection = true; cam.camera!.orthographicScale = 6.55; cam.position = SCNVector3(0,0,22); scene.rootNode.addChildNode(cam); pointOfView = cam
        func light(_ pos: SCNVector3,_ intensity: CGFloat,_ color: NSColor,_ type: SCNLight.LightType = .omni) {
            let n = SCNNode(); n.light = SCNLight(); n.light!.type = type; n.light!.intensity = intensity; n.light!.color = color; n.position = pos; scene.rootNode.addChildNode(n)
        }
        light(SCNVector3(-5,7,10),420,NSColor(calibratedRed:1,green:0.97,blue:0.9,alpha:1))
        light(SCNVector3(7,-1,8),220,NSColor(calibratedRed:0.76,green:0.84,blue:1,alpha:1))
        light(SCNVector3(0,0,0),160,.white,.ambient)
        // A generated studio environment gives the steel back broad, soft reflections.
        let env = NSImage(size:NSSize(width:1024,height:512)); env.lockFocus(); NSColor(white:0.3,alpha:1).setFill(); NSRect(x:0,y:0,width:1024,height:512).fill(); NSColor(white:0.95,alpha:1).setFill(); NSRect(x:120,y:40,width:180,height:420).fill(); NSColor(white:0.7,alpha:1).setFill(); NSRect(x:700,y:100,width:260,height:330).fill(); env.unlockFocus(); scene.lightingEnvironment.contents = env; scene.lightingEnvironment.intensity = 0.4
        library.screenChanged = { [weak self] in self?.updateScreen() }
        library.resetPose = { [weak self] in self?.reset() }
        updateScreen(); setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("3D iPod，使用方向键选择，回车进入，Escape 返回")
    }
    required init?(coder:NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }
    func addLabel(_ text: String,x:Float,y:Float,size:CGFloat) {
        let img = NSImage(size:NSSize(width:256,height:64)); img.lockFocus(); NSColor.clear.setFill(); NSRect(x:0,y:0,width:256,height:64).fill()
        let attrs: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:36,weight:.bold),.foregroundColor:NSColor(white:0.35,alpha:1)]
        let sz = (text as NSString).size(withAttributes:attrs); (text as NSString).draw(at:NSPoint(x:(256-sz.width)/2,y:(64-sz.height)/2),withAttributes:attrs); img.unlockFocus()
        let p = SCNPlane(width:size*4,height:size); let m = SCNMaterial(); m.diffuse.contents = img; m.lightingModel = .constant; m.writesToDepthBuffer = false; p.materials = [m]
        let n = SCNNode(geometry:p); n.position = SCNVector3(x,y,0.621); n.name = "Label"; pod.addChildNode(n)
    }
    func reset() { SCNTransaction.begin(); SCNTransaction.animationDuration = 0.45; pod.eulerAngles = SCNVector3Zero; SCNTransaction.commit(); library.inspection = false }
    func updateScreen() {
        let w: CGFloat = 640, h: CGFloat = 480
        let image = NSImage(size:NSSize(width:w,height:h)); image.lockFocusFlipped(true)
        let ink = NSColor(calibratedRed:0.08,green:0.15,blue:0.25,alpha:1)
        let bg = NSColor(calibratedRed:0.76,green:0.84,blue:0.87,alpha:1)
        bg.setFill(); NSRect(x:0,y:0,width:w,height:h).fill()
        // Restrained scan lines keep the display reminiscent of the original monochrome LCD.
        NSColor(white:0,alpha:0.025).setFill(); for y in stride(from:0,to:480,by:3) { NSRect(x:0,y:y,width:640,height:1).fill() }
        func text(_ s:String,_ r:NSRect,_ size:CGFloat = 27,_ bold:Bool = false,_ color:NSColor? = nil) {
            let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail
            (s as NSString).draw(in:r,withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:bold ? .semibold:.medium),.foregroundColor:color ?? ink,.paragraphStyle:p])
        }
        text(library.page.title,NSRect(x:20,y:13,width:500,height:37),30,true)
        ink.setStroke(); let batt = NSBezierPath(rect:NSRect(x:560,y:21,width:52,height:23)); batt.lineWidth = 3; batt.stroke(); ink.setFill(); NSRect(x:614,y:27,width:5,height:11).fill(); NSRect(x:565,y:26,width:40,height:13).fill(); NSRect(x:0,y:62,width:640,height:2).fill()
        let page = library.page
        if let err = library.error {
            text("同步遇到问题",NSRect(x:22,y:100,width:585,height:38),28,true)
            text(err,NSRect(x:22,y:150,width:585,height:180),23)
            text("点击窗口中的同步按钮重试",NSRect(x:22,y:350,width:585,height:38),22)
        } else if page.thread != nil {
            let lines = library.detailLines(); let offset = min(page.offset,max(0,lines.count-9))
            for (i,line) in lines.dropFirst(offset).prefix(9).enumerated() { text(line,NSRect(x:20,y:80+CGFloat(i)*36,width:590,height:34),22,i == 0 && offset == 0) }
            text("中央键 · 在 Codex 中打开",NSRect(x:20,y:439,width:590,height:30),21,true)
            drawScroll(offset:offset,total:lines.count,visible:9,ink:ink)
        } else if page.items.isEmpty {
            text("这里还没有任务",NSRect(x:25,y:190,width:580,height:42),29,true)
            text("MENU 返回上一级",NSRect(x:25,y:240,width:580,height:38),23)
        } else {
            let start = max(0,min(page.selected-5,page.items.count-6))
            for (i,item) in page.items.dropFirst(start).prefix(6).enumerated() {
                let y = CGFloat(75+i*58); let selected = start+i == page.selected
                if selected { ink.setFill(); NSRect(x:9,y:y-1,width:612,height:55).fill() }
                text(item.title,NSRect(x:22,y:y+9,width:495,height:38),27,true,selected ? bg:ink)
                text(item.subtitle,NSRect(x:516,y:y+13,width: 60,height:32),21,false,selected ? bg:ink)
                text("›",NSRect(x:591,y:y+2,width:25,height:45),35,true,selected ? bg:ink)
            }
            text("\(page.selected+1) / \(page.items.count)",NSRect(x:21,y:439,width:590,height:29),21)
            drawScroll(offset:start,total:page.items.count,visible:6,ink:ink)
        }
        image.unlockFocus(); lcd.diffuse.contents = image; needsDisplay = true
        setAccessibilityValue(page.thread?.title ?? (page.items.indices.contains(page.selected) ? page.title+", "+page.items[page.selected].title : page.title))
    }
    func drawScroll(offset:Int,total:Int,visible:Int,ink:NSColor) { guard total>visible else { return }; let track:CGFloat = 342; ink.withAlphaComponent(0.2).setFill(); NSRect(x:630,y:80,width:4,height:track).fill(); ink.setFill(); let size = max(20,track*CGFloat(visible)/CGFloat(total)); NSRect(x:630,y:80+(track-size)*CGFloat(offset)/CGFloat(max(1,total-visible)),width:4,height:size).fill() }
    func local(_ e:NSEvent) -> SCNVector3? {
        let p = convert(e.locationInWindow,from:nil)
        guard let hit = hitTest(p,options:[.searchMode:SCNHitTestSearchMode.closest.rawValue]).first else { return nil }
        return pod.convertPosition(hit.worldCoordinates,from:nil)
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self); startPoint = convert(event.locationInWindow,from:nil); lastPoint = startPoint; moved = false; angleAccum = 0; wheelGesture = false; lastAngle = nil
        if !library.inspection, let p = local(event), p.z > 0.5 { let r = hypot(p.x,p.y+2.36); if r > 0.80 && r < 2.15 { wheelGesture = true; lastAngle = atan2(CGFloat(p.y+2.36),CGFloat(p.x)) } }
    }
    override func mouseDragged(with event:NSEvent) {
        let p = convert(event.locationInWindow,from:nil); let dx = p.x-lastPoint.x; let dy = p.y-lastPoint.y; lastPoint = p; if hypot(p.x-startPoint.x,p.y-startPoint.y)>4 { moved = true }
        if wheelGesture, let local = local(event) {
            let a = atan2(CGFloat(local.y+2.36),CGFloat(local.x)); if let last = lastAngle { var d = a-last; if d > .pi { d -= 2 * .pi }; if d < -.pi { d += 2 * .pi }; angleAccum -= d
                while abs(angleAccum) > 0.23 { let step = angleAccum>0 ? 1:-1; library.move(step); angleAccum -= CGFloat(step)*0.23 } }; lastAngle = a
        } else if moved { pod.eulerAngles.y += dx*0.009; pod.eulerAngles.x = max(-0.65,min(0.65,pod.eulerAngles.x-dy*0.007)) }
    }
    override func mouseUp(with event:NSEvent) {
        guard !moved,!library.inspection,let p = local(event),p.z > 0.5 else { return }
        let x = p.x, y = p.y+2.36, r = hypot(x,y)
        if r < 0.8 { library.select() }
        else if r < 2.15 { if y > abs(x) { library.back() } else if -y > abs(x) { library.select() } else { library.move(x>0 ? 1:-1) } }
        else if p.y > 0.4 && p.y < 3.8 { library.select() }
    }
    override func scrollWheel(with event:NSEvent) {
        scrollAccum += event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? -1:1)
        let threshold:CGFloat = event.hasPreciseScrollingDeltas ? 16:1
        if abs(scrollAccum) >= threshold { let n = scrollAccum>0 ? 1:-1; library.move(n); scrollAccum = 0 }
    }
    override func keyDown(with event:NSEvent) {
        switch event.keyCode { case 125,124:library.move(1); case 126:library.move(-1); case 123,53,51:library.back(); case 36,49:library.select(); case 115:library.home(); default:super.keyDown(with:event) }
    }
}
struct ScenePane: NSViewRepresentable {
    let library: Library
    func makeNSView(context:Context) -> PodView { PodView(library) }
    func updateNSView(_ view:PodView,context:Context) {}
}

struct ContentView: View {
    @ObservedObject var library: Library
    let cream = Color(red:0.91,green:0.91,blue:0.86)
    var body: some View {
        ZStack {
            Color(red:0.055,green:0.063,blue:0.066)
            RadialGradient(colors:[Color(red:0.17,green:0.19,blue:0.19),.clear],center:UnitPoint(x:0.68,y:0.4),startRadius:10,endRadius:520)
            HStack(spacing:0) {
                VStack(alignment:.leading,spacing:0) {
                    HStack(spacing:9) { Image(systemName:"circle.hexagongrid.fill").font(.system(size:19)); Text("CLICKPOD").font(.system(size:13,weight:.bold,design:.monospaced)).tracking(3) }.foregroundStyle(cream)
                    Spacer().frame(height:65)
                    Text("A thousand ideas.\nIn your pocket.").font(.system(size:34,weight:.medium,design:.serif)).tracking(-1.1).lineSpacing(-1).foregroundStyle(cream).fixedSize(horizontal:false,vertical:true)
                    Text("把你的 Codex 世界，\n装进熟悉的滚轮里。").font(.system(size:14)).lineSpacing(7).foregroundStyle(cream.opacity(0.47)).padding(.top,22)
                    HStack(alignment:.firstTextBaseline,spacing:28) { stat("\(library.threads.count)","THREADS"); stat("\(library.projects.count)","FOLDERS") }.padding(.top,38)
                    Rectangle().fill(cream.opacity(0.12)).frame(height:1).padding(.vertical,28)
                    HStack { Image(systemName:"magnifyingglass").foregroundStyle(cream.opacity(0.4)); TextField("搜索任务或目录",text:$library.query).textFieldStyle(.plain).font(.system(size:13)).onSubmit { library.search() } }.padding(12).background(cream.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius:7))
                    if !library.query.isEmpty { Button("在 iPod 中查看 \(library.filtered.count) 个结果") { library.search() }.buttonStyle(.plain).font(.system(size:12)).foregroundStyle(cream.opacity(0.7)).padding(.top,10) }
                    Spacer()
                    VStack(alignment:.leading,spacing:13) { hint("cursorarrow.motionlines","沿滚轮画圈，浏览任务"); hint("return","中央键进入 · MENU 返回"); hint("rotate.3d","拖动机身，转动视角") }
                    HStack(spacing:7) { Circle().fill(library.error == nil ? Color(red:0.64,green:0.78,blue:0.43):.orange).frame(width:5,height:5); Text(library.error == nil ? "本地资料库 · 每 12 秒同步":"资料库连接异常").font(.system(size:10,design:.monospaced)).foregroundStyle(cream.opacity(0.4)) }.padding(.top,32)
                }.frame(width:292).padding(.leading,46).padding(.vertical,42)
                ZStack(alignment:.bottom) {
                    Ellipse().fill(.black.opacity(0.5)).frame(width:270,height:30).blur(radius:18).offset(y:-46)
                    ScenePane(library:library).padding(.bottom,30)
                    HStack(spacing:18) {
                        Button { library.back() } label: { Label("返回",systemImage:"chevron.left") }
                        Button { library.home(); library.resetPose?() } label: { Label("主菜单",systemImage:"house") }
                        Button { library.inspection.toggle() } label: { Label(library.inspection ? "结束旋转":"旋转",systemImage:"rotate.3d") }
                        Button { library.resetPose?() } label: { Label("正面",systemImage:"rectangle.portrait") }
                        Button { library.reload() } label: { Image(systemName:"arrow.clockwise") }
                    }.font(.system(size:11)).buttonStyle(.plain).foregroundStyle(cream.opacity(0.58)).padding(.horizontal,18).padding(.vertical,12).background(.black.opacity(0.2)).clipShape(Capsule()).padding(.bottom,22)
                }.padding(.leading,16)
            }
            VStack { HStack { Spacer(); Text("DESIGNED FOR YOUR TRAIN OF THOUGHT").font(.system(size:9,design:.monospaced)).tracking(1.7).foregroundStyle(cream.opacity(0.26)).padding(.trailing,30) }; Spacer() }.padding(.top,26)
        }.frame(minWidth:1000,minHeight:730).preferredColorScheme(.dark)
    }
    func stat(_ value:String,_ label:String) -> some View { VStack(alignment:.leading,spacing:5) { Text(value).font(.system(size:33,weight:.light,design:.monospaced)).foregroundStyle(cream); Text(label).font(.system(size:9,weight:.medium,design:.monospaced)).tracking(2).foregroundStyle(cream.opacity(0.35)) } }
    func hint(_ icon:String,_ text:String) -> some View { HStack(spacing:11) { Image(systemName:icon).frame(width:17); Text(text) }.font(.system(size:11)).foregroundStyle(cream.opacity(0.4)) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window:NSWindow!; var library:Library!
    func applicationDidFinishLaunching(_ notification:Notification) {
        library = Library()
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:780),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title = "ClickPod — Your Codex, on repeat"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden; window.backgroundColor = NSColor(white:0.06,alpha:1); window.minSize = NSSize(width:1000,height:750)
        window.contentView = NSHostingView(rootView:ContentView(library:library)); window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        let main = NSMenu(); let appItem = NSMenuItem(); main.addItem(appItem); let app = NSMenu(); appItem.submenu = app
        app.addItem(withTitle:"关于 ClickPod",action:#selector(about),keyEquivalent:""); app.addItem(.separator()); app.addItem(withTitle:"退出 ClickPod",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let navItem = NSMenuItem(); navItem.title = "导航"; main.addItem(navItem); let nav = NSMenu(title:"导航"); navItem.submenu = nav
        for (title,action,key) in [("主菜单",#selector(home),"h"),("同步任务",#selector(refresh),"r"),("回到正面",#selector(reset),"0")] { let i = nav.addItem(withTitle:title,action:action,keyEquivalent:key); i.target = self }
        let editItem = NSMenuItem(); editItem.title = "编辑"; main.addItem(editItem); let edit = NSMenu(title:"编辑"); editItem.submenu = edit
        for (title,action,key) in [("剪切",#selector(NSText.cut(_:)),"x"),("复制",#selector(NSText.copy(_:)),"c"),("粘贴",#selector(NSText.paste(_:)),"v"),("全选",#selector(NSText.selectAll(_:)),"a")] { edit.addItem(withTitle:title,action:action,keyEquivalent:key) }
        NSApp.mainMenu = main
        
    }
    @objc func home() { library.home() }
    @objc func refresh() { library.reload() }
    @objc func reset() { library.resetPose?() }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"ClickPod",.applicationVersion:"1.0",.credits:NSAttributedString(string:"A local Codex library inside a Blender-built iPod.\nIndependent homage. Not affiliated with Apple.")]) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }

}
func selfTest(_ library: Library) {
        precondition(library.error == nil,library.error ?? "")
        let n = library.threads.count; library.select(); precondition(library.page.items.count == n)
        library.move(10000); precondition(library.page.selected == max(0,n-1)); library.move(-10000); precondition(library.page.selected == 0)
        if n>0 { library.select(); precondition(library.page.thread != nil); library.move(10000); precondition(library.page.offset >= 0); library.back() }
        library.home(); library.move(1); library.select(); precondition(library.page.items.count == library.projects.count)
        library.home(); library.move(3); library.select(); precondition(library.page.items.count == library.threads.filter(\.archived).count)
        library.query = "__no_matching_thread_8c5a__"; library.search(); precondition(library.page.items.isEmpty); library.select(); library.back(); library.query = ""; library.home()
        print("SELF-TEST PASSED: \(n) threads, \(library.projects.count) folders; navigation, bounds, detail, archive, empty search")
        if let path = ProcessInfo.processInfo.environment["CLICKPOD_TEST_RESULT"] { try? "PASS \(n) threads\n".write(toFile:path,atomically:true,encoding:.utf8) }
    }
if CommandLine.arguments.contains("--self-test-error") { let l = Library(); precondition(l.error != nil); precondition(l.threads.isEmpty); print("PASS: missing library shows a recoverable error"); exit(0) }
if CommandLine.arguments.contains("--self-test") { selfTest(Library()); exit(0) }
let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
