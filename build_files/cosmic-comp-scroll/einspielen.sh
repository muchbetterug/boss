#!/usr/bin/bash
# Ersetzt im fertigen Image /usr/bin/cosmic-comp durch die gepatchte Fassung aus der
# Baustufe "cosmic-comp-scroll" - aber nur, wenn sie geklappt hat UND für genau die
# cosmic-comp-Version gebaut wurde, die build.sh installiert hat. Sonst bleibt das
# Original, und eine Warnung steht im Build-Protokoll.
#
# Was das Image enthält, steht danach in /usr/share/boss/cosmic-comp-scroll
# (auf dem laufenden System: cat /usr/share/boss/cosmic-comp-scroll).

set -euo pipefail

scroll=/scroll
marker=/usr/share/boss/cosmic-comp-scroll
mkdir -p "$(dirname "$marker")"

installed="$(rpm -q --qf '%{VERSION}-%{RELEASE}' cosmic-comp)"
status="$(cat "$scroll/STATUS" 2>/dev/null || echo "FEHLER: Baustufe hat kein Ergebnis geliefert")"
built="$(cat "$scroll/NVR" 2>/dev/null || echo unbekannt)"

if [[ $status == OK && $built == "$installed" && -x $scroll/cosmic-comp ]]; then
    install -m 0755 "$scroll/cosmic-comp" /usr/bin/cosmic-comp
    echo "gepatcht: cosmic-comp $installed mit Scroll-Streifen" | tee "$marker"
else
    if [[ $status == OK ]]; then
        status="gebaut für $built, installiert ist aber $installed"
    fi
    msg="UNVERÄNDERT: cosmic-comp $installed ohne Scroll-Streifen (${status#FEHLER: })"
    echo "$msg" | tee "$marker"
    # wird von GitHub Actions als Warnung am Lauf angezeigt
    echo "::warning title=cosmic-comp-scroll::$msg"
fi
