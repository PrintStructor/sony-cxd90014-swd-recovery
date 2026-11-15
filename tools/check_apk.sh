#!/bin/sh
# Pre-install check for Sony PMCA apps (ScalarALauncher needs a bitmap icon).
# Usage: tools/check_apk.sh app.apk   (needs aapt from the Android SDK build-tools)
APK="$1"; AAPT="${AAPT:-aapt}"; ok=1
B=$("$AAPT" dump badging "$APK" 2>/dev/null); rc=$?
if [ $rc -ne 0 ]; then
  # badging fails if the icon references a framework drawable (@android:drawable/...)
  X=$("$AAPT" dump xmltree "$APK" AndroidManifest.xml) || { echo "aapt failed"; exit 2; }
  if echo "$X" | grep -E "android:icon\(0x01010002\)=@0x0108" >/dev/null; then
    echo "OK    icon is a system (framework) drawable"
    echo "RESULT: icon check passed (framework icon; label/sdk not checked)"; exit 0
  fi
  echo "FAIL  could not read manifest icon"; exit 2
fi
icons=$(echo "$B" | grep -oE "application-icon-[0-9]+:'[^']*'|icon='[^']*'" | grep -oE "'[^']*'" | tr -d "'" | sort -u | grep -v '^$')
for i in $icons; do
  case "$i" in *.png) echo "OK    icon $i";; *) echo "FAIL  icon $i is not a PNG -> launcher crash / boot loop"; ok=0;; esac
done
[ -z "$icons" ] && { echo "FAIL  no icon found"; ok=0; }
act=$(echo "$B" | grep "launchable-activity")
echo "$act" | grep -q "label=''" && echo "WARN  launcher activity has no label (launcher logs NotFoundException)"
echo "$act" | grep -q "icon=''" && echo "WARN  launcher activity has no icon (falls back to application icon)"
sdk=$(echo "$B" | sed -n "s/^sdkVersion:'\([0-9]*\)'.*/\1/p")
[ -n "$sdk" ] && [ "$sdk" -gt 10 ] && echo "WARN  minSdkVersion $sdk > 10 (camera is API 10)"
unzip -l "$APK" | grep -qE "res/drawable[^ ]*\.png" || { echo "FAIL  no PNG in res/drawable*"; ok=0; }
[ $ok = 1 ] && echo "RESULT: icon check passed" || { echo "RESULT: DO NOT INSTALL"; exit 1; }
