import AppKit
import Darwin
import IOKit.ps
import Foundation

let GB = 1024.0 * 1024.0 * 1024.0
/// Proben richten die App auf einen nachgestellten Ordner. Die echten Dateien bleiben dann unberührt.
let home = ProcessInfo.processInfo.environment["RAVARO_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
let bremseDatei = home + "/.claude/hooks/speicher-bremse.py"
let bremseAusDatei = home + "/.claude/absturzschutz/bremse-aus"
let bremseLog = home + "/.claude/absturzschutz/speicher.log"

enum Stufe: Int { case gruen, gelb, rot }
enum BremseZustand { case aktiv, aus, fehlt, ohneFreigabe }

struct Speicher {
    var frei = 0
    var gepresst = 0.0
    var swap = 0.0
    var ram = 0.0
    var druck = 0
}

struct Schwelle {
    var freiMax: Int
    var gepresstFach: Double
    var swapFach: Double
}

struct Beleger: Identifiable {
    var id: String { name }
    var name: String
    var gb: Double
    var prozesse: Int
}

struct Fach: Identifiable {
    var id: String { name }
    var name: String
    var platte: String?
    var pfad: String?
    var frei = 0.0
    var gesamt = 0.0
    var freiProzent: Double { gesamt > 0 ? frei / gesamt * 100 : 0 }
}

struct Limit {
    var prozent: Double
    var neuAm: Date
}

struct RuhigesFenster: Identifiable {
    var id: Int { pid }
    var pid: Int
    var ordner: String
    var gb: Double
    var ruhigSeit: Date?
    var start: Date?
    var programm: String?
    /// Die Nummer, die VS Code am Terminal-Reiter nennt. Andere Programme zeigen keine.
    var nummer: Int?
}

struct Fenster {
    var arbeiten = 0
    var warten = 0
    var ruhig = 0
    var hauptOrdner: String?
    var ordner: [String] = []
    var ruhige: [RuhigesFenster] = []
    var ruhigeGB: Double { ruhige.reduce(0) { $0 + $1.gb } }
}

struct Akku: Equatable {
    var prozent: Int
    var laedt: Bool
    var amStrom: Bool
}

/// Der eingebaute Akku, wie ihn das System meldet. Rechner ohne Akku liefern nil, ebenso eine angeschlossene USV.
func leseAkku() -> Akku? {
    if let probe = ProcessInfo.processInfo.environment["RAVARO_AKKU"] {
        let t = probe.split(separator: ",")
        guard t.count == 2, let p = Int(t[0]) else { return nil }
        return Akku(prozent: p, laedt: t[1] == "laedt", amStrom: t[1] != "entlaedt")
    }
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let quellen = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
    for quelle in quellen {
        guard let d = IOPSGetPowerSourceDescription(info, quelle)?.takeUnretainedValue() as? [String: Any],
              d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              let jetzt = d[kIOPSCurrentCapacityKey] as? Int, let voll = d[kIOPSMaxCapacityKey] as? Int, voll > 0 else { continue }
        return Akku(prozent: jetzt * 100 / voll, laedt: d[kIOPSIsChargingKey] as? Bool ?? false, amStrom: d[kIOPSPowerSourceStateKey] as? String != kIOPSBatteryPowerValue)
    }
    return nil
}

func sysctlZahl(_ name: String) -> Int {
    var wert: Int32 = 0
    var groesse = MemoryLayout<Int32>.size
    return sysctlbyname(name, &wert, &groesse, nil, 0) == 0 ? Int(wert) : 0
}

/// Gleiche Quellen wie speicher-bremse.py, damit App und Bremse dieselbe Zahl sehen.
func messeSpeicher() -> Speicher {
    var s = Speicher()
    var ram: UInt64 = 0
    var groesse = MemoryLayout<UInt64>.size
    sysctlbyname("hw.memsize", &ram, &groesse, nil, 0)
    s.ram = Double(ram)
    s.frei = sysctlZahl("kern.memorystatus_level")
    s.druck = sysctlZahl("kern.memorystatus_vm_pressure_level")

    var swap = xsw_usage()
    var swapGroesse = MemoryLayout<xsw_usage>.size
    if sysctlbyname("vm.swapusage", &swap, &swapGroesse, nil, 0) == 0 { s.swap = Double(swap.xsu_used) }

    var info = vm_statistics64()
    var anzahl = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let ergebnis = withUnsafeMutablePointer(to: &info) { zeiger in
        zeiger.withMemoryRebound(to: integer_t.self, capacity: Int(anzahl)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &anzahl)
        }
    }
    if ergebnis == KERN_SUCCESS {
        s.gepresst = Double(info.total_uncompressed_pages_in_compressor) * Double(vm_kernel_page_size)
    }
    return s
}

