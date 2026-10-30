import AppKit
import SwiftUI

/// Bildschirmaufnahmen sind hier nicht freigegeben. Deshalb fotografiert sich die App selbst.
@MainActor
struct Foto {
    var modell: Modell
    var ordner: String

    func starten() {
        modell.messen(alles: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            // Die Foto-Ablage bleibt zwischen Läufen liegen. Jeder Lauf beginnt mit allen Bereichen.
            modell.ausgeblendet = []
            modell.fotoAblageLeeren()
            let echteBlockade = modell.letzteBlockade
            modell.letzteBlockade = echteBlockade.map { min($0, Date(timeIntervalSinceNow: -3600)) }
            modell.blockadenZehnMinuten = 0
            sichern("lasche-ruhe", hintergrund(Lasche(modell: modell), rechts: true))
            let alteForm = modell.form
            modell.form = .links
            sichern("lasche-links", hintergrund(HStack { Lasche(modell: modell); Spacer().frame(width: 212) }, rechts: true))
            modell.form = alteForm
            sichern("bruecke-ruhe", hintergrund(Bruecke(modell: modell), rechts: false))
            for g in LaschenGroesse.allCases {
                let f = g.skala
                modell.laschenGroesse = g
                sichern("lasche-groesse-" + g.rawValue, hintergrund(LaschenPlatz(modell: modell), rechts: true, hoehe: 680))
                sichern("bruecke-groesse-" + g.rawValue, hintergrund(Bruecke(modell: modell).frame(width: 800, height: 84, alignment: .top).scaleEffect(f).frame(width: 800 * f, height: 84 * f), rechts: false, breite: 1000))
            }
            modell.laschenGroesse = .normal
            sichern("panel", hintergrund(Panel(modell: modell), rechts: nil))
            modell.reiter = .platten
            modell.ordnerProbe(zehnLange: false)
            sichern("panel-platten-ergebnis", hintergrund(Panel(modell: modell), rechts: nil))
            modell.fotoAblageLeeren()
            for r in Reiter.allCases where r != .uebersicht {
                modell.reiter = r
                sichern("panel-" + r.rawValue, hintergrund(Panel(modell: modell), rechts: nil))
            }
            modell.reiter = .einstellungen
            let andere: Sprache = modell.sprache == .de ? .en : .de
            let eigene = modell.sprache
            modell.sprache = andere
            sichern("sprache-wechsel-panel", hintergrund(Panel(modell: modell), rechts: nil))
            sichern("sprache-wechsel-lasche", hintergrund(Lasche(modell: modell), rechts: true))
            modell.sprache = eigene
            modell.reiter = .uebersicht
            modell.codexLesen()
            sichern("mitteilung", hintergrund(MeldungsAnsicht(meldung: modell.blockadeMeldung(3)), rechts: nil))
            modell.letzteBlockade = Date()
            modell.blockadenZehnMinuten = 3
            modell.blockadenHeute = max(1, modell.blockadenHeute)
            sichern("lasche-blockiert", hintergrund(Lasche(modell: modell), rechts: true))
            sichern("bruecke-blockiert", hintergrund(Bruecke(modell: modell), rechts: false))
            let alteAuswahl = modell.ausgeblendet
            modell.letzteBlockade = Date(timeIntervalSinceNow: -7200)
            modell.ausgeblendet = ["woche", "platte"]
            sichern("lasche-auswahl", hintergrund(Lasche(modell: modell), rechts: true))
            modell.ausgeblendet = alteAuswahl
            modell.speicher.frei = 5
            modell.stufe = .rot
            sichern("panel-rot", hintergrund(Panel(modell: modell), rechts: nil))
            for (i, stand) in [0.0, 0.45, 1.0].enumerated() {
                modell.reiter = .mac
                let flug = RingFlug(quelle: "ram", ziel: .mac)
                sichern("flug-\(i + 1)", hintergrund(Panel(modell: modell, flugProbe: (flug, stand)), rechts: nil))
            }
            modell.reiter = .uebersicht
            schlimmsterFall()
            passungMessen()
            sichern("erklaerung", hintergrund(ErklaerAnsicht(titel: L("Arbeitsspeicher (RAM)", "Memory (RAM)"), text: RingWerte(modell: modell).alle[2].hilfe), rechts: nil))
            exit(0)
        }
    }

