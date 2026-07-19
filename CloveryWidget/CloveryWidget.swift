import WidgetKit
import SwiftUI

// ═══════════════════════════════════════════
// MARK: - Data
// ═══════════════════════════════════════════

struct DiaryEntry: Codable {
    let id: String?; let date: String?; let lucky: String?
    let mood: String?; let isWelcome: Bool?; let tags: [String]?
}

struct CD {
    let entries: [DiaryEntry]; let name: String; let streak: Int
    let todayEntries: [DiaryEntry]; let uniqueDays: [String]
    let totalClovers: Int; let leafCount: Int
    let fontName: String; let palette: String; let lang: String

    static func load() -> CD {
        let s = UserDefaults(suiteName: "group.com.clovery.app")
        let name = s?.string(forKey: "widget_name") ?? ""
        let raw = s?.string(forKey: "widget_entries") ?? "[]"
        let fontName =
            s?.string(forKey: "clovery_font_selection") ??
            s?.string(forKey: "widget_font") ??
            "Gaegu"
        let palette = s?.string(forKey: "widget_palette") ?? "clover"
        let lang = s?.string(forKey: "widget_lang") ?? "zh"
        var all: [DiaryEntry] = []
        if let data = raw.data(using: .utf8) { all = (try? JSONDecoder().decode([DiaryEntry].self, from: data)) ?? [] }
        let real = all.filter { $0.isWelcome != true }
        let today = tStr()
        let days = Array(Set(real.compactMap { $0.date })).sorted()
        let dc = days.count
        return CD(entries: real, name: name, streak: stk(Set(days), today),
                  todayEntries: real.filter { $0.date == today }, uniqueDays: days,
                  totalClovers: dc/4, leafCount: dc%4, fontName: fontName, palette: palette, lang: lang)
    }
    static func tStr() -> String { let f=DateFormatter(); f.dateFormat="yyyy-MM-dd"; f.timeZone = .current; return f.string(from:Date()) }
    static func stk(_ days: Set<String>, _ today: String) -> Int {
        let c=Calendar.current,n=Date(),f=DateFormatter(); f.dateFormat="yyyy-MM-dd"; f.timeZone = .current
        let o=days.contains(today) ? 0:1
        if !days.contains(f.string(from:c.date(byAdding:.day,value:-o,to:n)!)){return 0}
        var s=0; while days.contains(f.string(from:c.date(byAdding:.day,value:-(o+s),to:n)!)){s+=1}; return s
    }
    var ps: String {
        switch fontName {
        case "System":
            ""
        case "NotoSerifSC":
            "NotoSerifSC-ExtraLight"
        case "NaiChaTi":
            "BoBoNaiChaTi"
        default:
            lang == "zh" ? "YLHZYS" :
                lang == "ja" ? "Yomogi-Regular" : "Gaegu-Regular"
        }
    }

    var psB: String {
        switch fontName {
        case "System":
            ""
        case "NotoSerifSC":
            "NotoSerifSC-ExtraLight"
        case "NaiChaTi":
            "BoBoNaiChaTi"
        default:
            lang == "zh" ? "YLHZYS" :
                lang == "ja" ? "Yomogi-Regular" : "Gaegu-Bold"
        }
    }

    var isSys: Bool {
        fontName == "System"
    }
}
func af(_ d:CD,_ sz:CGFloat,bold:Bool=false)->Font{
    d.isSys ? .system(size:sz,weight:bold ? .bold:.regular,design:.rounded) : .custom(bold ? d.psB:d.ps, size:sz)
}

// ═══════════════════════════════════════════
// MARK: - Palette
// ═══════════════════════════════════════════
struct P{let bg:Color;let paper:Color;let accent:Color;let accentSoft:Color;let ink:Color;let inkSoft:Color;let inkMut:Color
    static func g(_ k:String)->P{
        switch k{
        case "sakura":return P(bg:c(252,247,245),paper:.white,accent:c(230,141,166),accentSoft:c(251,228,237),ink:c(42,30,34),inkSoft:c(106,90,96),inkMut:c(181,168,172))
        case "ocean":return P(bg:c(245,249,250),paper:.white,accent:c(91,168,181),accentSoft:c(217,236,239),ink:c(21,33,40),inkSoft:c(84,103,109),inkMut:c(155,174,180))
        case "kraft":return P(bg:c(244,238,223),paper:c(251,246,233),accent:c(124,138,71),accentSoft:c(232,229,201),ink:c(44,36,24),inkSoft:c(110,96,71),inkMut:c(180,165,128))
        default:return P(bg:c(250,250,246),paper:.white,accent:c(123,181,118),accentSoft:c(226,239,223),ink:c(26,36,24),inkSoft:c(90,101,90),inkMut:c(160,172,159))
        }
    }
    private static func c(_ r:Int,_ g:Int,_ b:Int)->Color{Color(red:Double(r)/255,green:Double(g)/255,blue:Double(b)/255)}
}

