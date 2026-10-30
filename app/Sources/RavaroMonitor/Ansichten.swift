import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255)
    }
    static let flaeche = Color(hex: 0x17181B)
    static let leiste = Color(hex: 0x121316)
    static let karte = Color(hex: 0x1E2024)
    static let linie = Color.white.opacity(0.14)
    static let spur = Color(hex: 0x2A2C32)
    static let text = Color(hex: 0xF8F8F8)
    static let grau = Color(hex: 0xBBBEC3)
    static let grauLeise = Color(hex: 0xA6AAB2)
    static let tinte = Color(hex: 0x0A0B0D)
    static let orange2 = Color(hex: 0xFF7716)
    static let rot = Color(hex: 0xE62B34)
    static let rotText = Color(hex: 0xFF6A70)
    static let rotFlaeche = Color(hex: 0xD21F2A)
    static let gelb = Color(hex: 0xF5B83D)
    static let gruen = Color(hex: 0x5FD08A)
}

extension Font {
    static func kopf(_ g: CGFloat) -> Font { .custom("Space Grotesk", size: g).weight(.semibold) }
    static func lauf(_ g: CGFloat) -> Font { .custom("Inter", size: g) }
    static func mikro(_ g: CGFloat) -> Font { .custom("JetBrains Mono", size: g).weight(.bold) }
}

func textFarbe(_ s: Stufe) -> Color { s == .rot ? .rotText : farbe(s) }

func farbe(_ s: Stufe) -> Color {
    switch s {
    case .gruen: return .gruen
    case .gelb: return .gelb
    case .rot: return .rot
    }
}

let rBild: NSImage? = Bundle.main.url(forResource: "ravaro-r", withExtension: "png").flatMap(NSImage.init(contentsOf:))

/// Meldet das Überfahren auch dann, wenn die App nicht aktiv ist. `.help` tut das in diesem Fenster nicht verlässlich.
final class HoverFlaeche: NSView {
    var bei: (Bool, NSRect) -> Void = { _, _ in }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    private var rechteck: NSRect { window?.convertToScreen(convert(bounds, to: nil)) ?? .zero }
    override func mouseEntered(with event: NSEvent) { bei(true, rechteck) }
    override func mouseExited(with event: NSEvent) { bei(false, rechteck) }
}

struct HoverErkenner: NSViewRepresentable {
    var bei: (Bool, NSRect) -> Void
    func makeNSView(context: Context) -> HoverFlaeche { HoverFlaeche() }
    func updateNSView(_ v: HoverFlaeche, context: Context) { v.bei = bei }
}

/// Das Selbstfoto kann keine NSViews zeichnen und setzt sonst Platzhalter ins Bild.
let imFoto = CommandLine.arguments.contains("--foto")

extension View {
    @ViewBuilder func schwebe(_ bei: @escaping (Bool, NSRect) -> Void) -> some View {
        if imFoto { self } else { background(HoverErkenner(bei: bei)) }
    }
}

/// Hover, Gedrückt und Fokusring für alle Knöpfe, die keinen Systemrahmen haben.
struct DruckStil: ButtonStyle {
    var radius: CGFloat = 6
    func makeBody(configuration: Configuration) -> some View {
        DruckInhalt(konfiguration: configuration, radius: radius)
    }
}

private struct DruckInhalt: View {
    let konfiguration: ButtonStyle.Configuration
    var radius: CGFloat
    @State private var drueber = false
    @Environment(\.isFocused) private var fokus

    var body: some View {
        konfiguration.label
            .overlay(RoundedRectangle(cornerRadius: radius).fill(Color.white.opacity(konfiguration.isPressed ? 0.10 : (drueber ? 0.06 : 0))).allowsHitTesting(false))
            .overlay(RoundedRectangle(cornerRadius: radius + 2).stroke(Color.text, lineWidth: fokus ? 2 : 0).padding(-2).allowsHitTesting(false))
            .animation(.easeOut(duration: 0.08), value: drueber)
            .onHover { drueber = $0 }
    }
}

struct RLogo: View {
    var breite: CGFloat
    var body: some View {
        if let rBild {
            Image(nsImage: rBild).resizable().aspectRatio(contentMode: .fit).frame(width: breite)
                .accessibilityLabel("RAVARO")
        }
    }
}

struct Ring: View {
    var anteil: Double
    var farbton: Color
    var text: String
    var durchmesser: CGFloat = 40
    var claude = false
    var mitte: String?

