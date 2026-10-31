import AppKit
import Foundation
import ServiceManagement

enum Form: String { case links, lasche, bruecke }

/// Größe der Lasche. Normal ist die Größe bis v1.8, die anderen Stufen skalieren sie.
enum LaschenGroesse: String, CaseIterable {
    case klein, normal, gross
    var skala: CGFloat {
        switch self {
        case .klein: return 0.85
        case .normal: return 1
        case .gross: return 1.2
        }
    }
    var name: String {
        switch self {
        case .klein: return L("Klein", "Small")
        case .normal: return L("Normal", "Normal")
        case .gross: return L("Groß", "Large")
        }
    }
}

/// Die Flächen des Panels, in der Reihenfolge der Seitenleiste.
enum Reiter: String, CaseIterable { case uebersicht, claude, mac, platten, einstellungen }

enum Sprache: String, CaseIterable {
    case de, en
    var name: String { self == .de ? "Deutsch" : "English" }
    /// Startwert: Deutsch bei deutschem System, sonst Englisch.
    static let system: Sprache = (Locale.preferredLanguages.first ?? "de").lowercased().hasPrefix("de") ? .de : .en
}

/// Die gewählte Sprache. Sie wird im Hauptfaden gesetzt, die Messung liest sie nur für Namen.
var istEnglisch = Sprache.system == .en
var sprachOrt: Locale { Locale(identifier: istEnglisch ? "en_GB" : "de_DE") }
func L(_ de: String, _ en: String) -> String { istEnglisch ? en : de }

/// Jede Funktion, die fremde Dateien liest, hat ihre eigene Freigabe. Ohne sie läuft nur, was keine Datei braucht.
enum Freigabe: String, CaseIterable {
    case claude, bremse, codex, ordner
    var name: String {
        switch self {
        case .claude: return L("Claude-Limits und Fenster", "Claude limits and windows")
        case .bremse: return L("Speicher-Bremse", "Memory brake")
        case .codex: return L("Codex-Verbrauch", "Codex usage")
        case .ordner: return L("Ordnergrößen", "Folder sizes")
        }
    }
    var liest: String {
        switch self {
        case .claude: return L("Liest Limit-Stand und offene Fenster aus dem Ordner .claude. Gesprächsinhalte liest die App nie.", "Reads limit status and open windows from the .claude folder. The app never reads conversations.")
        case .bremse: return L("Die Speicher-Bremse ist ein eigenes Werkzeug, das neue Claude-Starts anhält, wenn der Mac überlastet ist. Die Freigabe erlaubt nur, ihre Zählung zu lesen, sie schaltet nichts ein.", "The memory brake is a separate tool that holds back new Claude starts when the Mac is overloaded. This permission only lets the app read its count, it switches nothing on.")
        case .codex: return L("Liest den letzten Verbrauchsstand aus dem Ordner .codex. Nur nötig, wenn du Codex von OpenAI nutzt.", "Reads the latest usage from the .codex folder. Only needed if you use Codex by OpenAI.")
        case .ordner: return L("Misst auf deinen Klick, welche Ordner einer Platte am größten sind. Gelöscht wird nichts.", "Measures on your click which folders on a drive are largest. Nothing is deleted.")
        }
    }
}

/// Wohin der eine nächste Schritt führt: ein Reiter im Panel oder ein Ort im Finder.
enum SchrittZiel: Equatable {
    case reiter(Reiter)
    case pfad(String)
}

/// Die zwei Seiten der Einstellungen: Vier Freigaben passen nicht zusätzlich auf eine Seite.
enum EinstellSeite: String { case allgemein, freigaben }

struct Bereich {
    var schluessel: String
    var symbol: String
    var name: String
    static var alle: [Bereich] { [
        Bereich(schluessel: "woche", symbol: "calendar", name: L("Woche", "Week")),
        Bereich(schluessel: "fuenf", symbol: "clock", name: L("5 Stunden", "5 hours")),
        Bereich(schluessel: "ram", symbol: "memorychip", name: "RAM"),
        Bereich(schluessel: "platte", symbol: "internaldrive", name: L("Platte", "Drive")),
        Bereich(schluessel: "akku", symbol: "battery.100", name: L("Akku", "Battery")),
    ] }
}

struct Meldung: Equatable {
    var titel: String
    var text: String
}

struct Erklaerung: Equatable {
    var schluessel: String
    var rechteck: NSRect
}

/// Hält alle angezeigten Werte. Gemessen wird im Hintergrund, angezeigt im Hauptfaden.
@MainActor
final class Modell: ObservableObject {
    @Published var speicher = Speicher()
    @Published var stufe = Stufe.gruen
    @Published var bremse = BremseZustand.aktiv
    @Published var beleger: [Beleger] = []
    @Published var akku: Akku?
    private var akkuMeldungen = 0
    @Published var faecher: [Fach] = []
    @Published var fenster = Fenster()
    @Published var fuenfStunden: Limit?
    @Published var woche: Limit?
    @Published var limitStand: Date?
    @Published var blockadenHeute = 0
    @Published var letzteBlockade: Date?
    @Published var blockadeBrowser = false
    @Published var blockadenZehnMinuten = 0
    @Published var logLesbar = true
    @Published var offen = false { didSet { if offen != oldValue { taktSetzen() } } }
    @Published var reiter = Reiter.uebersicht { didSet { if reiter == .claude { codexLesen() } } }
    @Published var codex: CodexLage?
    @Published var tippStand = 0
    @Published var meldung: Meldung?
    @Published var startFehler: String?
    @Published var erklaerung: Erklaerung?
    @Published var einstellSeite = EinstellSeite.allgemein
    @Published var freigabeFrage: Freigabe?
    /// Wer aus einem Bereich zu den Freigaben geführt wurde, kommt nach dem Ja dorthin zurück.
    private var rueckweg: Reiter?
    @Published var ordnerWurzel: String?
    @Published var ordnerLaeuft = false
    @Published var ordnerFehler: String?
    @Published var ordnerStand = 0