// ═══════════════════════════════════════════
// MARK: - Images
// ═══════════════════════════════════════════
struct CloverImg:View{let size:CGFloat;var body:some View{
    if let u=Bundle.main.url(forResource:"clover",withExtension:"png"),let d=try? Data(contentsOf:u),let i=UIImage(data:d){
        Image(uiImage:i).resizable().aspectRatio(contentMode:.fit).frame(width:size,height:size)
    }else{Text("🍀").font(.system(size:size*0.7))}
}}
struct LeafImg:View{let size:CGFloat;let on:Bool;var body:some View{
    if let u=Bundle.main.url(forResource:"leaf",withExtension:"png"),let d=try? Data(contentsOf:u),let i=UIImage(data:d){
        Image(uiImage:i).resizable().aspectRatio(contentMode:.fit).frame(width:size,height:size)
            .saturation(on ? 1:0).opacity(on ? 1:0.35).brightness(on ? 0:0.15)
    }else{Circle().fill(on ? P.g("clover").accent:Color.gray.opacity(0.3)).frame(width:size,height:size)}
}}

// ═══════════════════════════════════════════
// MARK: - Timeline
// ═══════════════════════════════════════════
struct CTE:TimelineEntry{let date:Date;let data:CD}
struct CPr:TimelineProvider{
    func placeholder(in c:Context)->CTE{CTE(date:.now,data:.load())}
    func getSnapshot(in c:Context,completion:@escaping(CTE)->Void){completion(CTE(date:.now,data:.load()))}
    func getTimeline(in c:Context,completion:@escaping(Timeline<CTE>)->Void){
        completion(Timeline(entries:[CTE(date:.now,data:.load())],policy:.after(Calendar.current.date(byAdding:.minute,value:30,to:.now)!)))
    }
}

