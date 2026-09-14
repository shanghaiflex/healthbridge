#!/bin/sh
# Build BoW and put it on the iPhone — over the cable or over Wi-Fi (the phone is paired for network use).
#   sh phone.sh            build + install + launch
#   sh phone.sh --check    only say whether the phone is reachable and how (wired / localNetwork)
# Personal-team signing lives 7 days: run this once a week (or when the app stops opening).
set -e
cd "$(dirname "$0")"
UDID="${BOW_DEVICE:-00008030-001119CA0E3B802E}"
JSON=$(mktemp)
xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1 || true
STATE=$(python3 - "$JSON" "$UDID" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for dev in d["result"]["devices"]:
    if sys.argv[2] in dev["hardwareProperties"].get("udid", "") or sys.argv[2] in str(dev["connectionProperties"].get("potentialHostnames", "")):
        cp = dev["connectionProperties"]
        print(f"{dev['deviceProperties']['name']}: {cp.get('transportType')}, tunnel {cp.get('tunnelState')}")
        break
else:
    print("not found")
PY
)
rm -f "$JSON"
echo "phone: $STATE"
[ "$1" = "--check" ] && exit 0
case "$STATE" in "not found"*) echo "iPhone is neither on the cable nor on this Wi-Fi — nothing to do"; exit 1;; esac

xcodebuild -project BoW.xcodeproj -scheme BoW -destination "id=$UDID" -configuration Debug \
  -derivedDataPath build/device -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD" || true
APP=build/device/Build/Products/Debug-iphoneos/BoW.app
[ -d "$APP" ] || { echo "build failed"; exit 1; }
xcrun devicectl device install app --device "$UDID" "$APP" 2>&1 | grep -E "installationURL|rror" || true
xcrun devicectl device process launch --device "$UDID" cc.bodywithoutorgans.bow 2>&1 | tail -1
PROFILE=$(ls -t ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision 2>/dev/null | head -1)
[ -n "$PROFILE" ] && echo "profile expires: $(security cms -D -i "$PROFILE" 2>/dev/null | grep -A1 ExpirationDate | tail -1 | sed 's/.*<date>\(.*\)<\/date>.*/\1/')"