    @Published var mitteilung: Bool { didSet { ablage.set(mitteilung, forKey: "mitteilung") } }
    @Published var grenzeProzent: Int { didSet { ablage.set(grenzeProzent, forKey: "grenzeProzent") } }
    @Published var form: Form { didSet { ablage.set(form.rawValue, forKey: "form") } }
    @Published var laschenGroesse: LaschenGroesse { didSet { ablage.set(laschenGroesse.rawValue, forKey: "laschenGroesse") } }
    @Published var ausgeblendet: Set<String> { didSet { ablage.set(Array(ausgeblendet), forKey: "ausgeblendet") } }
    @Published var sprache: Sprache {
        didSet {
            ablage.set(sprache.rawValue, forKey: "sprache")
            istEnglisch = sprache == .en
            // Platten und Prozesse tragen übersetzte Namen, sie werden gleich neu gelesen.
            messen(alles: true)
        }
    }
    @Published var freigaben: Set<Freigabe> { didSet { ablage.set(freigaben.map(\.rawValue), forKey: "freigaben") } }
    @Published var einrichtungFertig: Bool { didSet { ablage.set(einrichtungFertig, forKey: "einrichtungFertig") } }
    @Published var autostart = SMAppService.mainApp.status == .enabled

    static let version = "v1.27"
    /// Fotos und Proben dürfen die eigenen Einstellungen nicht anfassen.
    private let ablage: UserDefaults = {
        if let suite = ProcessInfo.processInfo.environment["RAVARO_ABLAGE"] { return UserDefaults(suiteName: suite) ?? .standard }
        return CommandLine.arguments.contains("--foto") ? UserDefaults(suiteName: "de.ravaro.monitor.foto") ?? .standard : .standard
    }()
    private let leser = LogLeser()
    private let ordnerMesser = OrdnerMesser()
    private var ordnerAbgebrochen = false
    private(set) var schwellen = leseSchwellen(darf: false)
    private let warteschlange = DispatchQueue(label: "de.ravaro.monitor.messung", qos: .utility)
    private var takt: Timer?
    private var schlag = 0
    private var letzteMeldung: Date?

    init() {
        ablage.register(defaults: ["mitteilung": true, "grenzeProzent": 5, "form": Form.lasche.rawValue, "laschenGroesse": LaschenGroesse.normal.rawValue])
        mitteilung = ablage.bool(forKey: "mitteilung")
        grenzeProzent = ablage.integer(forKey: "grenzeProzent")
        ausgeblendet = Set(ablage.stringArray(forKey: "ausgeblendet") ?? [])
        form = Form(rawValue: ablage.string(forKey: "form") ?? "") ?? .lasche
        laschenGroesse = LaschenGroesse(rawValue: ablage.string(forKey: "laschenGroesse") ?? "") ?? .normal
        sprache = Sprache(rawValue: ablage.string(forKey: "sprache") ?? "") ?? .system
        // Das Selbstfoto zeigt alle Flächen gefüllt und schaltet die Fälle ohne Freigabe selbst.
        freigaben = imFoto ? Set(Freigabe.allCases) : Set((ablage.stringArray(forKey: "freigaben") ?? []).compactMap(Freigabe.init(rawValue:)))
        einrichtungFertig = imFoto || ablage.bool(forKey: "einrichtungFertig")
        istEnglisch = sprache == .en
        schwellen = leseSchwellen(darf: darf(.bremse))
    }

    func darf(_ f: Freigabe) -> Bool { freigaben.contains(f) }

    func zuDenFreigaben(_ f: Freigabe) {
        rueckweg = reiter
        reiter = .einstellungen
        einstellSeite = .freigaben
        freigabeFrage = f
    }

    func freigabeBestaetigen() {
        guard let f = freigabeFrage else { return }
        freigabeFrage = nil
        freigaben.insert(f)
        if f == .bremse { schwellen = leseSchwellen(darf: true) }
        if f == .codex { codexLesen() }
        if let r = rueckweg {
            rueckweg = nil
            reiter = r
            einstellSeite = .allgemein
        }
        messen(alles: true)
    }

    /// Zurücknehmen braucht keine Rückfrage. Was gelesen wurde, verschwindet sofort aus der Anzeige.
    func freigabeZuruecknehmen(_ f: Freigabe) {
        freigaben.remove(f)
        switch f {
        case .claude:
            fuenfStunden = nil
            woche = nil
            limitStand = nil
            fenster = Fenster()
            ablage.removeObject(forKey: "hauptOrdner")
        case .bremse:
            blockadenHeute = 0
            letzteBlockade = nil
            blockadenZehnMinuten = 0
            bremse = .ohneFreigabe
            schwellen = leseSchwellen(darf: false)
        case .ordner:
            ordnerAbbrechen()
            ablage.removeObject(forKey: "ordnerMessungen")
            ordnerStand += 1
        case .codex:
            codex = nil
        }
        messen(alles: true)
    }

