# RAVARO Monitor

**v1.26** · Stand 2026-10-30 · Akku als eigener Bereich, Einrichtung der Limits ohne Zusatzprogramme

Kleine Mac-App für alle, die mit Claude Code arbeiten. Sie sitzt als Lasche am Bildschirmrand und zeigt Wochenlimit, 5-Stunden-Limit, Arbeitsspeicher, Platte und, wenn der Mac einen hat, den Akku. Ein Klick klappt die Details auf: Prognose fürs Limit, ruhende Fenster, größte Ordner.

*English below.*

## Installieren

Du brauchst macOS 13 oder neuer und die Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/RRavaro/ravaro-monitor.git
cd ravaro-monitor
app/bau.sh
open ~/Applications/RAVARO\ Monitor.app
```

Beim ersten Start fragt die App, was sie lesen darf. Ohne dein Ja zeigt sie nur Arbeitsspeicher und Platten. Jede Freigabe lässt sich später unter Einstellungen ändern.

## Limits einrichten

Die Limits kommen aus der Statuszeile von Claude Code. Trage in `~/.claude/settings.json` ein, mit dem Pfad zu deinem Ordner:

```json
{ "statusLine": { "type": "command", "command": "bash /PFAD/ZU/ravaro-monitor/app/limits-statuszeile.sh" } }
```

Hast du schon eine eigene Statuszeile, ruf das Skript dort zusätzlich auf und gib ihm dieselben Daten weiter. Die Werte erscheinen nach der nächsten Antwort in einem Claude-Fenster. Das klappt nur mit einem Claude-Abo, API-Konten haben diese Limits nicht.

## Was die App nicht tut

- Kein Login, kein Schlüsselbund, keine Verbindung ins Netz.
- Sie löscht nie etwas. Die größten Ordner zeigt sie dir, löschen tust du selbst.

Blockaden zählt sie nur zusammen mit einer Speicher-Bremse unter `~/.claude/hooks/speicher-bremse.py`. Ohne Bremse läuft alles andere genauso.

## Bedingungen

Der Quelltext ist öffentlich einsehbar, aber kein Open Source. Es gelten die Bedingungen in `LICENSE.md`, Name und Logo bleiben Pflicht. RAVARO Monitor ist ein unabhängiges Werkzeug und stammt nicht von Anthropic oder OpenAI. Schriften: Space Grotesk, Inter, JetBrains Mono (SIL Open Font License). Eine Windows-Fassung gibt es nicht, `WINDOWS.md` ist nur ein Bauplan.

---

## English

A small Mac app for people working with Claude Code. It sits as a tab at the edge of your screen and shows the weekly limit, the 5-hour limit, memory, disk and, if your Mac has one, the battery. One click opens the details.

**Install:** macOS 13 or later and the Xcode Command Line Tools, then run the commands above. On first launch the app asks what it may read. Without your yes it only shows memory and drives.

**Limits:** add the `statusLine` entry above to `~/.claude/settings.json`, using the path to your folder. If you already have a status line, call the script from it and pass the same input along. Values appear after the next reply in a Claude window. This needs a Claude subscription, API accounts do not have these limits.

**What it does not do:** no login, no keychain, no network connection. It never deletes anything.

**Terms:** the source is public but not open source. `LICENSE.md` applies, name and logo must stay. RAVARO Monitor is an independent tool and does not come from Anthropic or OpenAI.
