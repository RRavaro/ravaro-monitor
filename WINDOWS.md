# RAVARO Monitor für Windows · Bauplan

**v1.0** · Stand 2026-10-30 · Bauplan, kein Code

Die Mac-Fassung lässt sich nicht übertragen, weil SwiftUI und die Messwerte nur auf dem Mac laufen. Für Windows entsteht eine eigene kleine App. Vorbild: der Windows-Teil von Codenotch (Rust und Tauri 2, MIT-Lizenz).

| Teil | Mac | Windows |
|---|---|---|
| Fenster | `NSPanel` am Rand | Tauri-Fenster ohne Rahmen, immer oben, am Bildschirmrand |
| Arbeitsspeicher | `kern.memorystatus_level`, Kompressor, Swap | `GlobalMemoryStatusEx`, Rust-Paket `sysinfo` |
| Größte Verbraucher | `ps` | `sysinfo` |
| Platten | `URLResourceValues` | `GetDiskFreeSpaceExW` oder `sysinfo` |
| Limits | `~/.claude/ctx-state/rate-limits.json` | gleicher Ort unter `%USERPROFILE%\.claude` |
| Fenster-Zustand | `~/.claude/sessions/*.json` | gleicher Ort, Feld `status` vor dem Bau gegenprüfen |
| Autostart | `SMAppService` | Tauri-Erweiterung `autostart` |

**Das muss vorher gelöst sein:**
1. Die Speicher-Bremse misst mit Mac-Befehlen und läuft unter Windows nicht. Sie braucht eigene Messwerte und eigene Grenzen, weil Windows keinen Kompressor-Wert wie macOS meldet.
2. `rate-limits.json` schreibt das Statuszeilen-Skript. Das ist ein Bash-Skript und braucht unter Windows Git Bash oder eine Fassung in PowerShell.
3. Der Installer ist ohne gekauftes Zertifikat unsigniert, SmartScreen warnt dann beim ersten Start.

**Reihenfolge:** Bremse portieren · Statuszeile portieren · Lasche · Panel · Mitteilung · Test auf einem echten Windows-Rechner. Hier auf dem Mac lässt sich das nicht prüfen.