    // MARK: Codex

    /// Gelesen wird beim Öffnen des Reiters, nicht im Takt: Die Datei ändert sich nur, wenn Codex läuft.
    func codexLesen() {
        guard darf(.codex) else { return }
        warteschlange.async { [weak self] in
            let lage = leseCodex()
            DispatchQueue.main.async {
                guard let self, self.darf(.codex) else { return }
                self.codex = lage
            }
        }
    }

    // MARK: Tipp

    /// Wird nach der Veröffentlichung auf das öffentliche Repo gesetzt. Solange es fehlt, bleibt der Tipp verborgen.
    private var tippLink: String? { ProcessInfo.processInfo.environment["RAVARO_TIPP_LINK"] ?? (imFoto ? "https://example.invalid" : nil) }

    /// Zählt jedes Limit-Fenster einmal, sobald es 90 % erreicht. Gilt auch bei ausgeschalteten Mitteilungen.
    private func engpassZaehlen() {
        var liste = (ablage.array(forKey: "engpaesse") as? [Double]) ?? []
        let jetzt = Date().timeIntervalSince1970
        let vorher = liste.count
        liste.removeAll { $0 < jetzt - 30 * 86400 }
        var geaendert = liste.count != vorher
        for limit in [fuenfStunden, woche].compactMap({ $0 }) where limit.prozent >= 90 && limit.neuAm > Date() {
            let ende = limit.neuAm.timeIntervalSince1970
            if liste.contains(where: { abs($0 - ende) < 600 }) { continue }
            liste.append(ende)
            geaendert = true
        }
        if geaendert {
            ablage.set(liste, forKey: "engpaesse")
            tippStand += 1
        }
    }

    var tippSichtbar: Bool {
        let _ = tippStand
        guard darf(.claude), tippLink != nil, Date().timeIntervalSince1970 >= ablage.double(forKey: "tippRuheBis") else { return false }
        return ((ablage.array(forKey: "engpaesse") as? [Double]) ?? []).count >= 3
    }

    /// Beide Wege enden gleich: Der Tipp ist gezeigt und ruht 30 Tage. Danach zählen nur neue Engpässe.
    func tippErledigt(oeffnen: Bool) {
        if oeffnen, let tippLink, let url = URL(string: tippLink) { NSWorkspace.shared.open(url) }
        ablage.set(Date().timeIntervalSince1970 + 30 * 86400, forKey: "tippRuheBis")
        ablage.set([Double](), forKey: "engpaesse")
        tippStand += 1
    }

    /// Nur für das Selbstfoto: Reste des letzten Laufs dürfen nicht als echte Daten erscheinen.
    func fotoAblageLeeren() {
        ["ordnerMessungen", "engpaesse", "tippRuheBis"].forEach(ablage.removeObject)
        ordnerStand += 1
        tippStand += 1
    }

    /// Nur für das Selbstfoto.
    func tippProbe() {
        ablage.removeObject(forKey: "tippRuheBis")
        ablage.set([1, 2, 3].map { Date().timeIntervalSince1970 + Double($0) * 7200 }, forKey: "engpaesse")
        tippStand += 1
    }

    // MARK: Prognose

    func prognoseText(_ schluessel: String) -> (text: String, warnung: Bool)? {
        let limit = schluessel == "woche" ? woche : fuenfStunden
        guard let limit, let p = prognose(limit, fensterStunden: schluessel == "woche" ? 168 : 5, stand: limitStand ?? Date()) else { return nil }
        switch p {
        case .zuFrueh: return (L("Noch zu früh für eine Prognose", "Too early to forecast"), false)
        case .reicht: return (L("Reicht bis zur Rückstellung", "Lasts until the reset"), false)
        case .leerAm(let d):
            guard d > Date() else { return (L("Reicht nicht, vermutlich schon leer", "Not enough, probably empty already"), true) }
            let f = DateFormatter()
            f.locale = sprachOrt
            let heute = Calendar.current.isDateInToday(d)
            f.dateFormat = heute ? "HH:mm" : "EEE, HH:mm"
            let wann = (heute ? L("heute ", "today ") : "") + f.string(from: d)
            return (L("Reicht nicht, leer gegen \(wann) Uhr", "Not enough, empty around \(wann)"), true)
        }
    }

    // MARK: Größte Ordner

    /// Die Platten, die gemessen werden können. Bei der Hauptplatte zählt der eigene Benutzerordner.
    var plattenWahl: [(name: String, wurzel: String)] {
        if let probe = ProcessInfo.processInfo.environment["RAVARO_ORDNER_WURZEL"] { return [("Probe", probe)] }
        var liste: [(name: String, wurzel: String)] = []
        for f in faecher {
            guard let platte = f.platte, let pfad = f.pfad else { continue }
            let hauptplatte = platte == "Hauptplatte"
            let wurzel = hauptplatte ? home : pfad
            if !liste.contains(where: { $0.wurzel == wurzel }) { liste.append((hauptplatte ? L("Hauptplatte", "Main drive") : platte, wurzel)) }
        }
        return liste
    }

