import AppKit
import SwiftUI

let panelGroesse = NSSize(width: 760, height: 600)

/// Ein Ring des Panels. Die Lasche behält ihren eigenen, der Strich liegt hier innerhalb des Durchmessers.
struct PanelRing: View {
    var anteil: Double
    var farbton: Color
    var text = ""
    var claude = false
    var durchmesser: CGFloat
    var strich: CGFloat
    var inhalt: Double = 1
    var mitte: String?

    var body: some View {
        ZStack {
            Circle().inset(by: strich / 2).stroke(Color.spur, lineWidth: strich)
            Circle().inset(by: strich / 2).trim(from: 0, to: max(0.012, min(1, anteil / 100)))
                .stroke(farbton, style: StrokeStyle(lineWidth: strich, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if claude { LimitSymbol().fill(Color.text).frame(width: durchmesser * 0.56, height: durchmesser * 0.56).opacity(inhalt) }
            if let mitte { Image(systemName: mitte).font(.system(size: durchmesser * 0.3)).foregroundColor(.text).opacity(inhalt) } else if !text.isEmpty && !claude { Text(text).font(.kopf(22)).monospacedDigit().foregroundColor(.text).opacity(inhalt) }
        }
        .frame(width: durchmesser, height: durchmesser)
    }
}

struct Balken: View {
    var prozent: Double
    var farbton: Color
    var sichtbar: Bool
    @Environment(\.accessibilityReduceMotion) private var ruhig

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.spur)
                Capsule().fill(farbton).frame(width: sichtbar ? max(4, g.size.width * min(1, prozent / 100)) : 0)
            }
        }
        .frame(height: 6)
        .animation(ruhig ? nil : .easeOut(duration: 0.45), value: sichtbar)
    }
}

struct Karte<Inhalt: View>: View {
    var titel: String?
    var fuellen = false
    @ViewBuilder var inhalt: Inhalt

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let titel { Text(titel).font(.mikro(12)).tracking(0.6).foregroundColor(.grau).lineLimit(1) }
            inhalt
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: fuellen ? .infinity : nil, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.karte))
    }
}

/// Name links, Wert rechts, darunter der Balken.
struct BalkenZeile: View {
    var name: String
    var wert: String
    var prozent: Double
    var farbton: Color
    var textFarbton: Color
    var sichtbar: Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(name).font(.lauf(13)).foregroundColor(.text).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text(wert).font(.kopf(16)).monospacedDigit().foregroundColor(textFarbton).layoutPriority(1)
            }
            Balken(prozent: prozent, farbton: farbton, sichtbar: sichtbar)
        }
    }
}

struct ZweiSeiten: View {
    var links: String
    var rechts: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(links).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Text(rechts).monospacedDigit().lineLimit(1).layoutPriority(1)
        }
        .font(.lauf(13)).foregroundColor(.grau)
    }
}

/// Merkt sich, wo ein Ring steht, damit der angeklickte zu seinem Reiter wandern kann.
private struct RingOrte: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

struct RingFlug {
    var quelle: String
    var ziel: Reiter
}

struct Panel: View {
    @ObservedObject var modell: Modell
    var sichtbar = true
    /// Für das Selbstfoto: ein fester Moment der Bewegung statt der Animation.
    var flugProbe: (flug: RingFlug, stand: Double)?
    @State private var flug: RingFlug?
    @State private var flugStand = 0.0
    @Environment(\.accessibilityReduceMotion) private var ruhig
    @Namespace private var auswahl

    private var flugJetzt: RingFlug? { flugProbe?.flug ?? flug }
    private var standJetzt: Double { flugProbe?.stand ?? flugStand }

