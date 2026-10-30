#!/bin/bash
# Statuszeile für Claude Code. Sie legt die Limits dort ab, wo RAVARO Monitor sie liest.
# Claude Code reicht die Werte als JSON herein. plutil gehört zu macOS, es braucht also keine Zusatzprogramme.
eingabe=$(cat)
ordner="$HOME/.claude/ctx-state"
mkdir -p "$ordner"
zwischen=$(mktemp "$ordner/rate-limits.XXXXXX")
# Ältere Claude-Code-Fassungen und API-Konten liefern keine Limits. Dann bleibt die alte Datei liegen.
if printf '%s' "$eingabe" | plutil -extract rate_limits json -o "$zwischen" - 2>/dev/null; then
    mv "$zwischen" "$ordner/rate-limits.json"
else
    rm -f "$zwischen"
fi