    /// Ohne eigene Wahl zählt die vollste Platte, denn dort wird der Platz gebraucht.
    var ordnerZiel: String? {
        let wahl = plattenWahl
        if let w = wahl.first(where: { $0.wurzel == ordnerWurzel }) { return w.wurzel }
        let engste = engstesFach.map { $0.platte == "Hauptplatte" ? home : $0.pfad ?? "" }
        return wahl.first { $0.wurzel == engste }?.wurzel ?? wahl.first?.wurzel
    }

    private var heuteText: String { String(ISO8601DateFormatter().string(from: Date()).prefix(10)) }

    private var ordnerAblage: [String: OrdnerMessung] {
        guard let d = ablage.data(forKey: "ordnerMessungen") else { return [:] }
        return (try? JSONDecoder().decode([String: OrdnerMessung].self, from: d)) ?? [:]
    }

    /// Nur die Messung von heute zählt. Eine alte Liste würde Platz versprechen, der längst anders liegt.
    var ordnerHeute: OrdnerMessung? {
        guard let z = ordnerZiel, let m = ordnerAblage[z], m.tag == heuteText else { return nil }
        return m
    }

    func ordnerMessen() {
        guard darf(.ordner), !ordnerLaeuft, let wurzel = ordnerZiel else { return }
        guard FileManager.default.fileExists(atPath: wurzel) else {
            ordnerFehler = L("Die Platte ist gerade nicht angeschlossen. Schließe sie an und miss erneut.", "The drive is not connected. Connect it and measure again.")
            return
        }
        ordnerLaeuft = true
        ordnerFehler = nil
        ordnerAbgebrochen = false
        let arbeitsordner = fenster.ordner, messer = ordnerMesser
        // Sicherung gegen eine hängende Platte: Nach 15 Minuten gilt die Messung als gescheitert.
        let notbremse = DispatchWorkItem { messer.abbrechen() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 900, execute: notbremse)
        DispatchQueue.global(qos: .background).async { [weak self] in
            let ergebnis = messer.messen(wurzel: wurzel)
            notbremse.cancel()
            let liste = ergebnis.map { groessteOrdner($0.kilobyte, wurzel: wurzel, arbeitsordner: arbeitsordner) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.ordnerLaeuft = false
                if self.ordnerAbgebrochen { return }
                guard let ergebnis, let liste, !liste.isEmpty else {
                    self.ordnerFehler = L("Die Messung ging nicht. macOS gibt den Ordner nicht frei oder die Platte antwortet nicht. Erlaube den Zugriff in den Systemeinstellungen unter Datenschutz und miss erneut.", "The measurement failed. macOS is not sharing the folder or the drive is not responding. Allow access in System Settings under Privacy and measure again.")
                    return
                }
                var alle = self.ordnerAblage
                alle[wurzel] = OrdnerMessung(tag: self.heuteText, liste: liste, unvollstaendig: ergebnis.unvollstaendig)
                if let d = try? JSONEncoder().encode(alle) { self.ablage.set(d, forKey: "ordnerMessungen") }
                self.ordnerStand += 1
            }
        }
    }

    /// Nur für das Selbstfoto: eine Liste mit langen Namen, damit die Passung den schlimmsten Fall misst.
    func ordnerProbe(zehnLange: Bool) {
        guard let z = ordnerZiel else { return }
        var liste = (1...10).map { GrosserOrdner(pfad: z + "/Ein sehr langer Ordnername mit Zusatz \($0)", gb: 200 / Double($0), geschuetzt: $0 % 3 == 0) }
        if !zehnLange {
            let namen: [(String, Double, Bool)] = [("Downloads", 48.2, false), ("Filme/Exporte", 31.4, false), ("Library/Caches", 22.1, false), (".Trash", 12.6, false), (".claude/projects", 9.3, true), ("Library/Application Support", 8.7, true), ("Musik", 6.5, false), ("Bilder/Urlaub", 4.2, false)]
            liste = namen.map { GrosserOrdner(pfad: home + "/" + $0.0, gb: $0.1, geschuetzt: $0.2) }
        }
        let m = OrdnerMessung(tag: heuteText, liste: liste, unvollstaendig: zehnLange)
        if let d = try? JSONEncoder().encode([z: m]) { ablage.set(d, forKey: "ordnerMessungen") }
        ordnerStand += 1
    }

    func ordnerAbbrechen() {
        ordnerAbgebrochen = true
        ordnerMesser.abbrechen()
    }