/// Die Schwellen stehen nur in der Bremse. Die App liest sie dort, damit keine zweite Kopie entsteht.
func leseSchwellen(darf: Bool) -> (rot: Schwelle, gelb: Schwelle) {
    var rot = Schwelle(freiMax: 7, gepresstFach: 2.3, swapFach: 0.75)
    var gelb = Schwelle(freiMax: 15, gepresstFach: 2.0, swapFach: 0.6)
    guard darf, let text = try? String(contentsOfFile: bremseDatei, encoding: .utf8) else { return (rot, gelb) }
    func finde(_ name: String) -> Schwelle? {
        let muster = name + #" = \{"frei_max": (\d+), "gepresst_fach": ([\d.]+), "swap_fach": ([\d.]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: muster),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let a = Range(m.range(at: 1), in: text), let b = Range(m.range(at: 2), in: text),
              let c = Range(m.range(at: 3), in: text) else { return nil }
        return Schwelle(freiMax: Int(text[a]) ?? 7, gepresstFach: Double(text[b]) ?? 2.3, swapFach: Double(text[c]) ?? 0.75)
    }
    rot = finde("ROT") ?? rot
    gelb = finde("GELB") ?? gelb
    return (rot, gelb)
}

func bestimmeStufe(_ m: Speicher, _ schwellen: (rot: Schwelle, gelb: Schwelle)) -> Stufe {
    func ueber(_ g: Schwelle) -> Bool {
        m.frei <= g.freiMax || m.gepresst >= g.gepresstFach * m.ram || m.swap >= g.swapFach * m.ram
    }
    if m.druck >= 4 || ueber(schwellen.rot) { return .rot }
    return ueber(schwellen.gelb) ? .gelb : .gruen
}

func bremseZustand() -> BremseZustand {
    let fm = FileManager.default
    if !fm.fileExists(atPath: bremseDatei) { return .fehlt }
    return fm.fileExists(atPath: bremseAusDatei) ? .aus : .aktiv
}

func leseBeleger() -> [Beleger] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-axo", "pid=,ppid=,rss=,command="]
    let rohr = Pipe()
    p.standardOutput = rohr
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return [] }
    let daten = rohr.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard let text = String(data: daten, encoding: .utf8) else { return [] }

    var eintraege: [(pid: Int, kb: Double, name: String)] = []
    var eltern: [Int: Int] = [:]
    var namen: [Int: String] = [:]
    for zeile in text.split(separator: "\n") {
        let teile = zeile.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard teile.count == 4, let pid = Int(teile[0]), let vater = Int(teile[1]), let kb = Double(teile[2]) else { continue }
        let name = belegerName(String(teile[3]))
        eintraege.append((pid, kb, name))
        eltern[pid] = vater
        namen[pid] = name
    }
    // Was ein Claude-Fenster gestartet hat, zählt zu Claude Code. So rechnet auch die Liste der ruhigen Fenster.
    func gehoertZuClaude(_ pid: Int) -> Bool {
        var zeiger = eltern[pid]
        while let z = zeiger, z > 1 {
            if namen[z] == "Claude Code" { return true }
            zeiger = eltern[z]
        }
        return false
    }
    var summe: [String: (gb: Double, n: Int)] = [:]
    for e in eintraege {
        let name = gehoertZuClaude(e.pid) ? "Claude Code" : e.name
        let alt = summe[name] ?? (0, 0)
        summe[name] = (alt.gb + (fussabdruck(e.pid) ?? e.kb * 1024) / GB, alt.n + 1)
    }
    return summe.map { Beleger(name: $0.key, gb: $0.value.gb, prozesse: $0.value.n) }
        .sorted { $0.gb > $1.gb }
}