    var body: some View {
        ZStack {
            Circle().stroke(Color.spur, lineWidth: 2)
            Circle().trim(from: 0, to: max(0.012, min(1, anteil / 100)))
                .stroke(farbton, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if claude { LimitSymbol().fill(Color.text.opacity(0.3)).frame(width: durchmesser * 0.55, height: durchmesser * 0.55) }
            if let mitte { Image(systemName: mitte).font(.system(size: durchmesser * 0.36)).foregroundColor(.text) } else { Text(text).font(.mikro(durchmesser > 36 ? 14 : 12)).foregroundColor(claude ? .orange2 : .text) }
        }
        .frame(width: durchmesser, height: durchmesser)
    }
}

/// Die Werte, die auch zugeklappt lesbar bleiben. Auf allen Ringen gilt: voll heißt schlecht.
@MainActor
struct RingWerte {
    var modell: Modell

    /// Was die Lasche zeigt: alle Bereiche außer den ausgeblendeten.
    var eintraege: [(schluessel: String, symbol: String, belegt: Double, farbton: Color, text: String, titel: String, hilfe: String)] {
        // Verschwindet der Akku, nachdem nur er sichtbar war, bliebe die Lasche sonst leer.
        let sichtbar = alle.filter { !modell.ausgeblendet.contains($0.schluessel) }
        return sichtbar.isEmpty ? alle : sichtbar
    }

    var alle: [(schluessel: String, symbol: String, belegt: Double, farbton: Color, text: String, titel: String, hilfe: String)] {
        let f5 = modell.fuenfStunden, wo = modell.woche
        let platte = modell.engstesFach
        let s = modell.speicher
        func limitHilfe(_ l: Limit?) -> String {
            guard modell.darf(.claude) else { return L("Ohne Freigabe. Das Panel führt dich zu den Freigaben.", "No permission yet. The panel takes you to the permissions.") }
            guard let l else { return keinLimitText }
            let rest = restzeit(bis: l.neuAm)
            return L("\(Int(l.prozent)) % verbraucht. Voller Ring: Claude pausiert bis zur Rückstellung.", "\(Int(l.prozent)) % used. Full ring: Claude pauses until the reset.") + " \(rest.prefix(1).uppercased() + rest.dropFirst())."
        }
        let plattenHilfe = platte.map { L("\(100 - Int($0.freiProzent.rounded())) % belegt, \(prozent($0.freiProzent)) frei (\(zahl($0.frei)) GB). Voller Ring: Arbeit kann scheitern.", "\(100 - Int($0.freiProzent.rounded())) % used, \(prozent($0.freiProzent)) free (\(zahl($0.frei)) GB). Full ring: work can fail.") } ?? L("Wird gemessen …", "Measuring …")
        var liste: [(String, Double, Color, String, String, String)] = [
            ("woche", wo?.prozent ?? 0, farbe(modell.limitFarbe(wo?.prozent ?? 0)), wo.map { "\(Int($0.prozent))" } ?? "–", L("Wochenlimit", "Weekly limit"), limitHilfe(wo)),
            ("fuenf", f5?.prozent ?? 0, farbe(modell.limitFarbe(f5?.prozent ?? 0)), f5.map { "\(Int($0.prozent))" } ?? "–", L("5-Stunden-Limit", "5-hour limit"), limitHilfe(f5)),
            ("ram", s.ram > 0 ? Double(100 - s.frei) : 0, s.ram > 0 ? farbe(modell.stufe) : .grau, s.ram > 0 ? "\(100 - s.frei)" : "–", L("Arbeitsspeicher (RAM)", "Memory (RAM)"), L("\(100 - s.frei) % belegt, \(s.frei) % frei. Voller Ring: Der Mac wird langsam, und die Bremse hält schwere Starts an.", "\(100 - s.frei) % used, \(s.frei) % free. Full ring: the Mac slows down and the brake holds back heavy starts.")),
            ("platte", platte.map { 100 - $0.freiProzent } ?? 0, platte.map { farbe(modell.plattenStufe($0)) } ?? .grau, platte.map { "\(100 - Int($0.freiProzent.rounded()))" } ?? "–", platte?.platte.map(plattenName) ?? L("Platte", "Drive"), plattenHilfe),
        ]
        if let a = modell.akku {
            liste.append(("akku", Double(a.prozent), a.amStrom ? .grau : farbe(modell.akkuStufe(a)), "\(a.prozent)", L("Akku", "Battery"), a.amStrom ? L("\(akkuText(a)). Der Mac hängt am Strom, deshalb ist der Ring grau.", "\(akkuText(a)). The Mac is on power, so the ring is grey.") : L("\(akkuText(a)). Hier ist es umgekehrt: Voller Ring heißt voller Akku. Je kürzer er wird, desto eher muss der Mac an den Strom.", "\(akkuText(a)). This one is the other way round: a full ring means a full battery. The shorter it gets, the sooner the Mac needs power.")))
        }
        return liste.map { e in
            (e.0, Bereich.alle.first { $0.schluessel == e.0 }?.symbol ?? "circle", e.1, e.2, e.3, e.4, e.5)
        }
    }
}

struct Abzeichen: View {
    var zahl: Int
    var body: some View {
        Text(zahl > 99 ? "99+" : "\(zahl)").font(.mikro(12)).foregroundColor(.white).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.rotFlaeche))
    }
}