    /// Führt nur hin. Gelöscht wird in dieser App nichts, das tut der Nutzer selbst im Finder.
    func ordnerZeigen(_ o: GrosserOrdner) {
        if ProcessInfo.processInfo.environment["RAVARO_ABLAGE"] != nil {
            print("finder: " + o.pfad)
            fflush(stdout)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: o.pfad)])
    }

    func starten() {
        messen(alles: true)
        taktSetzen()
    }

    /// Aufgeklappt zählt der Arbeitsspeicher von Sekunde zu Sekunde, zugeklappt bleibt die App sparsam.
    private func taktSetzen() {
        guard imFoto == false else { return }
        takt?.invalidate()
        takt = Timer.scheduledTimer(withTimeInterval: offen ? 2 : 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.schlagen() }
        }
        takt?.tolerance = offen ? 0.3 : 1
    }

    private func schlagen() {
        schlag += 1
        // Zu ist die App sparsam: Platten, Fenster und Beleger nur jeden sechsten Schlag.
        messen(alles: offen || schlag % 6 == 0)
    }

    func messen(alles: Bool) {
        let leser = self.leser, schwellen = self.schwellen
        let claude = darf(.claude), mitBremse = darf(.bremse), mitGroesse = offen || imFoto
        warteschlange.async { [weak self] in
            let s = messeSpeicher()
            let st = bestimmeStufe(s, schwellen)
            let akku = leseAkku()
            let br = mitBremse ? bremseZustand() : .ohneFreigabe
            let l: (fuenf: Limit?, woche: Limit?, stand: Date?) = claude ? leseLimits() : (nil, nil, nil)
            let neu = mitBremse ? leser.lies() : 0
            let heute = leser.heute, letzte = leser.letzte, browser = leser.browser, lesbar = leser.lesbar
            let jung = leser.juengste.count
            let f = alles ? (claude ? leseFenster(mitGroesse: mitGroesse) : Fenster()) : nil
            let b = alles || neu > 0 ? leseBeleger() : nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.speicher = s
                self.stufe = st
                self.akku = akku
                self.akkuPruefen()
                // Wurde eine Freigabe während der Messung zurückgenommen, zählt ihr Ergebnis nicht mehr.
                if claude == self.darf(.claude) {
                    self.fuenfStunden = l.fuenf
                    self.woche = l.woche
                    self.limitStand = l.stand
                    if let f {
                        self.fenster = f
                        self.faecher = claude ? leseFaecher(hauptOrdner: f.hauptOrdner ?? self.ablage.string(forKey: "hauptOrdner")) : lesePlatten()
                        if let h = f.hauptOrdner { self.ablage.set(h, forKey: "hauptOrdner") }
                    }
                }
                if mitBremse == self.darf(.bremse) {
                    self.bremse = br
                    self.blockadenHeute = mitBremse ? heute : 0
                    self.letzteBlockade = mitBremse ? letzte : nil
                    self.blockadeBrowser = browser
                    self.blockadenZehnMinuten = mitBremse ? jung : 0
                    self.logLesbar = lesbar
                }
                if let b { self.beleger = b }
                if neu > 0 { self.blockadeMelden(zehnMinuten: jung) }
                self.engpassZaehlen()
                self.limitPruefen()
                if f != nil { self.plattenPruefen() }
            }
        }
    }

    /// Warnt ab 10 % einmal je Entladung. Am Strom beginnt die Zählung neu.
    private func akkuPruefen() {
        guard let akku else { return }
        if akku.amStrom { ablage.removeObject(forKey: "akku-gewarnt"); return }
        guard mitteilung, meldung == nil, akku.prozent <= 10, !ablage.bool(forKey: "akku-gewarnt") else { return }
        ablage.set(true, forKey: "akku-gewarnt")
        akkuMeldungen += 1
        meldung = Meldung(titel: L("Akku fast leer", "Battery almost empty"), text: L("Noch \(akku.prozent) %. Schließ den Mac bald an den Strom an.", "\(akku.prozent) % left. Plug in your Mac soon."))
    }

    /// Warnt ab 90 % einmal je Limit-Fenster. Ein ausgeblendeter Bereich warnt nicht.
    private func limitPruefen() {
        guard mitteilung, meldung == nil else { return }
        let liste = [("fuenf", fuenfStunden, L("Das 5-Stunden-Limit", "The 5-hour limit")), ("woche", woche, L("Das Wochenlimit", "The weekly limit"))]
        for (schluessel, limit, name) in liste where !ausgeblendet.contains(schluessel) {
            guard let limit, limit.prozent >= 90, limit.neuAm > Date() else { continue }
            let merker = "limit-gewarnt-" + schluessel
            let bekannt = ablage.double(forKey: merker)
            // Die Rückstellzeit schwankt um Sekunden, ein neues Fenster liegt Stunden daneben.
            if abs(bekannt - limit.neuAm.timeIntervalSince1970) < 600 { continue }
            ablage.set(limit.neuAm.timeIntervalSince1970, forKey: merker)
            let rest = restzeit(bis: limit.neuAm)
            meldung = Meldung(titel: L("Claude-Limit fast erreicht", "Claude limit almost reached"), text: L("\(name) steht bei \(Int(limit.prozent)) %. Bei 100 % pausiert Claude. Rückstellung: \(rest).", "\(name) is at \(Int(limit.prozent)) %. At 100 % Claude pauses. Reset: \(rest)."))
            return
        }
    }

    /// Für Proben: was die laufende App gerade wirklich zeigt.
    func zustandAusgeben(rand: [String: Double] = [:]) {
        let d: [String: Any] = [
            "rand": rand, "akku": akku.map(akkuText) ?? "", "meldungen": akkuMeldungen, "belegerClaude": beleger.first { $0.name == "Claude Code" }?.gb ?? 0, "ruhigeGB": fenster.ruhigeGB,
            "reiter": reiter.rawValue, "seite": einstellSeite.rawValue, "sprache": sprache.rawValue, "woche": Bereich.alle[0].name, "kopf": kopfzeile.text,
            "faecher": faecher.map(\.name), "groesse": laschenGroesse.rawValue,
            "ring": RingWerte(modell: self).alle.map(\.titel), "bereiche": bereiche.map(\.schluessel), "lasche": RingWerte(modell: self).eintraege.map(\.schluessel),
            "freigaben": freigaben.map(\.rawValue).sorted(), "frage": freigabeFrage?.rawValue ?? "",
            "einrichtungFertig": einrichtungFertig, "fuenf": fuenfStunden?.prozent ?? -1, "woche_prozent": woche?.prozent ?? -1,
            "blockaden": blockadenHeute, "bremse": "\(bremse)", "ruhig": fenster.ruhig, "ram": speicher.ram > 0,
            "platten": faecher.compactMap(\.platte).count,
            "ordner": (ordnerHeute?.liste ?? []).map { ["pfad": $0.pfad, "gb": $0.gb, "geschuetzt": $0.geschuetzt] as [String: Any] },
            "prognoseWoche": prognoseText("woche")?.text ?? "", "prognoseFuenf": prognoseText("fuenf")?.text ?? "",
            "prognoseAm": woche.flatMap { l -> Double? in
                if case .leerAm(let d)? = prognose(l, fensterStunden: 168, stand: limitStand ?? Date()) { return d.timeIntervalSince1970 }
                return nil
            } ?? 0,
            "ruhige": fenster.ruhige.map { ["ordner": $0.ordner, "gb": $0.gb, "seit": $0.ruhigSeit.map(seitText) ?? "", "start": $0.start.map(startText) ?? "", "programm": $0.programm ?? "", "nummer": $0.nummer ?? 0] as [String: Any] },
            "schritt": naechsterSchritt?.knopf ?? "",
            "codex": codexText, "tipp": tippSichtbar, "engpaesse": ((ablage.array(forKey: "engpaesse") as? [Double]) ?? []).count,
            "ordnerLaeuft": ordnerLaeuft, "ordnerFehler": ordnerFehler ?? "",
        ]
        if let j = try? JSONSerialization.data(withJSONObject: d), let s = String(data: j, encoding: .utf8) {
            print("zustand: " + s)
            fflush(stdout)
        }
    }

    private var codexText: String {
        switch codex {
        case .wert(let w)?: return "wert:\(w.prozent):\(w.fensterMinuten):\(Int(w.neuAm.timeIntervalSince1970))"
        case .keinWert?: return "keinWert"
        case .keinCodex?: return "keinCodex"
        case nil: return ""
        }
    }

    func erklaeren(_ schluessel: String?, _ rechteck: NSRect) {
        guard let schluessel else {
            erklaerung = nil
            return
        }
        erklaerung = Erklaerung(schluessel: schluessel, rechteck: rechteck)
    }

    private func blockadeMelden(zehnMinuten n: Int) {
        guard mitteilung else { return }
        if let d = letzteMeldung, Date().timeIntervalSince(d) < 600 { return }
        letzteMeldung = Date()
        meldung = blockadeMeldung(n)
    }

    func blockadeMeldung(_ n: Int) -> Meldung {
        let browser = blockadeBrowser
        if istEnglisch {
            let wer = n == 1 ? "1 heavy start was" : "\(n) heavy starts were"
            let grund = browser ? "too many browsers are running" : "memory has reached its limit"
            return Meldung(titel: "Heavy starts held back", text: "\(wer) blocked because \(grund). Running work continues, Claude reports back in its window. Close windows and apps you do not need right now.")
        }
        let wer = n == 1 ? "1 schwerer Start wurde" : "\(n) schwere Starts wurden"
        let grund = browser ? "zu viele Browser laufen" : "der Arbeitsspeicher seine Grenze erreicht hat"
        let text = "\(wer) blockiert, weil \(grund). Laufende Arbeit geht weiter, Claude meldet sich im Fenster. Schließe Fenster und Programme, die du gerade nicht brauchst."
        return Meldung(titel: "Schwere Starts angehalten", text: text)
    }

    /// Der eine nächste Schritt bei roter Lage. Arbeitsspeicher geht vor der Platte, weil er Starts blockiert.
    var naechsterSchritt: (text: String, knopf: String, ziel: SchrittZiel, stufe: Stufe)? {
        if stufe == .rot || (blockiertGerade && stufe != .gruen) {
            let n = fenster.ruhig
            let danach = engstesFach.flatMap { plattenStufe($0) == .rot ? " " + L("Danach die Platte: ", "After that the drive: ") + plattenText($0) : nil } ?? ""
            if !fenster.ruhige.isEmpty {
                let gb = zahl(fenster.ruhigeGB)
                return (L(n == 1 ? "Arbeitsspeicher an der Grenze. 1 ruhiges Fenster belegt \(gb) GB. Schließen ist sicher, das Gespräch bleibt erhalten." : "Arbeitsspeicher an der Grenze. \(n) ruhige Fenster belegen \(gb) GB. Schließen ist sicher, das Gespräch bleibt erhalten.", n == 1 ? "Memory at its limit. 1 idle window uses \(gb) GB. Closing it is safe, the conversation is kept." : "Memory at its limit. \(n) idle windows use \(gb) GB. Closing them is safe, the conversation is kept.") + danach, L("Ruhige Fenster ansehen", "View idle windows"), .reiter(.claude), .rot)
            }
            let ruhige = L(n == 1 ? "1 ruhiges Claude-Fenster" : "\(n) ruhige Claude-Fenster", n == 1 ? "1 idle Claude window" : "\(n) idle Claude windows")
            return (L("Arbeitsspeicher an der Grenze. Schließen darfst du \(n > 0 ? ruhige + ", " : "")Browser-Fenster und Programme, die du nicht nutzt. Offen lassen: Fenster, die arbeiten oder auf dich warten. Was gerade läuft, zeigt die Aktivitätsanzeige des Mac.", "Memory at its limit. Safe to close: \(n > 0 ? ruhige + ", " : "")browser windows and apps you are not using. Keep open: windows that are working or waiting for you. Activity Monitor shows what is running.") + (darf(.claude) ? "" : " " + L("Welche Claude-Fenster ruhen, zeigt die App erst mit Freigabe.", "Which Claude windows are idle is shown once permitted.")) + danach, L("Aktivitätsanzeige öffnen", "Open Activity Monitor"), .pfad("/System/Applications/Utilities/Activity Monitor.app"), .rot)
        }
        func platte(_ f: Fach, _ s: Stufe) -> (text: String, knopf: String, ziel: SchrittZiel, stufe: Stufe) {
            (plattenText(f) + " " + L("Sieh nach, wo der Platz liegt. Löschen tust nur du.", "See where the space went. Only you delete things."), L("Größte Ordner ansehen", "View largest folders"), .reiter(.platten), s)
        }
        if let f = engstesFach, plattenStufe(f) == .rot { return platte(f, .rot) }
        // Ein Limit ab 90 % stoppt die Arbeit wie eine volle Platte, nur mit Ansage.
        let limits = [(fuenfStunden, "fuenf", L("Das 5-Stunden-Limit", "The 5-hour limit")), (woche, "woche", L("Das Wochenlimit", "The weekly limit"))]
        if let e = limits.compactMap({ l, k, name in l.map { ($0, k, name) } }).filter({ !ausgeblendet.contains($0.1) && $0.0.prozent >= 90 && $0.0.neuAm > Date() }).max(by: { $0.0.prozent < $1.0.prozent }) {
            let satz = prognoseText(e.1).map { $0.text + ". " } ?? ""
            return (L("\(e.2) steht bei \(Int(e.0.prozent)) %. \(satz)Bei 100 % pausiert Claude bis zur Rückstellung. Große Aufgaben verschiebst du besser.", "\(e.2) is at \(Int(e.0.prozent)) %. \(satz)At 100 % Claude pauses until the reset. Better to postpone big tasks."), L("Limits ansehen", "View limits"), .reiter(.claude), .rot)
        }
        // Gelb verdient denselben einen Schritt wie Rot. Sonst sagt die Übersicht „nichts zu tun“, während die Platte volläuft.
        if let f = engstesFach, plattenStufe(f) == .gelb { return platte(f, .gelb) }
        return nil
    }

    var blockadeGrund: String {
        blockadeBrowser ? L("zu viele Browser", "too many browsers") : L("Arbeitsspeicher-Grenze erreicht", "memory limit reached")
    }

    private func plattenText(_ f: Fach) -> String {
        let name = plattenName(f.platte ?? "")
        return L("\(name) hat nur noch \(prozent(f.freiProzent)) frei (\(zahl(f.frei)) GB).", "\(name) has only \(prozent(f.freiProzent)) free (\(zahl(f.frei)) GB).")
    }

    private func plattenPruefen() {
        guard mitteilung, meldung == nil else { return }
        let tag = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        for fach in faecher {
            guard let platte = fach.platte, fach.freiProzent < Double(grenzeProzent) else { continue }
            let schluessel = "gewarnt-" + platte
            if ablage.string(forKey: schluessel) == tag { continue }
            ablage.set(tag, forKey: schluessel)
            meldung = Meldung(titel: L("Platte wird knapp", "Drive running out"), text: plattenText(fach) + " " + L("Räume dort auf, sonst kann Arbeit scheitern. Das Panel sagt, was gefahrlos weg kann.", "Free up space, otherwise work can fail. The panel says what is safe to delete."))
            return
        }
    }

    /// Was dieser Rechner anbieten kann. Ohne Akku gibt es den Bereich Akku nirgends.
    var bereiche: [Bereich] { Bereich.alle.filter { $0.schluessel != "akku" || akku != nil } }

    /// Mindestens ein Bereich bleibt sichtbar, sonst wäre die Lasche leer.
    var letzterBereich: Bool { bereiche.filter { !ausgeblendet.contains($0.schluessel) }.count <= 1 }

    func bereichUmschalten(_ schluessel: String) {
        if ausgeblendet.contains(schluessel) {
            ausgeblendet.remove(schluessel)
        } else if !letzterBereich {
            ausgeblendet.insert(schluessel)
        }
    }

    func autostartUmschalten() {
        do {
            if autostart { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
            autostart = SMAppService.mainApp.status == .enabled
            startFehler = nil
        } catch {
            startFehler = L("Autostart ging nicht. Lege die App in den Ordner Programme und versuche es erneut.", "Start at login failed. Move the app to Applications and try again.")
        }
    }

    // MARK: Abgeleitete Anzeige

    /// Die vollste Platte, auf der Claude arbeitet. Sie bestimmt den Ring.
    var engstesFach: Fach? { faecher.filter { $0.platte != nil }.min { $0.freiProzent < $1.freiProzent } }

    func plattenStufe(_ fach: Fach) -> Stufe {
        if fach.freiProzent < Double(grenzeProzent) { return .rot }
        return fach.freiProzent < Double(grenzeProzent) * 3 ? .gelb : .gruen
    }

    /// Der Akku ist der eine Ring, auf dem voll gut ist.
    func akkuStufe(_ a: Akku) -> Stufe {
        if a.prozent <= 10 { return .rot }
        return a.prozent <= 20 ? .gelb : .gruen
    }

    /// Der Akku-Ring trägt keine Zahl, sondern dieses Symbol. Die Zahl steht in der Erklärung beim Drüberfahren.
    func ringSymbol(_ schluessel: String) -> String? {
        guard schluessel == "akku", let akku else { return nil }
        if akku.amStrom { return "powerplug.fill" }
        return akku.prozent <= 20 ? "battery.25" : "battery.100"
    }

    func limitFarbe(_ prozent: Double) -> Stufe {
        if prozent >= 90 { return .rot }
        return prozent >= 70 ? .gelb : .gruen
    }

    var blockiertGerade: Bool {
        guard let d = letzteBlockade else { return false }
        return Date().timeIntervalSince(d) < 600
    }

    var kopfzeile: (text: String, stufe: Stufe) {
        let platteRot = engstesFach.map { plattenStufe($0) == .rot } ?? false
        let platteGelb = engstesFach.map { plattenStufe($0) == .gelb } ?? false
        if stufe == .rot { return (L("ARBEITSSPEICHER AN DER GRENZE", "MEMORY AT ITS LIMIT") + (platteRot ? L(" · PLATTE FAST VOLL", " · DRIVE ALMOST FULL") : ""), .rot) }
        if platteRot { return (L("PLATTE FAST VOLL", "DRIVE ALMOST FULL"), .rot) }
        if stufe == .gelb { return (L("ARBEITSSPEICHER KNAPP", "MEMORY LOW") + (platteGelb ? L(" · PLATTE WIRD KNAPP", " · DRIVE GETTING FULL") : ""), .gelb) }
        if platteGelb { return (L("PLATTE WIRD KNAPP", "DRIVE GETTING FULL"), .gelb) }
        return (L("ALLES IM GRÜNEN", "ALL GOOD"), .gruen)
    }
}