func belegerName(_ befehl: String) -> String {
    if befehl.contains("ms-playwright") { return L("Browser aus Messläufen", "Browsers from test runs") }
    if befehl.contains("com.apple.WebKit") { return "Safari" }
    if befehl.contains("/System/") && !befehl.contains(".app/Contents/MacOS/") { return L("macOS-Dienste", "macOS services") }
    let kopf = befehl.components(separatedBy: " -")[0].components(separatedBy: " /")[0]
    var name = (kopf as NSString).lastPathComponent.trimmingCharacters(in: .whitespaces)
    if name.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil || name == "claude" || name.hasPrefix("claude ") { return "Claude Code" }
    if name.hasPrefix("Claude") { return "Claude App" }
    if name.hasPrefix("Code Helper") || name == "Electron" && befehl.contains("Visual Studio Code") { return "Visual Studio Code" }
    if name.hasPrefix("Close.io") { return "Close" }
    if name.hasPrefix("com.apple.Virtualization") { return L("Virtuelle Maschine", "Virtual machine") }
    if name.hasPrefix("next-server") { return L("Entwicklungs-Server", "Dev server") }
    if name == "node" { return L("Node-Skripte", "Node scripts") }
    if name.hasPrefix("python") || name.hasPrefix("Python") { return L("Python-Skripte", "Python scripts") }
    if name.hasPrefix("com.apple.") { return L("macOS-Dienste", "macOS services") }
    if let r = name.range(of: #"\s*(Helper.*|\(.*\))$"#, options: .regularExpression) { name.removeSubrange(r) }
    return name.isEmpty ? L("Sonstiges", "Other") : name
}

func plattenWert(_ name: String, pfad: String?) -> Fach {
    var fach = Fach(name: name)
    guard let pfad, FileManager.default.fileExists(atPath: pfad) else { return fach }
    let werte = try? URL(fileURLWithPath: pfad).resourceValues(forKeys: [.volumeNameKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey])
    fach.platte = pfad.hasPrefix("/Volumes/") ? (werte?.volumeName ?? L("Platte", "Drive")) : "Hauptplatte"
    fach.pfad = pfad
    fach.frei = Double(werte?.volumeAvailableCapacity ?? 0) / GB
    fach.gesamt = Double(werte?.volumeTotalCapacity ?? 0) / GB
    return fach
}

struct GrosserOrdner: Codable, Identifiable {
    var id: String { pfad }
    var pfad: String
    var gb: Double
    var geschuetzt: Bool
    var name: String { (pfad as NSString).lastPathComponent }
}

/// Das Ergebnis einer Messung gilt am selben Tag, danach zählt es als veraltet.
struct OrdnerMessung: Codable {
    var tag: String
    var liste: [GrosserOrdner]
    var unvollstaendig: Bool
}

/// Zugriff, den die App beim Messen nicht anfassen soll, und Ordner, die nie gelöscht werden dürfen.
private let systemOrdner: Set<String> = [".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100", ".TemporaryItems"]

func istGeschuetzt(_ pfad: String, arbeitsordner: [String]) -> Bool {
    let unter = { (wurzel: String) in pfad == wurzel || pfad.hasPrefix(wurzel + "/") }
    if unter(home + "/.claude") || unter(home + "/.codex") { return true }
    if unter(home + "/Library") && !unter(home + "/Library/Caches") { return true }
    return arbeitsordner.contains { unter($0) || $0.hasPrefix(pfad + "/") }
}

/// Wählt aus der Baumliste die Ordner, in denen der Platz wirklich liegt. Hat ein Ordner ein Kind mit dem Großteil seiner Größe, zählt das Kind.
func groessteOrdner(_ kilobyte: [String: Double], wurzel: String, arbeitsordner: [String]) -> [GrosserOrdner] {
    var kinder: [String: [Double]] = [:]
    for (pfad, kb) in kilobyte where pfad != wurzel {
        kinder[(pfad as NSString).deletingLastPathComponent, default: []].append(kb)
    }
    let kandidaten = kilobyte.filter { pfad, kb in
        kb >= 1024 && pfad != wurzel && pfad != home + "/Library" && !pfad.components(separatedBy: "/").contains(where: systemOrdner.contains)
            && (kinder[pfad]?.max() ?? 0) < kb * 0.6
    }
    var gewaehlt: [String] = []
    for (pfad, _) in kandidaten.sorted(by: { $0.value > $1.value }) where gewaehlt.count < 10 {
        if gewaehlt.contains(where: { pfad.hasPrefix($0 + "/") || $0.hasPrefix(pfad + "/") }) { continue }
        gewaehlt.append(pfad)
    }
    return gewaehlt.map { GrosserOrdner(pfad: $0, gb: (kilobyte[$0] ?? 0) * 1024 / GB, geschuetzt: istGeschuetzt($0, arbeitsordner: arbeitsordner)) }
}

/// Liest nur Größen, nie Inhalte. Läuft mit niedrigster Priorität, die App bleibt dabei bedienbar.
final class OrdnerMesser {
    private var prozess: Process?

    func messen(wurzel: String) -> (kilobyte: [String: Double], unvollstaendig: Bool)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        p.arguments = ["-k", "-x", "-d", "3", wurzel]
        p.qualityOfService = .background
        let rohr = Pipe()
        p.standardOutput = rohr
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        prozess = p
        let daten = rohr.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        prozess = nil
        if p.terminationReason == .uncaughtSignal { return nil }
        var kb: [String: Double] = [:]
        for zeile in String(decoding: daten, as: UTF8.self).split(separator: "\n") {
            let teile = zeile.split(separator: "\t", maxSplits: 1)
            if teile.count == 2, let wert = Double(teile[0]) { kb[String(teile[1])] = wert }
        }
        return kb.isEmpty ? nil : (kb, p.terminationStatus != 0)
    }

    func abbrechen() { prozess?.terminate() }
}

