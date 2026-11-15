#!/usr/bin/bash
# Baustufe "cosmic-comp-scroll" (siehe Containerfile).
#
# Baut cosmic-comp aus genau dem Quellpaket, das Fedora gerade ausliefert, und legt
# den Scroll-Streifen-Patch obendrauf. Ergebnis nach /out:
#   cosmic-comp   das gepatchte Binary
#   NVR           Version-Release des Quellpakets, z. B. 1.11.0-2.fc44
#   STATUS        "OK" oder der Grund, warum es nicht geklappt hat
#
# Diese Stufe bricht absichtlich NIE den Image-Bau ab. Passt der Patch nicht mehr auf
# eine neue COSMIC-Version, behält das Image das unveränderte cosmic-comp, und alle
# übrigen Updates kommen trotzdem an. einspielen.sh entscheidet und meldet.

set -uo pipefail

here="$(dirname "$(readlink -f "$0")")"
top=/tmp/rpmbuild
mkdir -p /out

fail() {
    echo "FEHLER: $*" | tee /out/STATUS
    exit 0
}

echo "::group::cosmic-comp-scroll: Werkzeuge und Bauabhängigkeiten"
dnf -y install rpm-build 'dnf5-command(builddep)' 'dnf5-command(download)' ||
    fail "Bauwerkzeuge nicht installierbar"
dnf -y builddep cosmic-comp || fail "Bauabhängigkeiten von cosmic-comp nicht installierbar"
echo "::endgroup::"

cd /tmp || fail "kein /tmp"
dnf -y download --source cosmic-comp || fail "Quellpaket cosmic-comp nicht ladbar"
srpm="$(ls cosmic-comp-*.src.rpm 2>/dev/null | head -1)"
[[ -n $srpm ]] || fail "Quellpaket cosmic-comp fehlt nach dem Download"
nvr="$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$srpm")"
echo "$nvr" >/out/NVR
echo "cosmic-comp-scroll: Quellpaket $srpm ($nvr)"

rpm -i --define "_topdir $top" "$srpm" || fail "Quellpaket $nvr nicht entpackbar"
cp "$here/cosmic-comp-scroll.patch" "$top/SOURCES/" || fail "Patch-Datei fehlt"
# %autosetup -p1 im Spec wendet jede PatchN-Zeile an
sed -i '/^Source2:/a Patch9000:      cosmic-comp-scroll.patch' "$top/SPECS/cosmic-comp.spec"
grep -q '^Patch9000:' "$top/SPECS/cosmic-comp.spec" ||
    fail "Spec von $nvr hat keine Source2-Zeile mehr, Patch nicht eintragbar"

rpmbuild --define "_topdir $top" -bp "$top/SPECS/cosmic-comp.spec" >/tmp/prep.log 2>&1 || {
    tail -30 /tmp/prep.log
    fail "Patch passt nicht auf cosmic-comp $nvr"
}

echo "::group::cosmic-comp-scroll: Kompilieren"
rpmbuild --define "_topdir $top" --define 'debug_package %{nil}' --nocheck \
    -bb "$top/SPECS/cosmic-comp.spec" || fail "cosmic-comp $nvr mit Patch kompiliert nicht"
echo "::endgroup::"

rpm="$(ls "$top"/RPMS/*/cosmic-comp-[0-9]*.rpm 2>/dev/null | head -1)"
[[ -n $rpm ]] || fail "kein RPM nach dem Bau"
mkdir -p /tmp/extract && cd /tmp/extract &&
    rpm2cpio "$rpm" | cpio -idm --quiet ./usr/bin/cosmic-comp ||
    fail "Binary nicht aus dem RPM lösbar"
install -m 0755 /tmp/extract/usr/bin/cosmic-comp /out/cosmic-comp || fail "Binary nicht kopierbar"

echo OK >/out/STATUS
echo "cosmic-comp-scroll: gebaut für $nvr"