/// Die Limits schreibt die Statuszeile von Claude Code. Ohne sie bleibt der Wert aus, deshalb nennt der Satz sie.
var keinLimitText: String { L("Noch kein Wert. Er kommt aus der Statuszeile von Claude Code, die Einrichtung steht im README.", "No value yet. It comes from the Claude Code status line, the README explains the setup.") }

func zahl(_ wert: Double) -> String {
    let f = NumberFormatter()
    f.locale = sprachOrt
    f.numberStyle = .decimal
    f.maximumFractionDigits = wert >= 100 ? 0 : 1
    f.minimumFractionDigits = wert >= 100 ? 0 : 1
    return f.string(from: NSNumber(value: wert)) ?? ""
}

/// Wie lange ein Fenster schon ruht. Das unterscheidet Fenster im selben Ordner.
func seitText(_ d: Date) -> String {
    let s = max(0, Int(Date().timeIntervalSince(d)))
    if s < 3600 { return L("seit \(s / 60) min", "for \(s / 60) min") }
    if s < 86400 { return L("seit \(s / 3600) h", "for \(s / 3600) h") }
    let tage = s / 86400
    return L(tage == 1 ? "seit 1 Tag" : "seit \(tage) Tagen", tage == 1 ? "for 1 day" : "for \(tage) days")
}