/// Kurze Erklärung neben der Lasche, solange die Maus auf einem Bereich steht.
struct ErklaerAnsicht: View {
    var titel: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titel).font(.lauf(13).weight(.semibold)).foregroundColor(.text)
            Text(text).font(.lauf(12)).foregroundColor(.grau).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.flaeche))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.linie, lineWidth: 1))
    }
}

/// Dreistufiger Schatten für die Lasche, bei Blockade roter Schein.
private struct KoerperSchatten: ViewModifier {
    var rot: Bool
    func body(content: Content) -> some View {
        if rot {
            content.shadow(color: Color.rot.opacity(0.45), radius: 14, y: 6)
        } else {
            content
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
        }
    }
}

struct Lasche: View {
    @ObservedObject var modell: Modell
    var aktion: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var ruhig

    var body: some View {
        let rot = modell.blockiertGerade
        let links = modell.form == .links
        let form = UnevenRoundedRectangle(topLeadingRadius: links ? 0 : 20, bottomLeadingRadius: links ? 0 : 20, bottomTrailingRadius: links ? 20 : 0, topTrailingRadius: links ? 20 : 0)
        Button(action: aktion) {
            VStack(spacing: 8) {
                RLogo(breite: 30).padding(.bottom, 2)
                    .schwebe { an, r in modell.erklaeren(an ? "griff" : nil, r) }
                ForEach(RingWerte(modell: modell).eintraege, id: \.schluessel) { e in
                    let claude = e.schluessel == "fuenf" || e.schluessel == "woche"
                    VStack(spacing: 4) {
                        if modell.ringSymbol(e.schluessel) == nil { Image(systemName: e.symbol).font(.system(size: 12)).foregroundColor(.text) }
                        Ring(anteil: e.belegt, farbton: e.farbton, text: e.text, claude: claude, mitte: modell.ringSymbol(e.schluessel))
                    }
                    .schwebe { an, r in modell.erklaeren(an ? e.schluessel : nil, r) }
                }
                if rot { Text(L("angehalten", "held back")).font(.lauf(10)).foregroundColor(.text).lineLimit(1).fixedSize() }
                HStack(spacing: 4) {
                    if rot {
                        Abzeichen(zahl: modell.blockadenHeute)
                            .schwebe { an, r in modell.erklaeren(an ? "blockaden" : nil, r) }
                    }
                    Image(systemName: links ? "chevron.right" : "chevron.left").font(.system(size: 12, weight: .bold)).foregroundColor(.text)
                        .rotationEffect(.degrees(modell.offen ? 180 : 0))
                }
                .frame(height: 20)
            }
            .padding(.vertical, 12).frame(width: 64)
            .background(form.fill(Color.flaeche))
            .overlay(form.stroke(rot ? Color.rot : Color.linie, lineWidth: 1))
            .contentShape(form)
        }
        .buttonStyle(.plain)
        .modifier(KoerperSchatten(rot: rot))
        .animation(ruhig ? nil : .easeOut(duration: 0.25), value: modell.offen)
        .accessibilityLabel(L("RAVARO Monitor aufklappen", "Open RAVARO Monitor"))
    }
}

/// Der Platz der Lasche im Fenster. Der Körper steht am Bildschirmrand, der Rest bleibt Raum für den Schatten.
struct LaschenPlatz: View {
    @ObservedObject var modell: Modell
    var aktion: () -> Void = {}