func zwischenspeicherPfad() -> String {
    if let daten = FileManager.default.contents(atPath: home + "/.claude/settings.json"),
       let json = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
       let env = json["env"] as? [String: Any], let pfad = env["CLAUDE_CODE_TMPDIR"] as? String {
        return pfad
    }
    return NSTemporaryDirectory()
}

func leseFaecher(hauptOrdner: String?) -> [Fach] {
    [plattenWert(L("mit deinem Arbeitsordner", "with your work folder"), pfad: hauptOrdner),
     plattenWert(L("mit deinen Gesprächen", "with your conversations"), pfad: home + "/.claude"),
     plattenWert(L("mit den Zwischendateien", "with temporary files"), pfad: zwischenspeicherPfad())]
}

/// Ohne Claude-Freigabe: nur der Füllstand, nichts aus dem Ordner .claude.
func lesePlatten() -> [Fach] {
    var liste = [plattenWert(L("Hauptplatte", "Main drive"), pfad: "/")]
    let schluessel: [URLResourceKey] = [.volumeIsLocalKey, .volumeNameKey]
    for url in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: schluessel, options: [.skipHiddenVolumes]) ?? [] where url.path.hasPrefix("/Volumes/") {
        let werte = try? url.resourceValues(forKeys: Set(schluessel))
        guard werte?.volumeIsLocal == true else { continue }
        liste.append(plattenWert(plattenName(werte?.volumeName ?? url.lastPathComponent), pfad: url.path))
    }
    return liste
}

/// Der Fußabdruck zählt wie die Aktivitätsanzeige auch gepackten Speicher, RSS sieht davon nichts.
func fussabdruck(_ pid: Int) -> Double? {
    var info = rusage_info_v2()
    let ergebnis = withUnsafeMutablePointer(to: &info) { zeiger in
        zeiger.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(Int32(pid), RUSAGE_INFO_V2, $0) }
    }
    return ergebnis == 0 ? Double(info.ri_phys_footprint) : nil
}

