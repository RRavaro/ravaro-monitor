import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppStart: NSObject, NSApplicationDelegate {
    private let modell = Modell()
    private var steuerung: Steuerung?

    func applicationDidFinishLaunching(_ note: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--foto"), i + 1 < args.count {
            Foto(modell: modell, ordner: args[i + 1]).starten()
            return
        }
        if args.contains("--werte") {
            werteAusgeben()
            return
        }
        if args.contains("--autostart-probe") {
            try? SMAppService.mainApp.register()
            let an = SMAppService.mainApp.status
            try? SMAppService.mainApp.unregister()
            print("nach Einschalten: \(an.rawValue), nach Ausschalten: \(SMAppService.mainApp.status.rawValue)")
            exit(0)
        }
        let eigene = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if eigene.count > 1 && ProcessInfo.processInfo.environment["RAVARO_ABLAGE"] == nil {
            NSApp.terminate(nil)
            return
        }
        modell.starten()
        steuerung = Steuerung(modell: modell)
        steuerung?.starten()
    }

    /// Für die Abnahme: gibt die gemessenen Werte als JSON aus.
    private func werteAusgeben() {
        modell.messen(alles: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [modell] in
            let m = modell
            let d: [String: Any] = [
                "frei": m.speicher.frei, "stufe": ["gruen", "gelb", "rot"][m.stufe.rawValue],
                "gepresst": m.speicher.gepresst / GB, "swap": m.speicher.swap / GB,
                "faecher": m.faecher.map { ["name": $0.name, "platte": $0.platte ?? "", "frei": $0.frei] as [String: Any] },
                "arbeiten": m.fenster.arbeiten, "warten": m.fenster.warten, "ruhig": m.fenster.ruhig,
                "fuenf": m.fuenfStunden?.prozent ?? -1, "woche": m.woche?.prozent ?? -1,
                "blockadenHeute": m.blockadenHeute, "autostart": m.autostart,
                "freigaben": m.freigaben.map(\.rawValue).sorted(), "bremse": "\(m.bremse)",
            ]
            if let j = try? JSONSerialization.data(withJSONObject: d), let s = String(data: j, encoding: .utf8) { print(s) }
            exit(0)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let start = MainActor.assumeIsolated { AppStart() }
app.delegate = start
app.run()