    var body: some View {
        Group {
            if modell.einrichtungFertig {
                HStack(spacing: 0) {
                    seitenleiste
                    VStack(spacing: 0) {
                        kopf
                        ZStack(alignment: .top) {
                            // Die Übersicht bleibt während des Flugs stehen, sonst verlöre der Ring seinen Startpunkt.
                            if flugJetzt != nil { seite(.uebersicht).opacity(max(0, 1 - standJetzt * 2.5)).allowsHitTesting(false) }
                            seite(modell.reiter).opacity(flugJetzt != nil ? max(0, (standJetzt - 0.4) / 0.6) : 1)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                einrichtung
            }
        }
        .frame(width: panelGroesse.width, height: panelGroesse.height)
        .background(Color.flaeche)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.linie, lineWidth: 1))
        .overlayPreferenceValue(RingOrte.self) { orte in fliegenderRing(orte) }
    }

    // MARK: Seitenleiste

    private var seitenleiste: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                RLogo(breite: 28)
                Text("RAVARO\nMONITOR").font(.kopf(13)).foregroundColor(.text).lineSpacing(0)
            }
            .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 12)
            eintrag(.uebersicht, L("Übersicht", "Overview"), L("Was jetzt zählt", "What matters now")) { symbol("scope") }
            eintrag(.claude, "Claude", claudeKurz.text) { kleinerRing(.claude, claudeKurz.anteil, claudeKurz.farbton) }
            eintrag(.mac, "Mac", macKurz.text) { kleinerRing(.mac, macKurz.anteil, macKurz.farbton) }
            eintrag(.platten, L("Platten", "Drives"), plattenKurz.text) { kleinerRing(.platten, plattenKurz.anteil, plattenKurz.farbton) }
            Spacer(minLength: 0)
            eintrag(.einstellungen, L("Einstellungen", "Settings"), nil) { symbol("gearshape") }
        }
        .padding(.horizontal, 8).padding(.vertical, 12)
        .frame(width: 178)
        .frame(maxHeight: .infinity)
        .background(Color.leiste)
        .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1) }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 16)).foregroundColor(.text).frame(width: 30, height: 30)
    }

    private func kleinerRing(_ r: Reiter, _ anteil: Double, _ farbton: Color) -> some View {
        PanelRing(anteil: anteil, farbton: farbton, durchmesser: 30, strich: 4)
            .opacity(flugJetzt?.ziel == r ? 0 : 1)
            .anchorPreference(key: RingOrte.self, value: .bounds) { ["reiter-" + r.rawValue: $0] }
    }

    private func eintrag<Marke: View>(_ r: Reiter, _ name: String, _ unter: String?, @ViewBuilder marke: () -> Marke) -> some View {
        let an = modell.reiter == r
        return Button { modell.reiter = r } label: {
            HStack(spacing: 10) {
                marke()
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(.lauf(13).weight(.medium)).foregroundColor(.text).lineLimit(1)
                    if let unter { Text(unter).font(.lauf(12)).foregroundColor(.grau).lineLimit(1).truncationMode(.tail) }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 8).fill(an ? Color.spur : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(DruckStil(radius: 8)).focusable()
        .accessibilityLabel(name).accessibilityValue(unter ?? "").accessibilityAddTraits(an ? .isSelected : [])
    }

    /// Die Seitenleiste nennt den Wert, der gerade am meisten zählt. Ausgeblendetes zählt nicht mit.
    private var claudeKurz: (text: String, anteil: Double, farbton: Color) {
        var wahl: (Limit, String)?
        if let w = modell.woche { wahl = (w, L("Woche", "week")) }
        if let f = modell.fuenfStunden, !modell.ausgeblendet.contains("fuenf"), f.prozent > (wahl?.0.prozent ?? -1) { wahl = (f, L("5 Stunden", "5 hours")) }
        guard modell.darf(.claude) else { return (L("ohne Freigabe", "no permission"), 0, .grau) }
        guard let wahl else { return (L("noch kein Wert", "no value yet"), 0, .grau) }
        return ("\(Int(wahl.0.prozent)) % \(wahl.1)", wahl.0.prozent, farbe(modell.limitFarbe(wahl.0.prozent)))
    }

    private var macKurz: (text: String, anteil: Double, farbton: Color) {
        let s = modell.speicher
        guard s.ram > 0 else { return (L("wird gemessen", "measuring"), 0, .grau) }
        return ("\(100 - s.frei) % RAM", Double(100 - s.frei), farbe(modell.stufe))
    }

    private var plattenKurz: (text: String, anteil: Double, farbton: Color) {
        guard let f = modell.engstesFach else { return (L("wird gemessen", "measuring"), 0, .grau) }
        let belegt = 100 - Int(f.freiProzent.rounded())
        return (L("\(belegt) % voll", "\(belegt) % full"), Double(belegt), farbe(modell.plattenStufe(f)))
    }

    // MARK: Kopf

    private func titel(_ r: Reiter) -> String {
        switch r {
        case .uebersicht: return L("Übersicht", "Overview")
        case .claude: return "Claude"
        case .mac: return "Mac"
        case .platten: return L("Platten", "Drives")
        case .einstellungen: return L("Einstellungen", "Settings")
        }
    }

    var kopf: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titel(modell.reiter)).font(.kopf(16)).foregroundColor(.text)
                Text("/// " + modell.kopfzeile.text).font(.mikro(12)).tracking(0.6).foregroundColor(textFarbe(modell.kopfzeile.stufe)).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 4)
            let b = bremseAnzeige
            Text(b.text).font(.mikro(12)).tracking(0.6).foregroundColor(b.farbton).fixedSize().padding(.top, 20)
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 12)
    }

    private var bremseAnzeige: (text: String, farbton: Color) {
        switch modell.bremse {
        case .aktiv: return (L("BREMSE AKTIV", "BRAKE ON"), .gruen)
        case .aus: return (L("BREMSE AUS", "BRAKE OFF"), .rotText)
        case .fehlt: return (L("OHNE BREMSE", "NO BRAKE"), .grau)
        case .ohneFreigabe: return ("", .grau)
        }
    }

    // MARK: Flächen

    @ViewBuilder func seite(_ r: Reiter) -> some View {
        Group {
            switch r {
            case .uebersicht: uebersicht
            case .claude: claude
            case .mac: mac
            case .platten: platten
            case .einstellungen: einstellungen
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 16)
    }

    private var uebersicht: some View {
        VStack(spacing: 12) {
            schritt
            Spacer(minLength: 0)
            ringe
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 12) {
                Karte(titel: "CLAUDE", fuellen: true) { claudeLage }
                Karte(titel: L("BREMSE", "BRAKE"), fuellen: true) { bremseLage }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var schritt: some View {
        if let s = modell.naechsterSchritt {
            HStack(spacing: 14) {
                Text(s.text).font(.lauf(13)).foregroundColor(.text).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(s.knopf) {
                    switch s.ziel {
                    case .reiter(let r): modell.reiter = r
                    case .pfad(let p): NSWorkspace.shared.open(URL(fileURLWithPath: p))
                    }
                }
                    .buttonStyle(DruckStil(radius: 8)).focusable().font(.lauf(13).weight(.semibold)).foregroundColor(.tinte)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange2)).fixedSize()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill((s.stufe == .rot ? Color.rotFlaeche : Color.gelb).opacity(0.09)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(s.stufe == .rot ? Color.rot : Color.gelb, lineWidth: 1))
        } else {
            Karte(titel: nil) {
                Text(L("Gerade ist nichts zu tun.", "Nothing to do right now.")).font(.kopf(16)).foregroundColor(.text)
                Text(L("Sobald etwas wichtig wird, steht es hier, mit dem einen nächsten Schritt.", "When something matters, it appears here with the one next step.")).font(.lauf(13)).foregroundColor(.grau)
            }
        }
    }

    private var ringe: some View {
        let werte = RingWerte(modell: modell).alle
        // Fünf Ringe in voller Größe wären breiter als die Fläche.
        let eng = werte.count > 4
        return HStack(spacing: 10) {
            ForEach(werte, id: \.schluessel) { e in ringKarte(e.schluessel, e.belegt, e.farbton, e.text, e.hilfe, eng: eng) }
        }
    }

    private func ringKarte(_ k: String, _ belegt: Double, _ farbton: Color, _ text: String, _ hilfe: String, eng: Bool) -> some View {
        let ziel: Reiter = k == "ram" || k == "akku" ? .mac : (k == "platte" ? .platten : .claude)
        let name = Bereich.alle.first { $0.schluessel == k }?.name ?? k
        let unter = ringUnter(k, text, leer: text == "–", eng: eng)
        return Button { ringGewaehlt(k, ziel) } label: {
            VStack(spacing: 6) {
                PanelRing(anteil: belegt, farbton: farbton, text: text, claude: k == "woche" || k == "fuenf", durchmesser: eng ? 78 : 96, strich: eng ? 8 : 9, mitte: modell.ringSymbol(k))
                    .opacity(flugJetzt?.quelle == k ? 0 : 1)
                    .anchorPreference(key: RingOrte.self, value: .bounds) { [k: $0] }
                Text(name).font(.lauf(13).weight(.semibold)).foregroundColor(.text).lineLimit(1)
                Text(unter).font(.lauf(13)).foregroundColor(.grau).lineLimit(1)
            }
            .padding(eng ? 8 : 12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.karte))
            .contentShape(Rectangle())
        }
        .buttonStyle(DruckStil(radius: 10)).focusable().help(hilfe)
        .accessibilityLabel(name).accessibilityValue(hilfe)
    }

    private func ringUnter(_ k: String, _ text: String, leer: Bool, eng: Bool) -> String {
        if leer { return (k == "woche" || k == "fuenf") && !modell.darf(.claude) ? L("ohne Freigabe", "no permission") : L("noch kein Wert", "no value yet") }
        switch k {
        case "ram": return (eng ? "" : L("belegt, ", "used, ")) + L("\(modell.speicher.frei) % frei", "\(modell.speicher.frei) % free")
        case "platte": return modell.engstesFach.map { (eng ? "" : L("belegt, ", "used, ")) + L("\(prozent($0.freiProzent)) frei", "\(prozent($0.freiProzent)) free") } ?? ""
        case "akku":
            guard let a = modell.akku else { return "" }
            return a.laedt ? L("lädt", "charging") : (a.amStrom ? L("am Strom", "plugged in") : L("ohne Strom", "on battery"))
        default: return L("\(text) % genutzt", "\(text) % used")
        }
    }

    /// Der Höhepunkt: Derselbe Ring wandert in die Seitenleiste, die Fläche blendet dabei um.
    private func ringGewaehlt(_ k: String, _ ziel: Reiter) {
        if ruhig {
            modell.reiter = ziel
            return
        }
        flugStand = 0
        flug = RingFlug(quelle: k, ziel: ziel)
        modell.reiter = ziel
        withAnimation(.spring(response: 0.42, dampingFraction: 1)) { flugStand = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { flug = nil }
    }

    @ViewBuilder private func fliegenderRing(_ orte: [String: Anchor<CGRect>]) -> some View {
        GeometryReader { g in
            if let f = flugJetzt, let a = orte[f.quelle], let b = orte["reiter-" + f.ziel.rawValue],
               let e = RingWerte(modell: modell).alle.first(where: { $0.schluessel == f.quelle }) {
                let von = g[a], nach = g[b], p = standJetzt
                let zielAnteil = f.ziel == .claude ? claudeKurz.anteil : (f.ziel == .mac ? macKurz.anteil : plattenKurz.anteil)
                PanelRing(anteil: e.belegt + (zielAnteil - e.belegt) * p, farbton: e.farbton, text: e.text, claude: f.ziel == .claude,
                          durchmesser: von.width + (nach.width - von.width) * p, strich: 9 - 5 * p, inhalt: max(0, 1 - p * 2.5), mitte: modell.ringSymbol(f.quelle))
                    .position(x: von.midX + (nach.midX - von.midX) * p, y: von.midY + (nach.midY - von.midY) * p)
            }
        }
        .allowsHitTesting(false)
    }

    /// Fehlt eine Freigabe, sagt der Bereich das und führt mit einem Knopf dorthin.
    private func freigabeFehlt(_ f: Freigabe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ohneFreigabeText(f)).font(.lauf(13)).foregroundColor(.grau).fixedSize(horizontal: false, vertical: true)
            umrissKnopf(L("Zu den Freigaben", "Go to permissions")) { modell.zuDenFreigaben(f) }
        }
    }

    /// Orange bleibt dem einen nächsten Schritt vorbehalten, die stillere Stufe darunter ist dieser Umriss.
    private func umrissKnopf(_ name: String, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Text(name).font(.lauf(13).weight(.semibold)).foregroundColor(.text)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(DruckStil(radius: 8)).focusable().fixedSize()
    }

    private func orangerKnopf(_ name: String, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Text(name).font(.lauf(13).weight(.semibold)).foregroundColor(.tinte)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange2))
        }
        .buttonStyle(DruckStil(radius: 8)).focusable().fixedSize()
    }

    /// Rot mit weißer Schrift, damit man ihn sieht und nicht aus Versehen trifft.
    private var beendenKnopf: some View {
        Button(action: { NSApp.terminate(nil) }) {
            Text(L("Beenden", "Quit")).font(.lauf(13).weight(.semibold)).foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.rotFlaeche))
        }
        .buttonStyle(DruckStil(radius: 8)).focusable().fixedSize().padding(.leading, 8)
    }

    private func ohneFreigabeText(_ f: Freigabe) -> String {
        L("Für diesen Bereich fehlt die Freigabe \u{201E}\(f.name)\u{201C}.", "This area needs the permission \u{201C}\(f.name)\u{201D}.")
    }

    @ViewBuilder private var claudeLage: some View {
        if modell.darf(.claude) { claudeLageWerte } else { freigabeFehlt(.claude) }
    }

    private var claudeLageWerte: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let w = modell.woche {
                Text(L("Woche: ", "Week: ") + restzeit(bis: w.neuAm)).font(.lauf(13)).foregroundColor(.grau).fixedSize(horizontal: false, vertical: true)
                if let p = modell.prognoseText("woche") { Text(p.text).font(.lauf(13)).foregroundColor(p.warnung ? .gelb : .grau).fixedSize(horizontal: false, vertical: true) }
            } else {
                Text(keinLimitText).font(.lauf(13)).foregroundColor(.grau).fixedSize(horizontal: false, vertical: true)
            }
            Text(fensterKurz).font(.lauf(13)).foregroundColor(.grau).lineLimit(1)
        }
    }

    private var fensterKurz: String {
        let f = modell.fenster
        return L("\(f.arbeiten) \(f.arbeiten == 1 ? "arbeitet" : "arbeiten") · \(f.warten) \(f.warten == 1 ? "wartet" : "warten") · \(f.ruhig) ruhig", "\(f.arbeiten) working · \(f.warten) waiting · \(f.ruhig) idle")
    }

    @ViewBuilder private var bremseLage: some View {
        if modell.darf(.bremse) { bremseLageWerte } else { freigabeFehlt(.bremse) }
    }

    private var bremseLageWerte: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(modell.bremse == .aktiv && modell.logLesbar ? L("Sie schützt den Mac und hält schwere Starts an, solange der Speicher knapp ist.", "It protects the Mac and holds back heavy starts while memory is short.") : blockadeText)
                .font(.lauf(13)).foregroundColor(.grau).fixedSize(horizontal: false, vertical: true)
            angehalten
        }
    }

    private var angehalten: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L("Heute angehalten", "Held back today")).font(.lauf(13)).foregroundColor(.text)
            Spacer(minLength: 4)
            Text("\(modell.blockadenHeute)").font(.kopf(16)).monospacedDigit().foregroundColor(.text)
        }
    }

    @ViewBuilder private var claude: some View {
        if modell.darf(.claude) {
            claudeWerte
        } else {
            VStack(spacing: 12) {
                Karte(titel: L("CLAUDE-LIMITS · VOLL HEISST PAUSE", "CLAUDE LIMITS · FULL MEANS PAUSE")) { freigabeFehlt(.claude) }
                Spacer(minLength: 0)
                untereReihe
            }
        }
    }

    private var claudeWerte: some View {
        VStack(spacing: 12) {
            Karte(titel: L("CLAUDE-LIMITS · VOLL HEISST PAUSE", "CLAUDE LIMITS · FULL MEANS PAUSE")) {
                if modell.fuenfStunden == nil && modell.woche == nil {
                    Klein(text: keinLimitText)
                } else {
                    VStack(spacing: 12) {
                        limitZeile(L("Woche", "Week"), modell.woche, "woche")
                        limitZeile(L("5 Stunden", "5 hours"), modell.fuenfStunden, "fuenf")
                    }
                    if let s = modell.limitStand, Date().timeIntervalSince(s) > 1800 {
                        Klein(text: L("Stand vor \(Int(Date().timeIntervalSince(s) / 60)) Minuten. Kein Fenster hat seitdem geantwortet.", "As of \(Int(Date().timeIntervalSince(s) / 60)) minutes ago. No window has replied since."))
                    }
                }
            }
            Karte(titel: L("CLAUDE-FENSTER", "CLAUDE WINDOWS")) {
                HStack {
                    fensterZahl(modell.fenster.arbeiten, L("arbeiten", "working"), .text)
                    fensterZahl(modell.fenster.warten, L("warten auf dich", "waiting for you"), modell.fenster.warten > 0 ? .orange2 : .text)
                    fensterZahl(modell.fenster.ruhig, modell.fenster.ruhige.isEmpty ? L("ruhig", "idle") : L("ruhig · \(zahl(modell.fenster.ruhigeGB)) GB", "idle · \(zahl(modell.fenster.ruhigeGB)) GB"), .text)
                }
                ruhigeListe
            }
            Spacer(minLength: 0)
            untereReihe
        }
    }

    /// Codex und Tipp teilen sich eine Reihe, damit die Fläche auch mit beiden auf einen Bildschirm passt.
    @ViewBuilder private var untereReihe: some View {
        let mitCodex = modell.codex != .keinCodex
        if mitCodex || modell.tippSichtbar {
            HStack(alignment: .top, spacing: 12) {
                if mitCodex { Karte(titel: "CODEX", fuellen: true) { codexInhalt } }
                if modell.tippSichtbar { Karte(titel: L("TIPP", "TIP"), fuellen: true) { tippInhalt } }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var codexInhalt: some View {
        if !modell.darf(.codex) {
            freigabeFehlt(.codex)
        } else if case .wert(let w)? = modell.codex {
            let f = DateFormatter()
            let _ = f.locale = sprachOrt
            let _ = f.dateFormat = Calendar.current.isDateInToday(w.stand) ? "HH:mm" : "dd.MM. HH:mm"
            if w.neuAm > Date() {
                BalkenZeile(name: codexFenster(w.fensterMinuten), wert: L("\(Int(w.prozent)) % genutzt", "\(Int(w.prozent)) % used"), prozent: w.prozent, farbton: farbe(modell.limitFarbe(w.prozent)), textFarbton: textFarbe(modell.limitFarbe(w.prozent)), sichtbar: sichtbar)
                ZweiSeiten(links: restzeit(bis: w.neuAm).components(separatedBy: " · ")[0], rechts: L("Stand \(f.string(from: w.stand))", "As of \(f.string(from: w.stand))"))
            } else {
                Klein(text: L("Kein aktueller Wert. Der letzte Stand ist von \(f.string(from: w.stand)) Uhr, das Limit wurde seitdem neu gesetzt.", "No current value. The last reading is from \(f.string(from: w.stand)), the limit has reset since."))
            }
        } else {
            Klein(text: L("Kein Wert vorhanden. Er erscheint, sobald Codex geantwortet hat.", "No value yet. It appears once Codex has replied."))
        }
    }

    private func codexFenster(_ minuten: Int) -> String {
        if minuten == 10080 { return L("Woche", "Week") }
        return L("\(minuten / 60) Stunden", "\(minuten / 60) hours")
    }

    private var tippInhalt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Dreimal in 30 Tagen fast am Limit. Ein freies Werkzeug meldet vorab, ab wann es teuer wird.", "Almost at the limit three times in 30 days. A free tool tells you in advance when things get expensive.")).font(.lauf(13)).foregroundColor(.grau).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                umrissKnopf(L("Ansehen", "View")) { modell.tippErledigt(oeffnen: true) }
                stillerKnopf(L("Ausblenden", "Dismiss")) { modell.tippErledigt(oeffnen: false) }
            }
        }
    }

    /// Ruhige Fenster beim Namen. Die Liste scrollt in ihrem Kasten, die Fläche bleibt stehen.
    @ViewBuilder private var ruhigeListe: some View {
        let liste = modell.fenster.ruhige
        if liste.isEmpty {
            Klein(text: L("Gerade kein ruhiges Fenster. Offen lassen: Fenster, die arbeiten oder auf dich warten.", "No idle window right now. Keep open: windows that are working or waiting for you."))
        } else {
            // Mit Tipp fehlt der Platz für den ersten Satz. Die angeschnittene letzte Zeile zeigt, dass die Liste rollt.
            if !modell.tippSichtbar {
                Klein(text: L("Ruhig heißt: tut nichts. Schließen kannst nur du, das Gespräch bleibt erhalten.", "Idle means: doing nothing. Only you can close it, the conversation is kept."))
            }
            Klein(text: fensterFindenText(liste))
            // Das Selbstfoto kann keine Rollfläche zeichnen und nimmt den sichtbaren Ausschnitt.
            Group {
                if imFoto { VStack(spacing: 0) { ruhigeZeilen(Array(liste.prefix(listeEng ? 3 : 5))) } } else { ScrollView { VStack(spacing: 0) { ruhigeZeilen(liste) } } }
            }
            .frame(height: min(CGFloat(liste.count) * 27, listeEng ? 67 : 121), alignment: .top).clipped()
        }
    }

    /// Tipp, Codex-Balken und der Hinweis auf einen alten Stand kosten Höhe, die Liste gibt sie ab.
    private var listeEng: Bool {
        var codexBalken = false
        if case .wert? = modell.codex { codexBalken = modell.darf(.codex) }
        let alterStand = modell.limitStand.map { Date().timeIntervalSince($0) > 1800 } ?? false
        return modell.tippSichtbar || codexBalken || alterStand
    }

    /// Sagt, wie man ein Fenster aus der Liste wiederfindet. Hinter dem Satz steht nur, was die App belegen kann.
    private func fensterFindenText(_ liste: [RuhigesFenster]) -> String {
        if liste.contains(where: { $0.nummer != nil }) {
            return L("Finden: In VS Code auf einen Terminal-Reiter zeigen, dort steht die Nummer.", "To find one: in VS Code, hover over a terminal tab, it shows the number.")
        }
        return L("Finden: Die Zeile nennt das Programm, die Startzeit trennt gleiche Ordner.", "To find one: the row names the app, the start time separates equal folders.")
    }

    private func ruhigeZeilen(_ liste: [RuhigesFenster]) -> some View {
        ForEach(Array(liste.enumerated()), id: \.element.id) { i, f in
            HStack(spacing: 10) {
                Text(f.ordner).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                // Feste Spalten, sonst springt jede Zeile mit der Länge ihres Ordnernamens.
                Text(f.start.map(startText) ?? "").foregroundColor(.grau).monospacedDigit().lineLimit(1).frame(width: 122, alignment: .trailing)
                Text(f.ruhigSeit.map(seitText) ?? "").foregroundColor(.grau).lineLimit(1).frame(width: 88, alignment: .trailing)
                Text(f.nummer.map { "Nr. " + String($0) } ?? f.programm ?? "").foregroundColor(.grau).monospacedDigit().lineLimit(1).frame(width: 70, alignment: .trailing)
                Text("\(zahl(f.gb)) GB").monospacedDigit().lineLimit(1).frame(width: 52, alignment: .trailing)
            }
            .font(.lauf(13)).foregroundColor(.text).padding(.vertical, 5).padding(.trailing, 12)
            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) } }
        }
    }

    @ViewBuilder private func limitZeile(_ name: String, _ limit: Limit?, _ schluessel: String) -> some View {
        if let limit {
            VStack(spacing: 0) {
                BalkenZeile(name: name, wert: L("\(Int(limit.prozent)) % genutzt", "\(Int(limit.prozent)) % used"), prozent: limit.prozent, farbton: farbe(modell.limitFarbe(limit.prozent)), textFarbton: textFarbe(modell.limitFarbe(limit.prozent)), sichtbar: sichtbar)
                // „Reicht nicht“ wird nie abgeschnitten: Passt beides nicht in eine Zeile, bekommt die Prognose eine eigene.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(restzeit(bis: limit.neuAm)).fixedSize().foregroundColor(.grau)
                        Spacer(minLength: 4)
                        if let p = modell.prognoseText(schluessel) { Text(p.text).fixedSize().foregroundColor(p.warnung ? .gelb : .grau) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(restzeit(bis: limit.neuAm)).lineLimit(1).foregroundColor(.grau)
                        if let p = modell.prognoseText(schluessel) { Text(p.text).fixedSize(horizontal: false, vertical: true).foregroundColor(p.warnung ? .gelb : .grau) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.lauf(13)).padding(.top, 8)
            }
        }
    }

    private func fensterZahl(_ n: Int, _ name: String, _ f: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(n)").font(.kopf(16)).foregroundColor(f).monospacedDigit()
            Text(name).font(.lauf(13)).foregroundColor(.grau).lineLimit(1).fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mac: some View {
        let s = modell.speicher
        let rot = modell.schwellen.rot
        return VStack(spacing: 12) {
            Karte(titel: L("ARBEITSSPEICHER · VOLL HEISST, DER MAC WIRD LANGSAM", "MEMORY · FULL MEANS THE MAC SLOWS DOWN")) {
                BalkenZeile(name: L("Belegt", "Used"), wert: "\(100 - s.frei) %", prozent: Double(100 - s.frei), farbton: farbe(modell.stufe), textFarbton: textFarbe(modell.stufe), sichtbar: sichtbar)
                HStack(alignment: .firstTextBaseline) {
                    Text(L("Noch \(s.frei) % frei, rund \(zahl(s.ram * Double(s.frei) / 100 / GB)) GB.", "\(s.frei) % free, about \(zahl(s.ram * Double(s.frei) / 100 / GB)) GB.")).font(.lauf(13)).foregroundColor(.grau)
                    Spacer(minLength: 4)
                    // Der Akku bekommt die freie Seite dieser Zeile. Als eigene Karte passt er nicht auf die Fläche.
                    if let a = modell.akku { Text(L("Akku ", "Battery ") + akkuText(a)).font(.lauf(13).weight(.medium)).monospacedDigit().foregroundColor(!a.amStrom && a.prozent <= 10 ? .rotText : .text).fixedSize() }
                }
                Klein(text: L("Wird es eng, packt der Mac Daten zusammen und lagert sie auf die Platte aus. Gerade: \(Int(s.gepresst / GB)) von \(Int(rot.gepresstFach * s.ram / GB)) GB gepackt, \(Int(s.swap / GB)) von \(Int(rot.swapFach * s.ram / GB)) GB ausgelagert. Solange der Balken grün ist, ist das normal.", "When space runs short, the Mac compresses data and moves it to the drive. Right now: \(Int(s.gepresst / GB)) of \(Int(rot.gepresstFach * s.ram / GB)) GB compressed, \(Int(s.swap / GB)) of \(Int(rot.swapFach * s.ram / GB)) GB moved. While the bar is green, that is normal."))
            }
            Spacer(minLength: 0)
            Karte(titel: L("WAS IHN BELEGT", "WHAT IS USING IT")) {
                if modell.beleger.isEmpty { Klein(text: L("Wird gemessen …", "Measuring …")) }
                VStack(spacing: 0) {
                    ForEach(Array(modell.beleger.prefix(4).enumerated()), id: \.element.id) { i, b in
                        HStack(spacing: 10) {
                            Text(b.prozesse > 1 ? "\(b.name) · \(b.prozesse) " + L("Prozesse", "processes") : b.name).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text("\(zahl(b.gb)) GB").monospacedDigit()
                        }
                        .font(.lauf(13)).foregroundColor(.text).padding(.vertical, 6)
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) } }
                    }
                }
                Klein(text: L("Ein Prozess ist ein laufender Teil eines Programms. macOS-Dienste gehören zum System. Bei Claude Code zählt mit, was die Fenster gestartet haben.", "A process is a running part of an app. macOS services belong to the system. Claude Code includes what its windows started."))
            }
            Spacer(minLength: 0)
            Karte(titel: L("BREMSE · SCHÜTZT DEN MAC, HÄLT SCHWERE STARTS AN", "BRAKE · PROTECTS THE MAC, HOLDS BACK HEAVY STARTS")) {
                if modell.darf(.bremse) {
                    angehalten
                    Klein(text: blockadeText)
                } else {
                    freigabeFehlt(.bremse)
                }
            }
        }
    }

    private var blockadeText: String {
        if modell.bremse == .fehlt { return L("Die Speicher-Bremse ist nicht installiert, daher zählt die App nichts. Alles andere geht auch ohne sie.", "The memory brake is not installed, so the app counts nothing. Everything else works without it.") }
        if !modell.logLesbar { return L("Das Log der Bremse ist gerade nicht lesbar. Starte die App neu, wenn das bleibt.", "The brake log cannot be read right now. Restart the app if this persists.") }
        guard let d = modell.letzteBlockade else { return L("Noch keine Blockade. Laufende Arbeit geht immer weiter.", "No blocks yet. Running work always continues.") }
        let f = DateFormatter()
        f.locale = sprachOrt
        f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "dd.MM. HH:mm"
        let jung = modell.blockadenZehnMinuten
        return L("Zuletzt \(f.string(from: d)) Uhr", "Last at \(f.string(from: d))") + " · \(modell.blockadeGrund)" + (jung > 0 ? L(" · \(jung) in den letzten 10 Minuten", " · \(jung) in the last 10 minutes") : "") + L(". Laufende Arbeit geht weiter.", ". Running work continues.")
    }

    private var platten: some View {
        VStack(spacing: 12) {
            Karte(titel: L("PLATTEN · VOLL HEISST, ARBEIT KANN SCHEITERN", "DRIVES · FULL MEANS WORK CAN FAIL")) {
                if modell.faecher.isEmpty { Klein(text: L("Wird gemessen …", "Measuring …")) }
                VStack(spacing: 10) {
                    ForEach(modell.faecher) { f in
                        if let platte = f.platte {
                            BalkenZeile(name: f.name == plattenName(platte) ? f.name : plattenName(platte) + " · " + f.name, wert: L("\(prozent(100 - f.freiProzent)) belegt · \(zahl(f.frei)) GB frei", "\(prozent(100 - f.freiProzent)) used · \(zahl(f.frei)) GB free"), prozent: 100 - f.freiProzent, farbton: farbe(modell.plattenStufe(f)), textFarbton: textFarbe(modell.plattenStufe(f)), sichtbar: sichtbar)
                        } else {
                            ZweiSeiten(links: f.name, rechts: L("nicht angeschlossen", "not connected"))
                        }
                    }
                }
            }
            Karte(titel: L("GRÖSSTE ORDNER · LÖSCHEN TUST NUR DU", "LARGEST FOLDERS · ONLY YOU DELETE")) {
                if modell.darf(.ordner) { ordnerBereich } else { freigabeFehlt(.ordner) }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var ordnerBereich: some View {
        let _ = modell.ordnerStand
        let messung = modell.ordnerHeute
        ordnerKopf
        if let fehler = modell.ordnerFehler {
            Text(fehler).font(.lauf(12)).foregroundColor(.rotText).fixedSize(horizontal: false, vertical: true)
        } else if modell.ordnerLaeuft {
            Klein(text: L("Wird im Hintergrund gemessen, das dauert ein paar Minuten. Du kannst weiterarbeiten.", "Measuring in the background, this takes a few minutes. You can keep working."))
        } else if let messung {
            let liste = messung.liste
            let linke = Array(liste.prefix(5)), rechte = Array(liste.dropFirst(5))
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 0) { ForEach(linke) { ordnerZeile($0) } }
                VStack(spacing: 0) { ForEach(rechte) { ordnerZeile($0) } }
            }
            Klein(text: (messung.unvollstaendig ? L("Einige Ordner gab macOS nicht frei, sie fehlen. ", "macOS withheld some folders, they are missing. ") : "") + L("Klick zeigt den Ordner im Finder. Das Schloss heißt: nicht löschen. Ohne Schloss entscheidest du, sieh vorher hinein. Gefahrlos: Papierkorb leeren, alte Downloads, den Inhalt von Caches (Zwischenspeicher, baut sich neu auf), nicht den Ordner selbst.", "Click shows the folder in Finder. The lock means: do not delete. Without a lock it is your call, look inside first. Safe: empty the Trash, old downloads, the contents of Caches, not the folder itself."))
        } else {
            Klein(text: L("Die Messung läuft im Hintergrund und dauert ein paar Minuten. macOS fragt dabei vielleicht nach Zugriff. Gelesen werden nur Größen, gelöscht wird nichts.", "The measurement runs in the background and takes a few minutes. macOS may ask for access. Only sizes are read, nothing is deleted."))
        }
    }

    /// Die Reihe darf nie breiter werden als die Karte, sonst schiebt sie das ganze Panel zur Seite.
    var ordnerKopf: some View {
        HStack(spacing: 10) {
            if modell.plattenWahl.count > 1 { plattenAuswahl }
            Spacer(minLength: 4)
            if modell.ordnerLaeuft {
                ProgressView().controlSize(.small)
                stillerKnopf(L("Abbrechen", "Cancel")) { modell.ordnerAbbrechen() }
            } else if modell.ordnerHeute == nil {
                orangerKnopf(L("Messen", "Measure")) { modell.ordnerMessen() }
            } else {
                Button { modell.ordnerMessen() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13)).foregroundColor(.grau).frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(DruckStil()).focusable().help(L("Neu messen", "Measure again")).accessibilityLabel(L("Neu messen", "Measure again"))
                if modell.ordnerZiel == home {
                    stillerKnopf(L("Caches öffnen", "Open Caches")) { NSWorkspace.shared.open(URL(fileURLWithPath: home + "/Library/Caches")) }
                }
            }
        }
        .frame(minHeight: 32)
    }

    /// Bis drei Platten als Umschalter, darüber wird die Reihe zu breit und es bleibt ein Menü.
    @ViewBuilder private var plattenAuswahl: some View {
        let wahl = modell.plattenWahl
        if wahl.count <= 3 {
            HStack(spacing: 0) {
                ForEach(wahl, id: \.wurzel) { p in
                    wahlKnopf(p.name.count > 16 ? p.name.prefix(15) + "…" : p.name, modell.ordnerZiel == p.wurzel, "platte") { platteWaehlen(p.wurzel) }
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.spur))
        } else {
            Menu(wahl.first { $0.wurzel == modell.ordnerZiel }?.name ?? "") {
                ForEach(wahl, id: \.wurzel) { p in Button(p.name) { platteWaehlen(p.wurzel) } }
            }
            .frame(maxWidth: 220)
        }
    }

    private func platteWaehlen(_ wurzel: String) {
        modell.ordnerWurzel = wurzel
        modell.ordnerFehler = nil
    }

    /// Der Weg ab der Platte. Der letzte Teil allein sagt oft nichts, etwa „projects“.
    private func ordnerName(_ o: GrosserOrdner) -> String {
        if (o.pfad as NSString).lastPathComponent == ".Trash" { return L("Papierkorb", "Trash") }
        guard let z = modell.ordnerZiel, o.pfad.hasPrefix(z + "/") else { return o.name }
        return String(o.pfad.dropFirst(z.count + 1))
    }

    private func groesse(_ gb: Double) -> String {
        gb >= 1 ? "\(zahl(gb)) GB" : "\(Int((gb * 1024).rounded())) MB"
    }

    private func ordnerZeile(_ o: GrosserOrdner) -> some View {
        Button { modell.ordnerZeigen(o) } label: {
            HStack(spacing: 6) {
                if o.geschuetzt { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundColor(.gelb) }
                Text(ordnerName(o)).font(.lauf(13)).foregroundColor(.text).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 2)
                Text(groesse(o.gb)).font(.lauf(13)).monospacedDigit().foregroundColor(.grau).fixedSize()
            }
            .padding(.vertical, 5).padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(DruckStil()).focusable()
        .help(o.pfad + (o.geschuetzt ? " · " + L("Nicht löschen, das braucht dein System oder laufende Arbeit.", "Do not delete, your system or running work needs this.") : ""))
        .accessibilityLabel(o.name).accessibilityValue(groesse(o.gb) + (o.geschuetzt ? ", " + L("nicht löschen", "do not delete") : ""))
    }

    private var einstellungen: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                seitenAuswahl
                Spacer(minLength: 4)
                Text(Modell.version).font(.lauf(13)).foregroundColor(.grau)
                beendenKnopf
            }
            if modell.einstellSeite == .allgemein {
                allgemein
            } else {
                freigabenKarte
                Spacer(minLength: 0)
            }
        }
    }

    private var seitenAuswahl: some View {
        HStack(spacing: 0) {
            wahlKnopf(L("Allgemein", "General"), modell.einstellSeite == .allgemein, "seite") { modell.einstellSeite = .allgemein }
            wahlKnopf(L("Freigaben", "Permissions"), modell.einstellSeite == .freigaben, "seite") { modell.einstellSeite = .freigaben }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.spur))
        .animation(ruhig ? nil : .interpolatingSpring(stiffness: 200, damping: 22), value: modell.einstellSeite)
    }

    /// Dieselbe Karte beim ersten Start und in den Einstellungen.
    private var freigabenKarte: some View {
        Karte(titel: L("FREIGABEN", "PERMISSIONS")) {
            Klein(text: L("Ohne Freigabe zeigt die App nur Arbeitsspeicher und Füllstand der Platten. Alles bleibt auf diesem Mac, nichts geht ins Netz.", "Without permission the app only shows memory and drive usage. Everything stays on this Mac, nothing goes online."))
            VStack(spacing: 0) {
                ForEach(Array(Freigabe.allCases.enumerated()), id: \.element.rawValue) { i, f in
                    freigabeZeile(f)
                        .padding(.vertical, 8)
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) } }
                }
            }
        }
    }

    private func freigabeZeile(_ f: Freigabe) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.name).font(.lauf(13).weight(.medium)).foregroundColor(.text)
                    Text(f.liest).font(.lauf(12)).foregroundColor(.grau).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if modell.darf(f) {
                    Text(L("FREIGEGEBEN", "PERMITTED")).font(.mikro(12)).tracking(0.6).foregroundColor(.gruen).fixedSize()
                    stillerKnopf(L("Zurücknehmen", "Revoke")) { modell.freigabeZuruecknehmen(f) }
                } else if modell.freigabeFrage != f {
                    umrissKnopf(L("Freigeben", "Permit")) { modell.freigabeFrage = f }.accessibilityLabel(f.name + ": " + L("Freigeben", "Permit"))
                }
            }
            if modell.freigabeFrage == f {
                HStack(spacing: 10) {
                    Text(L("Möchtest du es wirklich freigeben?", "Do you really want to permit this?")).font(.lauf(13).weight(.medium)).foregroundColor(.text)
                    orangerKnopf(L("Ja", "Yes")) { modell.freigabeBestaetigen() }
                    stillerKnopf(L("Nein", "No")) { modell.freigabeFrage = nil }
                }
            }
        }
    }

    private func stillerKnopf(_ name: String, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Text(name).font(.lauf(13)).foregroundColor(.grau).padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(DruckStil()).focusable().fixedSize()
    }

    /// Erster Start: nur diese eine Aufgabe, deshalb ohne Seitenleiste.
    var einrichtung: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RLogo(breite: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("RAVARO Monitor einrichten", "Set up RAVARO Monitor")).font(.kopf(16)).foregroundColor(.text)
                    Text(L("Was darf die App lesen? Jede Freigabe kannst du später in den Einstellungen ändern.", "What may the app read? You can change every permission later in Settings.")).font(.lauf(13)).foregroundColor(.grau)
                }
            }
            freigabenKarte
            Spacer(minLength: 0)
            HStack {
                Spacer()
                orangerKnopf(modell.freigaben.isEmpty ? L("Ohne Freigabe weiter", "Continue without permission") : L("Fertig", "Done")) { modell.einrichtungFertig = true }
            }
        }
        .padding(20)
        .frame(width: panelGroesse.width, height: panelGroesse.height)
        .background(Color.flaeche)
    }

    private var allgemein: some View {
        VStack(spacing: 12) {
            Karte(titel: L("LASCHE", "TAB")) {
                HStack(spacing: 10) {
                    Text(L("Ort", "Position")).font(.lauf(13)).foregroundColor(.text)
                    Spacer(minLength: 4)
                    formAuswahl
                }
                .frame(minHeight: 32)
                zeigenZeile
                    .frame(minHeight: 32)
                HStack(spacing: 8) {
                    Text(L("Größe", "Size")).font(.lauf(13)).foregroundColor(.text)
                    Spacer(minLength: 4)
                    groessenAuswahl
                }
                .frame(minHeight: 32)
                if modell.letzterBereich {
                    Klein(text: L("Ein Bereich bleibt immer sichtbar, sonst wäre die Lasche leer.", "One area always stays visible, otherwise the tab would be empty."))
                }
            }
            Spacer(minLength: 0)
            Karte(titel: L("MITTEILUNGEN", "NOTIFICATIONS")) {
                HStack {
                    Text(L("Mitteilungen", "Notifications")).font(.lauf(13)).foregroundColor(.text)
                    Spacer()
                    Schalter(an: modell.mitteilung, name: L("Mitteilung", "Notifications")) { modell.mitteilung.toggle() }
                }
                Klein(text: (modell.akku == nil ? L("Bei Blockade, voller Platte und Limit ab 90 %.", "For blocks, full drives and limits from 90 %.") : L("Bei Blockade, voller Platte, Limit ab 90 % und Akku ab 10 %.", "For blocks, full drives, limits from 90 % and battery from 10 %.")) + (modell.bremse == .fehlt ? "" : L(" Die Bremse läuft unabhängig davon.", " The brake runs regardless.")))
                HStack(spacing: 8) {
                    Text(L("Platte voll unter", "Drive full below")).font(.lauf(13)).lineLimit(1).fixedSize().foregroundColor(.text)
                    Spacer()
                    stufenKnopf("minus", L("Grenze senken", "Lower threshold"), aktiv: modell.grenzeProzent > 1) { modell.grenzeProzent -= 1 }.help(modell.grenzeProzent > 1 ? "" : L("1 % ist die kleinste Grenze.", "1 % is the lowest threshold."))
                    Text("\(modell.grenzeProzent) % " + L("frei", "free")).font(.lauf(13).weight(.semibold)).monospacedDigit().foregroundColor(.text).frame(width: 72)
                    stufenKnopf("plus", L("Grenze erhöhen", "Raise threshold"), aktiv: modell.grenzeProzent < 30) { modell.grenzeProzent += 1 }.help(modell.grenzeProzent < 30 ? "" : L("30 % ist die größte Grenze.", "30 % is the highest threshold."))
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Karte(titel: L("ALLGEMEIN", "GENERAL")) {
                HStack(spacing: 10) {
                    Text(L("Sprache", "Language")).font(.lauf(13)).foregroundColor(.text)
                    sprachAuswahl
                    Spacer(minLength: 4)
                    Text(L("Beim Anmelden starten", "Start at login")).font(.lauf(13)).foregroundColor(.text)
                    Spacer()
                    Schalter(an: modell.autostart, name: L("Beim Anmelden starten", "Start at login")) { modell.autostartUmschalten() }
                }
                .frame(minHeight: 32)
                if let fehler = modell.startFehler { Text(fehler).font(.lauf(12)).foregroundColor(.rotText).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
        }
    }

    private func stufenKnopf(_ symbol: String, _ name: String, aktiv: Bool, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundColor(.text)
                .frame(width: 24, height: 24).background(Circle().fill(Color.spur))
                .padding(10).contentShape(Rectangle()).padding(-10)
        }
        .buttonStyle(DruckStil(radius: 12)).focusable().disabled(!aktiv).opacity(aktiv ? 1 : 0.4).accessibilityLabel(name)
    }

    var zeigenZeile: some View {
        HStack(spacing: 8) {
            Text(L("Zeigen", "Show")).font(.lauf(13)).foregroundColor(.text).fixedSize()
            Spacer(minLength: 4)
            ForEach(modell.bereiche, id: \.schluessel) { b in bereichKnopf(b) }
        }
    }

    /// Die Knöpfe sind zugleich die Legende: Symbol und Wort stehen nebeneinander.
    private func bereichKnopf(_ b: Bereich) -> some View {
        let an = !modell.ausgeblendet.contains(b.schluessel)
        let letzter = modell.letzterBereich
        return Button { modell.bereichUmschalten(b.schluessel) } label: {
            HStack(spacing: 4) {
                Image(systemName: b.symbol).font(.system(size: 11))
                Text(b.name).font(.lauf(12)).lineLimit(1).fixedSize()
                if an { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
            }
            .foregroundColor(an ? .text : .grau)
            .padding(.horizontal, modell.bereiche.count > 4 ? 6 : 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(an ? 0.12 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(an ? 0.24 : 0.08), lineWidth: 1))
            .padding(.vertical, 10).contentShape(Rectangle()).padding(.vertical, -10)
        }
        .buttonStyle(DruckStil()).focusable().disabled(an && letzter).accessibilityLabel(b.name).accessibilityValue(an ? L("sichtbar", "shown") : L("ausgeblendet", "hidden"))
    }

    /// Einzelwahl sieht anders aus als die Mehrfachwahl „Zeigen“: ein Behälter, ein gleitender Anzeiger.
    private var formAuswahl: some View {
        HStack(spacing: 0) {
            wahlKnopf(L("Links", "Left"), modell.form == .links, "form") { modell.form = .links }
            wahlKnopf(L("Rechts", "Right"), modell.form == .lasche, "form") { modell.form = .lasche }
            wahlKnopf(L("Oben", "Top"), modell.form == .bruecke, "form") { modell.form = .bruecke }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.spur))
        .animation(ruhig ? nil : .interpolatingSpring(stiffness: 200, damping: 22), value: modell.form)
    }

    private var groessenAuswahl: some View {
        HStack(spacing: 0) {
            ForEach(LaschenGroesse.allCases, id: \.rawValue) { g in
                wahlKnopf(g.name, modell.laschenGroesse == g, "groesse") { modell.laschenGroesse = g }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.spur))
        .animation(ruhig ? nil : .interpolatingSpring(stiffness: 200, damping: 22), value: modell.laschenGroesse)
    }

    private var sprachAuswahl: some View {
        HStack(spacing: 0) {
            ForEach(Sprache.allCases, id: \.rawValue) { s in
                wahlKnopf(s.name, modell.sprache == s, "sprache") { modell.sprache = s }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.spur))
        .animation(ruhig ? nil : .interpolatingSpring(stiffness: 200, damping: 22), value: modell.sprache)
    }

    private func wahlKnopf(_ name: String, _ aktiv: Bool, _ gruppe: String, aktion: @escaping () -> Void) -> some View {
        return Button(action: aktion) {
            Text(name).font(.lauf(12)).foregroundColor(aktiv ? .text : .grau).lineLimit(1).fixedSize()
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background {
                    if aktiv { RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.12)).matchedGeometryEffect(id: gruppe, in: auswahl) }
                }
                .padding(.vertical, 10).contentShape(Rectangle()).padding(.vertical, -10)
        }
        .buttonStyle(DruckStil()).focusable().accessibilityValue(aktiv ? L("gewählt", "selected") : "")
    }
}