    /// Lesart-Prüfung: alle vier im schlechtesten Zustand müssen gleich aussehen.
    private func schlimmsterFall() {
        modell.fuenfStunden = Limit(prozent: 98, neuAm: Date(timeIntervalSinceNow: 3600))
        modell.woche = Limit(prozent: 98, neuAm: Date(timeIntervalSinceNow: 86400))
        modell.speicher.frei = 2
        modell.stufe = .rot
        if var f = modell.faecher.first(where: { $0.platte != nil }) {
            f.frei = f.gesamt * 0.02
            modell.faecher = [f]
        }
        sichern("ringe-schlimmster-fall", hintergrund(Lasche(modell: modell), rechts: true))
    }

    /// Misst die natürliche Höhe jeder Fläche im schlimmsten Fall. Ein Foto könnte Überstand nicht zeigen, der Rahmen schneidet ihn ab.
    private func passungMessen() {
        modell.bremse = .fehlt
        modell.akku = Akku(prozent: 8, laedt: false, amStrom: false)
        modell.ausgeblendet = []
        sichern("lasche-akku", hintergrund(Lasche(modell: modell), rechts: true))
        sichern("bruecke-akku", hintergrund(Bruecke(modell: modell), rechts: false))
        modell.akku = Akku(prozent: 72, laedt: true, amStrom: true)
        modell.reiter = .uebersicht
        sichern("lasche-akku-strom", hintergrund(Lasche(modell: modell), rechts: true))
        sichern("panel-akku-strom", hintergrund(Panel(modell: modell), rechts: nil))
        modell.reiter = .einstellungen
        sichern("panel-akku-zeigen", hintergrund(Panel(modell: modell), rechts: nil))
        modell.akku = Akku(prozent: 8, laedt: false, amStrom: false)
        modell.limitStand = Date(timeIntervalSinceNow: -7200)
        modell.ausgeblendet = Set(Bereich.alle.dropFirst().map(\.schluessel))
        modell.startFehler = L("Autostart ging nicht. Lege die App in den Ordner Programme und versuche es erneut.", "Start at login failed. Move the app to Applications and try again.")
        modell.faecher = [
            Fach(name: L("Arbeitsordner", "Work folder"), platte: "Externer Speicher mit sehr langem Namen", pfad: "/Volumes/x", frei: 12, gesamt: 2000),
            Fach(name: L("Gesprächsverläufe", "Conversation history"), platte: "Hauptplatte", pfad: "/", frei: 12, gesamt: 500),
            Fach(name: L("Zwischenspeicher", "Temporary files")),
        ]
        var werte: [String: Double] = [:]
        modell.codex = .wert(CodexStand(prozent: 95, fensterMinuten: 10080, neuAm: Date(timeIntervalSinceNow: 86400 * 3), stand: Date(timeIntervalSinceNow: -7200)))
        modell.tippProbe()
        modell.fenster.ruhige = (1...9).map { RuhigesFenster(pid: $0, ordner: "Ein sehr langer Projektordner \($0)", gb: 2.5 / Double($0), ruhigSeit: Date(timeIntervalSinceNow: -86400 * 12), start: Date(timeIntervalSinceNow: -86400 * 12), programm: "VS Code", nummer: 15280 + $0) }
        let breite = panelGroesse.width - 178
        func hoehe<V: View>(_ v: V) -> Double {
            let r = ImageRenderer(content: v.frame(width: breite).fixedSize(horizontal: false, vertical: true))
            r.scale = 1
            return Double(r.cgImage?.height ?? 100_000)
        }
        let panel = Panel(modell: modell)
        for r in Reiter.allCases {
            modell.reiter = r
            werte[r.rawValue] = hoehe(panel.seite(r))
        }
        modell.reiter = .claude
        sichern("panel-schlimmster-fall-claude", hintergrund(panel, rechts: nil))
        werte["kopf"] = hoehe(panel.kopf)
        modell.reiter = .einstellungen
        modell.einstellSeite = .freigaben
        modell.freigabeFrage = .claude
        modell.freigaben = [.bremse]
        werte["einstellungen-freigaben"] = hoehe(panel.seite(.einstellungen))
        sichern("panel-freigaben", hintergrund(panel, rechts: nil))
        modell.freigabeFrage = nil
        modell.einstellSeite = .allgemein
        let werteVorher = (modell.fuenfStunden, modell.woche, modell.fenster, modell.faecher)
        Freigabe.allCases.forEach(modell.freigabeZuruecknehmen)
        modell.faecher = werteVorher.3
        for r in Reiter.allCases {
            modell.reiter = r
            werte[r.rawValue + "-ohne"] = hoehe(panel.seite(r))
            sichern("panel-ohne-freigabe-" + r.rawValue, hintergrund(panel, rechts: nil))
        }
        modell.einrichtungFertig = false
        modell.freigabeFrage = .codex
        let r = ImageRenderer(content: panel.einrichtung.frame(width: panelGroesse.width).fixedSize(horizontal: false, vertical: true))
        werte["einrichtung"] = Double(r.cgImage?.height ?? 100_000)
        sichern("panel-einrichtung", hintergrund(panel, rechts: nil))
        modell.freigabeFrage = nil
        modell.einrichtungFertig = true
        modell.freigaben = Set(Freigabe.allCases)
        modell.bremse = .fehlt
        (modell.fuenfStunden, modell.woche, modell.fenster) = (werteVorher.0, werteVorher.1, werteVorher.2)
        modell.reiter = .einstellungen
        sichern("panel-schlimmster-fall-einstellungen", hintergrund(panel, rechts: nil))
        modell.reiter = .platten
        func messeBreite<V: View>(_ v: V) -> Double {
            let r = ImageRenderer(content: v.fixedSize())
            r.scale = 1
            return Double(r.cgImage?.width ?? 100_000)
        }
        let alleAus = modell.ausgeblendet
        modell.ausgeblendet = []
        werte["breite-zeigen"] = messeBreite(panel.zeigenZeile)
        modell.ausgeblendet = alleAus
        let echtePlatten = modell.faecher
        modell.faecher = [
            Fach(name: "a", platte: "Externer Speicher mit sehr langem Namen", pfad: "/Volumes/a", frei: 12, gesamt: 2000),
            Fach(name: "b", platte: "Hauptplatte", pfad: "/", frei: 12, gesamt: 500),
            Fach(name: "c", platte: "Noch eine Platte mit langem Namen", pfad: "/Volumes/c", frei: 12, gesamt: 500),
        ]
        modell.ordnerWurzel = home
        modell.fotoAblageLeeren()
        werte["breite-ordnerkopf-vorher"] = messeBreite(panel.ordnerKopf)
        modell.ordnerProbe(zehnLange: true)
        werte["breite-ordnerkopf-nachher"] = messeBreite(panel.ordnerKopf)
        modell.ordnerWurzel = nil
        modell.faecher = echtePlatten
        werte["platten-ordner"] = hoehe(panel.seite(.platten))
        sichern("panel-schlimmster-fall-platten", hintergrund(panel, rechts: nil))
        modell.reiter = .uebersicht
        sichern("panel-schlimmster-fall", hintergrund(panel, rechts: nil))
        if let d = try? JSONSerialization.data(withJSONObject: werte) { try? d.write(to: URL(fileURLWithPath: ordner + "/passung.json")) }
    }