/// Ein Fenster belegt seinen Prozess und alles, was es gestartet hat.
func speicherSamtKindern(_ pids: [Int]) -> [Int: Double] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-axo", "pid=,ppid=,rss="]
    let rohr = Pipe()
    p.standardOutput = rohr
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return [:] }
    let daten = rohr.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    var kb: [Int: Double] = [:]
    var kinder: [Int: [Int]] = [:]
    for zeile in String(decoding: daten, as: UTF8.self).split(separator: "\n") {
        let t = zeile.split(separator: " ", omittingEmptySubsequences: true)
        guard t.count == 3, let pid = Int(t[0]), let eltern = Int(t[1]), let wert = Double(t[2]) else { continue }
        kb[pid] = wert
        kinder[eltern, default: []].append(pid)
    }
    func summe(_ pid: Int) -> Double { (fussabdruck(pid) ?? (kb[pid] ?? 0) * 1024) + (kinder[pid] ?? []).reduce(0) { $0 + summe($1) } }
    return Dictionary(uniqueKeysWithValues: pids.map { ($0, summe($0) / GB) })
}

/// In welchem Programm ein Fenster läuft: die Kette der Elternprozesse bis zum sichtbaren Programm. Liest keine Datei.
func fensterHerkunft(_ pids: [Int]) -> [Int: (programm: String?, nummer: Int?)] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-axo", "pid=,ppid=,tty="]
    let rohr = Pipe()
    p.standardOutput = rohr
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return [:] }
    let daten = rohr.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    var eltern: [Int: Int] = [:]
    var tty: [Int: String] = [:]
    for zeile in String(decoding: daten, as: UTF8.self).split(separator: "\n") {
        let t = zeile.split(separator: " ", omittingEmptySubsequences: true)
        guard t.count == 3, let pid = Int(t[0]), let vater = Int(t[1]) else { continue }
        eltern[pid] = vater
        tty[pid] = String(t[2])
    }
    return Dictionary(uniqueKeysWithValues: pids.map { pid in
        var oben = pid
        while let vater = eltern[oben], tty[vater] == tty[pid], vater > 1, tty[pid]?.hasPrefix("?") == false { oben = vater }
        var zeiger = oben
        while let vater = eltern[zeiger], vater > 1 {
            if let app = NSRunningApplication(processIdentifier: pid_t(vater)), app.activationPolicy == .regular {
                let vsCode = app.bundleIdentifier == "com.microsoft.VSCode"
                return (pid, (vsCode ? "VS Code" : app.localizedName, vsCode && tty[pid]?.hasPrefix("?") == false ? oben : nil))
            }
            zeiger = vater
        }
        return (pid, (nil, nil))
    })
}