    var body: some View {
        let s = modell.laschenGroesse.skala
        let links = modell.form == .links
        Lasche(modell: modell, aktion: aktion)
            .frame(width: 114, height: 540, alignment: links ? .leading : .trailing)
            .scaleEffect(s, anchor: links ? .leading : .trailing)
            .frame(width: 114 * s, height: 540 * s, alignment: links ? .leading : .trailing)
    }
}

struct Bruecke: View {
    @ObservedObject var modell: Modell
    var aktion: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var ruhig

    var body: some View {
        let rot = modell.blockiertGerade
        let form = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 20, bottomTrailingRadius: 20, topTrailingRadius: 0)
        Button(action: aktion) {
            HStack(spacing: 10) {
                RLogo(breite: 26)
                    .schwebe { an, r in modell.erklaeren(an ? "griff" : nil, r) }
                ForEach(RingWerte(modell: modell).eintraege, id: \.schluessel) { e in
                    let claude = e.schluessel == "fuenf" || e.schluessel == "woche"
                    HStack(spacing: 4) {
                        if modell.ringSymbol(e.schluessel) == nil { Image(systemName: e.symbol).font(.system(size: 12)).foregroundColor(.text) }
                        Ring(anteil: e.belegt, farbton: e.farbton, text: e.text, durchmesser: 36, claude: claude, mitte: modell.ringSymbol(e.schluessel))
                    }
                    .schwebe { an, r in modell.erklaeren(an ? e.schluessel : nil, r) }
                }
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundColor(.text)
                    .rotationEffect(.degrees(modell.offen ? 180 : 0))
                ZStack {
                    if rot {
                        HStack(spacing: 4) {
                            Abzeichen(zahl: modell.blockadenHeute)
                            Text(L("angehalten", "held back")).font(.lauf(10)).foregroundColor(.text).lineLimit(1).fixedSize()
                        }
                        .schwebe { an, r in modell.erklaeren(an ? "blockaden" : nil, r) }
                    }
                }
                .frame(width: 90)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(form.fill(Color.flaeche))
            .overlay(form.stroke(rot ? Color.rot : Color.linie, lineWidth: 1))
            .contentShape(form)
        }
        .buttonStyle(.plain)
        .modifier(KoerperSchatten(rot: rot))
        .animation(ruhig ? nil : .easeOut(duration: 0.25), value: modell.offen)
        .accessibilityLabel(L("RAVARO Monitor aufklappen", "Open RAVARO Monitor"))
    }
}

struct Klein: View {
    var text: String
    var body: some View {
        Text(text).font(.lauf(12)).foregroundColor(.grauLeise).fixedSize(horizontal: false, vertical: true)
    }
}

struct Schalter: View {
    var an: Bool
    var name: String
    var aktion: () -> Void
    @Environment(\.accessibilityReduceMotion) private var ruhig

    var body: some View {
        Button(action: aktion) {
            HStack(spacing: 6) {
                Text(an ? L("AN", "ON") : L("AUS", "OFF")).font(.mikro(12)).foregroundColor(an ? .text : .grau).frame(width: 28, alignment: .trailing)
                ZStack(alignment: an ? .trailing : .leading) {
                    Capsule().fill(an ? Color.text : Color.spur).frame(width: 32, height: 18)
                    Circle().fill(an ? Color.tinte : Color.grau).frame(width: 14, height: 14).padding(2)
                }
            }
            .animation(ruhig ? nil : .easeOut(duration: 0.25), value: an)
            .padding(.vertical, 13).contentShape(Rectangle()).padding(.vertical, -13)
        }
        .buttonStyle(DruckStil(radius: 10)).focusable().accessibilityLabel(name).accessibilityValue(an ? L("an", "on") : L("aus", "off"))
    }
}

struct MeldungsAnsicht: View {
    var meldung: Meldung
    var aktion: () -> Void = {}

    var body: some View {
        Button(action: aktion) {
            HStack(alignment: .top, spacing: 12) {
                RLogo(breite: 30).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(meldung.titel).font(.lauf(13).weight(.semibold)).foregroundColor(.text)
                    Text(meldung.text).font(.lauf(13)).foregroundColor(.grau).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(width: 360, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.flaeche))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.rot, lineWidth: 1))
            .shadow(color: Color.rot.opacity(0.45), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }
}
