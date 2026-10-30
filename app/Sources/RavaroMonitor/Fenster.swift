import AppKit
import Combine
import SwiftUI

/// Schwebt über allem, auch über Vollbild-Apps, und nimmt anderen Programmen nie den Fokus.
final class SchwebeFenster: NSPanel {
    init(groesse: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: groesse), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }
    /// Erster Start: Das Fenster erscheint, ohne die Tastatur zu nehmen, bis der Nutzer hineinklickt.
    var ohneTastatur = false
    override var canBecomeKey: Bool { !ohneTastatur }
}

@MainActor
final class Steuerung {
    private let modell: Modell
    private let griff = SchwebeFenster(groesse: NSSize(width: 114, height: 540))
    private let detail = SchwebeFenster(groesse: panelGroesse)
    private let hinweis = SchwebeFenster(groesse: NSSize(width: 360, height: 180))
    private let erklaer = SchwebeFenster(groesse: NSSize(width: 280, height: 100))
    private var erklaerStart: DispatchWorkItem?
    private var abos = Set<AnyCancellable>()
    private var ausserhalb: Any?
    private var tasten: Any?
    private var erstKlick: Any?
    private var meldungsEnde: DispatchWorkItem?

    init(modell: Modell) {
        self.modell = modell
    }

    func starten() {
        griffInhalt()
        detail.contentView = festeGroesse(DetailWurzel(modell: modell).environment(\.colorScheme, .dark))
        detail.hasShadow = true
        modell.$form.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.griffInhalt() }
        }.store(in: &abos)
        modell.$laschenGroesse.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.griffInhalt() }
        }.store(in: &abos)
        modell.$meldung.sink { [weak self] m in
            DispatchQueue.main.async { self?.meldungZeigen(m) }
        }.store(in: &abos)
        erklaer.ignoresMouseEvents = true
        modell.$erklaerung.removeDuplicates().sink { [weak self] e in
            DispatchQueue.main.async { self?.erklaerungZeigen(e) }
        }.store(in: &abos)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.platzieren() }
        }
        // Für die Abnahme: öffnet und schließt das Panel von außen.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("de.ravaro.monitor.umschalten"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.umschalten() }
        }
        probeAnschliessen()
        griff.orderFrontRegardless()
        // Erster Start: Die Frage erscheint von selbst, nimmt aber nicht die Tastatur. Wer gerade tippt, drückt so nichts aus Versehen.
        if !modell.einrichtungFertig { oeffnen(fokus: false) }
    }

    /// Nur in Proben mit eigener Ablage: schaltet Reiter ohne Maus und meldet, was wirklich steht.
    private func probeAnschliessen() {
        guard let ablage = ProcessInfo.processInfo.environment["RAVARO_ABLAGE"] else { return }
        modell.$reiter.dropFirst().sink { [weak self] r in
            DispatchQueue.main.async {
                guard let self else { return }
                print("reiter: \(r.rawValue) fenster: \(Int(self.detail.frame.width))x\(Int(self.detail.frame.height)) sichtbar: \(self.detail.isVisible)")
                fflush(stdout)
            }
        }.store(in: &abos)
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("de.ravaro.monitor.probe"), object: nil, queue: .main) { [weak self] n in
            guard let auftrag = n.object as? String, auftrag.hasPrefix(ablage + "|") else { return }
            let wert = String(auftrag.dropFirst(ablage.count + 1))
            MainActor.assumeIsolated { self?.probeBefehl(wert) }
        }
    }

    private func probeBefehl(_ wert: String) {
        if wert == "oeffnen" {
            umschalten()
        } else if let r = Reiter(rawValue: wert) {
            modell.reiter = r
        } else if wert.hasPrefix("groesse:"), let g = LaschenGroesse(rawValue: String(wert.dropFirst(8))) {
            modell.laschenGroesse = g
        } else if wert.hasPrefix("sprache:"), let s = Sprache(rawValue: String(wert.dropFirst(8))) {
            modell.sprache = s
        } else if wert == "zustand" {
            print("tastatur: \(detail.isKeyWindow) panel: \(detail.isVisible)")
            let f = griff.frame
            let schirm = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
            modell.zustandAusgeben(rand: ["griffLinks": f.minX, "griffRechts": f.maxX, "schirmLinks": schirm.minX, "schirmRechts": schirm.maxX, "luecke": Double(randLuecke(modell))])
        } else if wert.hasPrefix("frage:"), let f = Freigabe(rawValue: String(wert.dropFirst(6))) {
            modell.freigabeFrage = f
        } else if wert.hasPrefix("fehlt:"), let f = Freigabe(rawValue: String(wert.dropFirst(6))) {
            modell.zuDenFreigaben(f)
        } else if wert == "ja" {
            modell.freigabeBestaetigen()
        } else if wert == "nein" {
            modell.freigabeFrage = nil
        } else if wert.hasPrefix("entziehen:"), let f = Freigabe(rawValue: String(wert.dropFirst(10))) {
            modell.freigabeZuruecknehmen(f)
        } else if wert == "ordner:messen" {
            modell.ordnerMessen()
        } else if wert.hasPrefix("ordner:zeigen:"), let i = Int(wert.dropFirst(14)), let o = modell.ordnerHeute?.liste[i] {
            modell.ordnerZeigen(o)
        } else if wert == "tipp:weg" {
            modell.tippErledigt(oeffnen: false)
        } else if wert == "fertig" {
            modell.einrichtungFertig = true
        }
    }

    /// Ohne das passt sich das Fenster dem Inhalt an und rutscht vom Rand weg.
    private func festeGroesse<V: View>(_ inhalt: V) -> NSHostingView<V> {
        let v = NSHostingView(rootView: inhalt)
        v.sizingOptions = []
        return v
    }

    private func griffInhalt() {
        let umschalten: () -> Void = { [weak self] in self?.umschalten() }
        let groesse: NSSize
        switch modell.form {
        case .links, .lasche:
            let s = modell.laschenGroesse.skala
            griff.contentView = festeGroesse(
                HStack {
                    if modell.form == .lasche { Spacer(minLength: 0) }
                    LaschenPlatz(modell: modell, aktion: umschalten)
                    if modell.form == .links { Spacer(minLength: 0) }
                }
                    .frame(maxHeight: .infinity).environment(\.colorScheme, .dark))
            groesse = NSSize(width: 114 * s, height: 540 * s)
        case .bruecke:
            let s = modell.laschenGroesse.skala
            griff.contentView = festeGroesse(
                VStack {
                    Bruecke(modell: modell, aktion: umschalten)
                        .frame(width: 800, height: 84, alignment: .top).scaleEffect(s).frame(width: 800 * s, height: 84 * s)
                    Spacer(minLength: 0)
                }
                    .frame(maxWidth: .infinity).environment(\.colorScheme, .dark))
            groesse = NSSize(width: 800 * s, height: 84 * s)
        }
        griff.setContentSize(groesse)
        platzieren()
    }

    private func platzieren() {
        guard let schirm = NSScreen.main ?? NSScreen.screens.first else { return }
        let f = schirm.visibleFrame
        let g = griff.frame.size
        let d = detail.frame.size
        let s = modell.laschenGroesse.skala
        switch modell.form {
        case .links:
            griff.setFrameOrigin(NSPoint(x: f.minX, y: f.midY - g.height / 2))
            detail.setFrameOrigin(NSPoint(x: f.minX + 64 * s + 10, y: f.midY - d.height / 2))
        case .lasche:
            griff.setFrameOrigin(NSPoint(x: f.maxX - g.width, y: f.midY - g.height / 2))
            detail.setFrameOrigin(NSPoint(x: f.maxX - 64 * s - d.width - 10, y: f.midY - d.height / 2))
        case .bruecke:
            griff.setFrameOrigin(NSPoint(x: f.midX - g.width / 2, y: f.maxY - g.height))
            detail.setFrameOrigin(NSPoint(x: f.midX - d.width / 2, y: max(f.minY, f.maxY - 66 * s - d.height)))
        }
        hinweis.setFrameOrigin(NSPoint(x: f.maxX - hinweis.frame.width - 12, y: f.maxY - hinweis.frame.height - 10))
    }

    func umschalten() {
        modell.offen ? schliessen() : oeffnen()
    }

    private func oeffnen(fokus: Bool = true) {
        platzieren()
        modell.reiter = .uebersicht
        modell.einstellSeite = .allgemein
        modell.freigabeFrage = nil
        modell.offen = true
        modell.erklaerung = nil
        modell.messen(alles: true)
        detail.ohneTastatur = !fokus
        detail.orderFrontRegardless()
        if fokus {
            detail.makeKey()
        } else {
            erstKlick = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
                MainActor.assumeIsolated {
                    guard let self, e.window === self.detail else { return }
                    self.detail.ohneTastatur = false
                    self.detail.makeKey()
                }
                return e
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.detail.invalidateShadow() }
        ausserhalb = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.schliessen() }
        }
        tasten = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 {
                MainActor.assumeIsolated { self?.schliessen() }
                return nil
            }
            if e.keyCode == 125 || e.keyCode == 126 {
                MainActor.assumeIsolated { self?.reiterWechseln(e.keyCode == 125 ? 1 : -1) }
                return nil
            }
            return e
        }
    }

    private func reiterWechseln(_ schritt: Int) {
        let alle = Reiter.allCases
        let i = alle.firstIndex(of: modell.reiter) ?? 0
        modell.reiter = alle[min(alle.count - 1, max(0, i + schritt))]
    }

    private func schliessen() {
        modell.offen = false
        if let ausserhalb { NSEvent.removeMonitor(ausserhalb) }
        if let tasten { NSEvent.removeMonitor(tasten) }
        if let erstKlick { NSEvent.removeMonitor(erstKlick) }
        ausserhalb = nil
        tasten = nil
        erstKlick = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !self.modell.offen else { return }
            self.detail.orderOut(nil)
        }
    }

    /// Kurz verzögert, damit beim Vorbeifahren nichts aufblitzt. Das offene Panel erklärt sich selbst.
    private func erklaerungZeigen(_ e: Erklaerung?) {
        erklaerStart?.cancel()
        guard let e, !modell.offen else {
            erklaer.orderOut(nil)
            return
        }
        let start = DispatchWorkItem { [weak self] in
            guard let self, let inhalt = self.erklaerText(e.schluessel) else { return }
            let ansicht = ErklaerAnsicht(titel: inhalt.titel, text: inhalt.text).environment(\.colorScheme, .dark)
            let s = NSHostingView(rootView: ansicht).fittingSize, r = e.rechteck
            self.erklaer.contentView = festeGroesse(ansicht)
            self.erklaer.setContentSize(s)
            switch self.modell.form {
            case .links: self.erklaer.setFrameOrigin(NSPoint(x: r.maxX + 16, y: r.midY - s.height / 2))
            case .lasche: self.erklaer.setFrameOrigin(NSPoint(x: r.minX - s.width - 16, y: r.midY - s.height / 2))
            case .bruecke: self.erklaer.setFrameOrigin(NSPoint(x: r.midX - s.width / 2, y: r.minY - s.height - 16))
            }
            self.erklaer.orderFrontRegardless()
        }
        erklaerStart = start
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: start)
    }

    private func erklaerText(_ schluessel: String) -> (titel: String, text: String)? {
        if schluessel == "griff" { return ("RAVARO Monitor", modell.akku == nil ? L("Klicken klappt die Details auf. Auf allen Ringen gilt: Voll heißt schlecht.", "Click to open the details. On every ring: full means bad.") : L("Klicken klappt die Details auf. Voll heißt schlecht, nur beim Akku ist voll gut.", "Click to open the details. Full means bad, only on the battery is full good.")) }
        if schluessel == "blockaden" { return (L("Blockaden heute", "Blocks today"), L("Die Speicher-Bremse hat heute \(modell.blockadenHeute) schwere Starts angehalten. Laufende Arbeit geht weiter.", "The memory brake held back \(modell.blockadenHeute) heavy starts today. Running work continues.")) }
        return RingWerte(modell: modell).eintraege.first { $0.schluessel == schluessel }.map { ($0.titel, $0.hilfe) }
    }

    private func meldungZeigen(_ m: Meldung?) {
        meldungsEnde?.cancel()
        guard let m else {
            hinweis.orderOut(nil)
            return
        }
        NSLog("RAVARO Monitor Mitteilung: %@ – %@", m.titel, m.text)
        hinweis.contentView = festeGroesse(
            VStack { MeldungsAnsicht(meldung: m) { [weak self] in
                self?.modell.meldung = nil
                if self?.modell.offen == false { self?.umschalten() }
            }; Spacer(minLength: 0) }.environment(\.colorScheme, .dark))
        hinweis.orderFrontRegardless()
        let ende = DispatchWorkItem { [weak self] in self?.modell.meldung = nil }
        meldungsEnde = ende
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: ende)
    }
}

/// Das Panel fährt beim Aufklappen vom Griff weg auf, die Balken laufen dabei hoch.
struct DetailWurzel: View {
    @ObservedObject var modell: Modell
    @Environment(\.accessibilityReduceMotion) private var ruhig

    var body: some View {
        let anker: UnitPoint = modell.form == .bruecke ? .top : (modell.form == .links ? .leading : .trailing)
        Panel(modell: modell, sichtbar: modell.offen)
            .scaleEffect(modell.offen || ruhig ? 1 : 0.94, anchor: anker)
            .opacity(modell.offen ? 1 : 0)
            .animation(.easeOut(duration: modell.offen ? 0.24 : 0.15), value: modell.offen)
    }
}