    private func hintergrund<V: View>(_ v: V, rechts: Bool?, breite: CGFloat = 840, hoehe: CGFloat = 600) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x123A56), Color(hex: 0x0B1320), Color(hex: 0x6A3A1E)], startPoint: .topTrailing, endPoint: .bottomLeading)
            switch rechts {
            case .some(true): HStack { Spacer(); v }
            case .some(false): VStack { v; Spacer() }
            default: v.padding(24)
            }
        }
        .fixedSize(horizontal: rechts == nil, vertical: rechts == nil)
        .frame(width: rechts == true ? 300 : (rechts == false ? breite : nil), height: rechts == true ? hoehe : (rechts == false ? 110 : nil))
        .environment(\.colorScheme, .dark)
    }

    private func sichern<V: View>(_ name: String, _ v: V) {
        let r = ImageRenderer(content: v)
        r.scale = 2
        guard let bild = r.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: bild)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ordner + "/" + name + ".png"))
    }
}

/// Für Proben: Punkte zwischen Bildschirmrand und Laschen-Körper, gemessen am gezeichneten Bild.
@MainActor
func randLuecke(_ modell: Modell) -> Int {
    let r = ImageRenderer(content: LaschenPlatz(modell: modell))
    r.scale = 1
    guard let bild = r.cgImage else { return -1 }
    let breite = bild.width
    var punkte = [UInt8](repeating: 0, count: breite * bild.height * 4)
    guard let ziel = CGContext(data: &punkte, width: breite, height: bild.height, bitsPerComponent: 8, bytesPerRow: breite * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
    ziel.draw(bild, in: CGRect(x: 0, y: 0, width: breite, height: bild.height))
    let zeile = bild.height / 2
    let vomRand = modell.form == .links ? Array(0..<breite) : Array((0..<breite).reversed())
    for (abstand, x) in vomRand.enumerated() where punkte[(zeile * breite + x) * 4 + 3] > 240 { return abstand }
    return -1
}