// ═══════════════════════════════════════════
// MARK: - 1. Quick Write (Small) — app homepage
// ═══════════════════════════════════════════
struct W1:View{
    let d:CD; var p:P{P.g(d.palette)}
    var body:some View{
        VStack(spacing:0){
            Spacer(minLength:2)
            ZStack{
                let sz:CGFloat=72,off:CGFloat=13
                Circle().fill(p.accent).frame(width:sz,height:sz).offset(x:-off,y:-off)
                Circle().fill(p.accent).frame(width:sz,height:sz).offset(x:off,y:-off)
                Circle().fill(p.accent).frame(width:sz,height:sz).offset(x:-off,y:off)
                Circle().fill(p.accent).frame(width:sz,height:sz).offset(x:off,y:off)
                VStack(spacing:2){
                    if let lucky=d.todayEntries.first?.lucky{
                        Text(d.lang=="zh" ?"今天的幸运":"today's luck")
                            .font(.system(size:8,weight:.medium)).foregroundStyle(.white.opacity(0.5)).tracking(1)
                        Text(lucky).font(af(d,11)).foregroundStyle(.white).lineLimit(3).multilineTextAlignment(.center).padding(.horizontal,8)
                    }else{
                        CloverImg(size:20)
                        Text(d.lang=="zh" ?"今天最幸运的小事\n是什么？":d.lang=="ja" ?"今日のラッキーは？":d.lang=="ko" ?"오늘의 행운은?":"What's your\nlucky moment?")
                            .font(af(d,11)).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center).lineSpacing(1)
                        Text(d.lang=="zh" ?"轻触记录":"tap to write").font(af(d,9)).foregroundStyle(.white.opacity(0.4))
                    }
                }
            }.shadow(color:p.accent.opacity(0.18),radius:10,y:4)
            // Stem
            RoundedRectangle(cornerRadius:1).fill(p.inkMut.opacity(0.4)).frame(width:2.5,height:14).padding(.top,-1)
            Spacer(minLength:2)
            // Stats
            Text(d.lang=="zh" ?"连续 \(d.streak) 天 · \(d.entries.count) 条记录":"\(d.streak) days · \(d.entries.count) entries")
                .font(af(d,11)).foregroundStyle(p.inkMut)
            Spacer(minLength:4)
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - 2. Leaf Progress (Small) — growing clover
// ═══════════════════════════════════════════
struct W2:View{
    let d:CD; var p:P{P.g(d.palette)}
    var body:some View{
        VStack(spacing:4){
            Spacer(minLength:2)
            // 4 heart-shaped leaves
            let sz:CGFloat=42,off:CGFloat=8
            ZStack{
                LeafImg(size:sz,on:d.leafCount>0).rotationEffect(.degrees(-45)).offset(x:-off,y:-off)
                LeafImg(size:sz,on:d.leafCount>1).rotationEffect(.degrees(45)).offset(x:off,y:-off)
                LeafImg(size:sz,on:d.leafCount>2).rotationEffect(.degrees(-135)).offset(x:-off,y:off)
                LeafImg(size:sz,on:d.leafCount>3).rotationEffect(.degrees(135)).offset(x:off,y:off)
            }
            Spacer(minLength:2)
            // Counter
            HStack(spacing:0){
                Text("\(d.leafCount)").font(af(d,28,bold:true)).foregroundStyle(p.ink)
                Text(" / 4").font(af(d,16)).foregroundStyle(p.inkMut)
            }
            // Progress text
            let remain=4-d.leafCount
            if d.leafCount>=4{
                Text(d.lang=="zh" ?"四叶草完成啦！🎉":"Clover complete! 🎉").font(af(d,12)).foregroundStyle(p.inkSoft)
            }else if d.leafCount==0{
                Text(d.lang=="zh" ?"开始收集叶片吧 🌿":"Start collecting! 🌿").font(af(d,12)).foregroundStyle(p.inkSoft)
            }else{
                Text(d.lang=="zh" ?"还差 \(remain) 片就满啦 🌿":"\(remain) more to go 🌿").font(af(d,12)).foregroundStyle(p.inkSoft)
            }
            Spacer(minLength:4)
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - 3. Diary (Medium) — calendar + entries
// ═══════════════════════════════════════════
struct W3:View{
    let d:CD; var p:P{P.g(d.palette)}
    var body:some View{
        HStack(spacing:0){
            // Left: calendar
            VStack(alignment:.leading,spacing:2){
                let cal=Calendar.current,now=Date()
                let y=cal.component(.year,from:now),m=cal.component(.month,from:now)
                // Month header
                Text(d.lang=="zh"||d.lang=="ja" ?"\(y)年\(m)月":d.lang=="ko" ?"\(y)년 \(m)월":"\(mn(m)) \(y)")
                    .font(af(d,13,bold:true)).foregroundStyle(p.ink)
                // Entry count this month
                let monthEntries=d.entries.filter{($0.date ?? "").hasPrefix(String(format:"%04d-%02d",y,m))}
                Text(d.lang=="zh" ?"本月 \(monthEntries.count) 篇":"\(monthEntries.count) entries")
                    .font(af(d,9)).foregroundStyle(p.inkMut).padding(.bottom,1)
                // Calendar grid
                MCal(days:Set(d.uniqueDays),p:p,lang:d.lang)
            }.frame(width:128).padding(.leading,2)

            // Right: entry cards
            VStack(spacing:6){
                let recent=recentGrouped()
                if recent.isEmpty{
                    Spacer()
                    Text("✨").font(.system(size:20))
                    Spacer()
                }else{
                    ForEach(Array(recent.prefix(2).enumerated()),id:\.offset){_,group in
                        VStack(alignment:.leading,spacing:4){
                            HStack{
                                let fd=fmtDate(group.date)
                                Text(fd).font(af(d,11)).foregroundStyle(p.inkSoft)
                                if group.entries.count>1{
                                    Text("\(group.entries.count)")
                                        .font(.system(size:9,weight:.bold)).foregroundStyle(.white)
                                        .frame(width:16,height:16).background(Circle().fill(p.accent))
                                }
                                Spacer()
                                Text("›").font(.system(size:13)).foregroundStyle(p.inkMut)
                            }
                            ForEach(Array(group.entries.prefix(2).enumerated()),id:\.offset){i,e in
                                if i>0{Rectangle().fill(p.inkMut.opacity(0.15)).frame(height:0.5).padding(.leading,2)}
                                Text(e.lucky ?? "").font(af(d,12)).foregroundStyle(p.ink).lineLimit(1)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius:12).fill(p.paper))
                        .overlay(RoundedRectangle(cornerRadius:12).stroke(p.inkMut.opacity(0.1),lineWidth:0.5))
                    }
                    Spacer(minLength:0)
                }
            }.padding(.leading,6).padding(.trailing,2)
        }.padding(.vertical,4)
    }

    func recentGrouped()->[(date:String,entries:[DiaryEntry])]{
        var map:[String:[DiaryEntry]]=[:]
        var order:[String]=[]
        for e in d.entries.sorted(by:{($0.date ?? "")>($1.date ?? "")}){
            let dt=e.date ?? ""; if !map.keys.contains(dt){order.append(dt)}
            map[dt,default:[]].append(e)
        }
        return order.map{(date:$0,entries:map[$0]!)}
    }
    func fmtDate(_ iso:String)->String{
        let parts=iso.split(separator:"-").compactMap{Int($0)}
        guard parts.count>=3 else{return iso}
        let m=parts[1],day=parts[2]
        if d.lang=="zh"||d.lang=="ja"{return "\(m)月\(day)日"}
        if d.lang=="ko"{return "\(m)월 \(day)일"}
        return "\(mn(m)) \(day)"
    }
    func mn(_ m:Int)->String{["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][m-1]}
}

struct MCal:View{
    let days:Set<String>;let p:P;let lang:String
    var body:some View{
        let cal=Calendar.current,now=Date()
        let y=cal.component(.year,from:now),m=cal.component(.month,from:now),td=cal.component(.day,from:now)
        let first=cal.date(from:DateComponents(year:y,month:m,day:1))!
        let wd=cal.component(.weekday,from:first)-1 // Sun=0
        let dim=cal.range(of:.day,in:.month,for:first)!.count
        let cells=Array(repeating:0,count:wd)+Array(1...dim)
        let rows=stride(from:0,to:cells.count,by:7).map{Array(cells[$0..<min($0+7,cells.count)])}
        let wh = lang=="zh"||lang=="ja" ? ["日","一","二","三","四","五","六"] :
                  lang=="ko" ? ["일","월","화","수","목","금","토"] : ["S","M","T","W","T","F","S"]
        VStack(spacing:1){
            HStack(spacing:0){ForEach(0..<7,id:\.self){i in
                Text(wh[i]).font(.system(size:7,weight:.medium)).foregroundStyle(p.inkMut).frame(maxWidth:.infinity)
            }}
            ForEach(Array(rows.enumerated()),id:\.offset){_,row in
                HStack(spacing:0){ForEach(0..<7,id:\.self){col in
                    let day=col<row.count ? row[col]:0
                    if day==0{Color.clear.frame(maxWidth:.infinity,minHeight:13)}
                    else{
                        let iso=String(format:"%04d-%02d-%02d",y,m,day)
                        let has=days.contains(iso),isT=day==td
                        VStack(spacing:1){
                            ZStack{
                                if isT{Circle().fill(p.accent).frame(width:16,height:16)}
                                Text("\(day)").font(.system(size:8,weight:isT ? .bold:has ? .semibold:.regular))
                                    .foregroundStyle(isT ? .white:has ? p.ink:p.inkMut)
                            }
                            if has && !isT{Circle().fill(p.accent).frame(width:3,height:3)}
                            else{Color.clear.frame(height:3)}
                        }.frame(maxWidth:.infinity,minHeight:15)
                    }
                }}
            }
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - 4. Clover Field (Large) — meadow
// ═══════════════════════════════════════════
struct W4:View{
    let d:CD; var p:P{P.g(d.palette)}
    var body:some View{
        let meadow=Color(red:0.88,green:0.94,blue:0.87)
        ZStack{
            // Meadow gradient
            LinearGradient(colors:[meadow.opacity(0.5),meadow],startPoint:.top,endPoint:.bottom)

            // Grass stems — scattered gray lines
            ForEach(0..<20,id:\.self){i in
                let x=CGFloat(((i*37+13)%100))/100
                let y=CGFloat(((i*53+29)%100))/100
                let h=CGFloat(((i*17+7)%12)+6)
                let r=Double(((i*23+11)%20)-10)
                Capsule().fill(Color.gray.opacity(0.18)).frame(width:1.5,height:h)
                    .rotationEffect(.degrees(r))
                    .position(x:UIScreen.main.bounds.width*0.4*x+20, y:220*y+40)
            }

            // Scattered clovers at pseudo-random positions
            let total=d.totalClovers
            if total>0{
                ForEach(0..<min(total,15),id:\.self){i in
                    let x=CGFloat(((i*67+23)%90)+5)/100
                    let y=CGFloat(((i*43+37)%70)+15)/100
                    let sz=CGFloat(((i*31+11)%16)+22)
                    VStack(spacing:0){
                        CloverImg(size:sz)
                        Capsule().fill(p.accent.opacity(0.3)).frame(width:1.5,height:sz*0.2)
                    }
                    .position(x:UIScreen.main.bounds.width*0.38*x+16, y:240*y+30)
                }
            }

            // Header text — top left
            VStack(alignment:.leading,spacing:1){
                Text(d.lang=="zh" ?"记录你的":d.lang=="ja" ?"あなたの":d.lang=="ko" ?"당신의":"Your")
                    .font(af(d,12)).foregroundStyle(p.ink.opacity(0.6))
                Text(d.lang=="zh" ?"幸运":d.lang=="ja" ?"ラッキー":d.lang=="ko" ?"행운":"Lucky")
                    .font(af(d,22,bold:true)).foregroundStyle(p.ink)
                Spacer()
            }
            .frame(maxWidth:.infinity,alignment:.leading)
            .padding(.leading,12).padding(.top,8)

            // Stats bottom right
            if total>0{
                VStack{
                    Spacer()
                    HStack{
                        Spacer()
                        HStack(spacing:3){
                            CloverImg(size:14)
                            Text("×\(total)").font(af(d,13,bold:true)).foregroundStyle(p.ink.opacity(0.6))
                        }
                        .padding(.horizontal,10).padding(.vertical,5)
                        .background(Capsule().fill(.white.opacity(0.6)))
                    }
                }.padding(8)
            }

            // Empty state
            if total==0 && d.leafCount==0{
                VStack(spacing:4){
                    CloverImg(size:36).opacity(0.4)
                    Text(d.lang=="zh" ?"集满四片叶片\n就能长出第一朵四叶草！":"Grow your first clover!")
                        .font(af(d,12)).foregroundStyle(p.ink.opacity(0.5)).multilineTextAlignment(.center)
                }.offset(y:20)
            }
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Widget definitions
// ═══════════════════════════════════════════
struct CloveryQuickWriteWidget:Widget{
    let kind="CloveryQuickWrite"
    var body:some WidgetConfiguration{
        StaticConfiguration(kind:kind,provider:CPr()){e in
            let bg=P.g(e.data.palette).bg
            if #available(iOS 17.0,*){W1(d:e.data).containerBackground(bg,for:.widget)}
            else{W1(d:e.data).background(bg)}
        }
        .configurationDisplayName("小幸运 · 记录").description("轻触开始记录今天的小幸运 🍀").supportedFamilies([.systemSmall])
    }
}
struct CloveryLeafWidget:Widget{
    let kind="CloveryLeaf"
    var body:some WidgetConfiguration{
        StaticConfiguration(kind:kind,provider:CPr()){e in
            let bg=P.g(e.data.palette).bg
            if #available(iOS 17.0,*){W2(d:e.data).containerBackground(bg,for:.widget)}
            else{W2(d:e.data).background(bg)}
        }
        .configurationDisplayName("小幸运 · 叶片").description("查看四叶草生长进度 🌱").supportedFamilies([.systemSmall])
    }
}
struct CloveryDiaryWidget:Widget{
    let kind="CloveryDiary"
    var body:some WidgetConfiguration{
        StaticConfiguration(kind:kind,provider:CPr()){e in
            let bg=P.g(e.data.palette).bg
            if #available(iOS 17.0,*){W3(d:e.data).containerBackground(bg,for:.widget)}
            else{W3(d:e.data).background(bg)}
        }
        .configurationDisplayName("小幸运 · 日记").description("日历和最近的幸运记录 📅").supportedFamilies([.systemMedium])
    }
}
struct CloveryFieldWidget:Widget{
    let kind="CloveryField"
    var body:some WidgetConfiguration{
        StaticConfiguration(kind:kind,provider:CPr()){e in
            if #available(iOS 17.0,*){W4(d:e.data).containerBackground(.clear,for:.widget)}
            else{W4(d:e.data)}
        }
        .configurationDisplayName("小幸运 · 四叶草田").description("你的四叶草花园 🏡").supportedFamilies([.systemLarge])
    }
}