func akkuText(_ a: Akku) -> String {
    if a.laedt { return L("\(a.prozent) %, lädt", "\(a.prozent) %, charging") }
    return a.amStrom ? L("\(a.prozent) %, am Strom", "\(a.prozent) %, plugged in") : "\(a.prozent) %"
}

/// Wann ein Fenster gestartet wurde. Heute reicht die Uhrzeit.
func startText(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : L("dd.MM. HH:mm", "MM/dd HH:mm")
    return L("Start ", "Start ") + f.string(from: d)
}

func prozent(_ wert: Double) -> String { "\(Int(wert.rounded())) %" }

/// Eine Platte kann auch Speicher heißen. Das Wort Platte davor hält sie vom Arbeitsspeicher getrennt.
func plattenName(_ name: String) -> String {
    if name == "Hauptplatte" { return L(name, "Main drive") }
    return L("Platte \u{201E}\(name)\u{201C}", "Drive \u{201C}\(name)\u{201D}")
}

func restzeit(bis ziel: Date) -> String {
    let s = Int(ziel.timeIntervalSinceNow)
    if s <= 0 { return L("wird gerade neu gesetzt", "resetting now") }
    let f = DateFormatter()
    f.locale = sprachOrt
    f.dateFormat = s >= 86400 ? "EEE, HH:mm" : "HH:mm"
    let wann = f.string(from: ziel) + L(" Uhr", "")
    if s >= 86400 {
        let tage = (s + 43200) / 86400
        return L(tage == 1 ? "neu in 1 Tag" : "neu in \(tage) Tagen", tage == 1 ? "resets in 1 day" : "resets in \(tage) days") + " · " + wann
    }
    return L("neu in", "resets in") + " \(s / 3600) h \(s % 3600 / 60) min · " + wann
}