func leseFenster(mitGroesse: Bool) -> Fenster {
    var f = Fenster()
    var ruhig: [(pid: Int, cwd: String, seit: Date?, start: Date?)] = []
    var ordner: [String: Int] = [:]
    let verzeichnis = home + "/.claude/sessions"
    for name in (try? FileManager.default.contentsOfDirectory(atPath: verzeichnis)) ?? [] where name.hasSuffix(".json") {
        guard let daten = FileManager.default.contents(atPath: verzeichnis + "/" + name),
              let d = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              let pid = d["pid"] as? Int, kill(pid_t(pid), 0) == 0 || errno == EPERM else { continue }
        switch d["status"] as? String {
        case "busy", "active": f.arbeiten += 1
        case "waiting", "blocked": f.warten += 1
        case "idle":
            f.ruhig += 1
            ruhig.append((pid, d["cwd"] as? String ?? "", (d["statusUpdatedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }, (d["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }))
        default: continue
        }
        if let cwd = d["cwd"] as? String { ordner[cwd, default: 0] += 1 }
    }
    f.hauptOrdner = plattenWurzelHaeufigster(ordner)
    f.ordner = Array(ordner.keys)
    if mitGroesse && !ruhig.isEmpty {
        let groesse = speicherSamtKindern(ruhig.map(\.pid))
        let herkunft = fensterHerkunft(ruhig.map(\.pid))
        f.ruhige = ruhig.map { RuhigesFenster(pid: $0.pid, ordner: ($0.cwd as NSString).lastPathComponent, gb: groesse[$0.pid] ?? 0, ruhigSeit: $0.seit, start: $0.start, programm: herkunft[$0.pid]?.programm, nummer: herkunft[$0.pid]?.nummer) }.sorted { $0.gb > $1.gb }
    }
    return f
}

/// Der Arbeitsordner ist die Platte, auf der die meisten Fenster gerade laufen.
func plattenWurzelHaeufigster(_ ordner: [String: Int]) -> String? {
    var jePlatte: [String: Int] = [:]
    for (pfad, n) in ordner {
        let teile = pfad.split(separator: "/")
        let wurzel = pfad.hasPrefix("/Volumes/") && teile.count >= 2 ? "/" + teile[0...1].joined(separator: "/") : home
        jePlatte[wurzel, default: 0] += n
    }
    return jePlatte.max { $0.value < $1.value }?.key
}

func leseLimits() -> (fuenf: Limit?, woche: Limit?, stand: Date?) {
    let pfad = ProcessInfo.processInfo.environment["RAVARO_LIMITS"] ?? home + "/.claude/ctx-state/rate-limits.json"
    guard let daten = FileManager.default.contents(atPath: pfad),
          let json = try? JSONSerialization.jsonObject(with: daten) as? [String: Any] else { return (nil, nil, nil) }
    func limit(_ s: String) -> Limit? {
        guard let d = json[s] as? [String: Any], let p = d["used_percentage"] as? Double ?? (d["used_percentage"] as? Int).map(Double.init),
              let r = d["resets_at"] as? Double ?? (d["resets_at"] as? Int).map(Double.init) else { return nil }
        return Limit(prozent: p, neuAm: Date(timeIntervalSince1970: r))
    }
    let stand = (try? FileManager.default.attributesOfItem(atPath: pfad))?[.modificationDate] as? Date
    return (limit("five_hour"), limit("seven_day"), stand)
}

struct CodexStand: Equatable {
    var prozent: Double
    var fensterMinuten: Int
    var neuAm: Date
    var stand: Date
}

enum CodexLage: Equatable {
    case keinCodex, keinWert
    case wert(CodexStand)
}

private let codexFormat: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

/// Liest nur das Ende der letzten Sitzungsdateien und nimmt den letzten vollständigen Eintrag. Das Format ist nicht offiziell, deshalb gilt: lieber kein Wert als ein geratener.
func leseCodex() -> CodexLage {
    let fm = FileManager.default
    let wurzel = home + "/.codex/sessions"
    guard fm.fileExists(atPath: wurzel) else { return .keinCodex }
    func neueste(_ pfad: String) -> [String] { ((try? fm.contentsOfDirectory(atPath: pfad)) ?? []).filter { !$0.hasPrefix(".") }.sorted(by: >).map { pfad + "/" + $0 } }
    var dateien: [String] = []
    jahre: for jahr in neueste(wurzel) {
        for monat in neueste(jahr) {
            for tag in neueste(monat) {
                dateien += neueste(tag).filter { $0.hasSuffix(".jsonl") }
                if dateien.count >= 12 { break jahre }
            }
        }
    }
    for datei in dateien.prefix(12) {
        if let wert = codexEintrag(datei) { return .wert(wert) }
    }
    return .keinWert
}

private func codexEintrag(_ datei: String) -> CodexStand? {
    guard let griff = FileHandle(forReadingAtPath: datei) else { return nil }
    defer { try? griff.close() }
    let ende = griff.seekToEndOfFile()
    griff.seek(toFileOffset: ende > 524_288 ? ende - 524_288 : 0)
    let daten = griff.readDataToEndOfFile()
    for zeile in daten.split(separator: 0x0A).reversed() {
        guard zeile.count < 200_000, String(decoding: zeile.prefix(4000), as: UTF8.self).contains("rate_limits") || String(decoding: zeile, as: UTF8.self).contains("\"rate_limits\""),
              let json = try? JSONSerialization.jsonObject(with: Data(zeile)) as? [String: Any],
              let nutzlast = json["payload"] as? [String: Any], let grenzen = nutzlast["rate_limits"] as? [String: Any],
              let p = grenzen["primary"] as? [String: Any],
              let prozent = p["used_percent"] as? Double ?? (p["used_percent"] as? Int).map(Double.init),
              let minuten = p["window_minutes"] as? Int,
              let neu = p["resets_at"] as? Double ?? (p["resets_at"] as? Int).map(Double.init) else { continue }
        let datum = (json["timestamp"] as? String).flatMap(codexFormat.date(from:))
        let aenderung = (try? FileManager.default.attributesOfItem(atPath: datei))?[.modificationDate] as? Date
        guard let stand = datum ?? aenderung else { continue }
        return CodexStand(prozent: prozent, fensterMinuten: minuten, neuAm: Date(timeIntervalSince1970: neu), stand: stand)
    }
    return nil
}

enum Prognose: Equatable {
    case zuFrueh, reicht
    case leerAm(Date)
}

/// Rechnet mit dem Schnitt des laufenden Fensters. Eine Verlaufsdatei gibt es nicht. Vor 5 % vergangener Zeit sagt der Schnitt noch nichts.
func prognose(_ l: Limit, fensterStunden: Double, stand: Date) -> Prognose? {
    let laenge = fensterStunden * 3600
    guard l.neuAm > stand else { return nil }
    let start = l.neuAm.addingTimeInterval(-laenge)
    let vergangen = stand.timeIntervalSince(start)
    guard vergangen / laenge >= 0.05 else { return .zuFrueh }
    guard l.prozent > 0 else { return .reicht }
    let bisLeer = vergangen * 100 / l.prozent
    return bisLeer >= laenge ? .reicht : .leerAm(start.addingTimeInterval(bisLeer))
}

/// Liest das Log der Bremse ab der letzten Stelle. Beim ersten Lauf wird nur gezählt, nicht gemeldet.
final class LogLeser {
    private var stelle: UInt64 = 0
    private var ersterLauf = true
    private var jeTag: [String: Int] = [:]
    private(set) var letzte: Date?
    private(set) var browser = false
    private(set) var lesbar = true
    private(set) var juengste: [Date] = []
    private let format: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var heute: Int { jeTag[String(format.string(from: Date()).prefix(10))] ?? 0 }

    /// Gibt zurück, wie viele neue Ablehnungen seit dem letzten Aufruf dazukamen.
    func lies() -> Int {
        guard FileManager.default.fileExists(atPath: bremseLog) else {
            lesbar = bremseZustand() == .fehlt
            return 0
        }
        guard let griff = FileHandle(forReadingAtPath: bremseLog) else {
            lesbar = false
            return 0
        }
        defer { try? griff.close() }
        lesbar = true
        let ende = griff.seekToEndOfFile()
        if ende < stelle {  // die Bremse hat ihr Log gekürzt
            stelle = 0
            jeTag = [:]
            ersterLauf = true
        }
        if ende == stelle {
            ersterLauf = false
            return 0
        }
        griff.seek(toFileOffset: stelle)
        let daten = griff.readDataToEndOfFile()
        guard let umbruch = daten.lastIndex(of: 0x0A) else { return 0 }
        let vollstaendig = daten[daten.startIndex...umbruch]
        stelle += UInt64(vollstaendig.count)
        var neu = 0
        for zeile in String(decoding: vollstaendig, as: UTF8.self).split(separator: "\n") where zeile.contains("-> abgelehnt") {
            let datum = format.date(from: String(zeile.prefix(19)))
            jeTag[String(zeile.prefix(10)), default: 0] += 1
            letzte = datum ?? letzte
            browser = zeile.contains("(Browser)")
            if let datum { juengste.append(datum) }
            neu += 1
        }
        juengste.removeAll { Date().timeIntervalSince($0) > 600 }
        let warErster = ersterLauf
        ersterLauf = false
        return warErster ? 0 : neu
    }
}
