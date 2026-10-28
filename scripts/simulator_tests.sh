#!/bin/bash
# Simulator test run (GitHub Actions, .github/workflows/test.yml):
#   1. dependencies as for the IPA (ffmpeg-kit incl. arm64-simulator slices,
#      framework renames) — no secrets, no Last.fm keys
#   2. test targets added to the project (scripts/add_test_targets.rb)
#   3. Debug build for the newest iPad simulator (iPadOS 18+)
#   4. unit + UI tests with video and console log
#   5. screenshots exported from the xcresult
#   6. crossfade measurements (DEBUG harness) + analysis/diagrams
# Everything lands in build/test-output/.
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="$ROOT/build/test-output"
BUNDLE_ID="dev.jackderganove.resona"
rm -rf "$OUT"
mkdir -p "$OUT/screenshots" "$OUT/crossfade/raw" "$OUT/logs"

step() { echo; echo "=== $* ==="; }

step "Prepare dependencies"
PREPARE_ONLY=1 ./build_ipa.sh || { echo "dependency preparation failed"; exit 1; }

step "Add test targets"
ruby scripts/add_test_targets.rb || exit 1

step "Pick iPad simulator"
UDID="$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
data = json.load(sys.stdin)["devices"]
preferred = ["iPad Pro 13-inch (M5)", "iPad Pro 13-inch (M4)", "iPad Air 13-inch (M3)", "iPad Air 13-inch (M2)",
             "iPad Pro 11-inch (M5)", "iPad Pro 11-inch (M4)"]
best = None
for runtime, devices in data.items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m or int(m.group(1)) < 18:
        continue
    version = (int(m.group(1)), int(m.group(2)))
    for d in devices:
        if not d["name"].startswith("iPad"):
            continue
        rank = preferred.index(d["name"]) if d["name"] in preferred else len(preferred)
        key = (version, -rank)
        if best is None or key > best[0]:
            best = (key, d["udid"], d["name"], runtime)
if not best:
    sys.exit("no iPad simulator with iOS 18+")
print(best[1])
print(f"{best[2]} / {best[3]}", file=sys.stderr)
' 2> "$OUT/logs/simulator.txt")"
cat "$OUT/logs/simulator.txt"
[ -n "$UDID" ] || exit 1
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

DERIVED="/Volumes/TropBuild/DerivedDataTests"
COMMON=(-project "$ROOT/Trop.xcodeproj" -scheme ResonaTests -configuration Debug
        -destination "id=$UDID" -derivedDataPath "$DERIVED" SKIP_SWIFTLINT=YES)

step "Resolve packages (with retries for flaky downloads)"
for attempt in 1 2 3; do
    xcodebuild -resolvePackageDependencies -project "$ROOT/Trop.xcodeproj" -scheme ResonaTests \
        -derivedDataPath "$DERIVED" > "$OUT/logs/resolve-$attempt.log" 2>&1 && break
    echo "package resolution failed (attempt $attempt)"; tail -3 "$OUT/logs/resolve-$attempt.log"
    sleep 20
done

step "Build for testing (Debug, simulator)"
xcodebuild build-for-testing "${COMMON[@]}" > "$OUT/logs/xcodebuild-build.log" 2>&1
BUILD_STATUS=$?
grep -E "error:|\*\* (BUILD|TEST)" "$OUT/logs/xcodebuild-build.log" | sort -u | head -80
if [ $BUILD_STATUS -ne 0 ]; then
    tail -40 "$OUT/logs/xcodebuild-build.log"
    exit $BUILD_STATUS
fi

step "Unit + UI tests (video + console)"
xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT/ui-tests.mp4" > "$OUT/logs/video.log" 2>&1 &
VIDEO_PID=$!
xcrun simctl spawn "$UDID" log stream --style compact --level info --predicate 'process == "Trop"' \
    > "$OUT/logs/console.log" 2>&1 &
LOG_PID=$!
sleep 2
ONLY=()
IFS=',' read -ra ONLY_LIST <<< "${ONLY_TESTING:-}"
for t in ${ONLY_LIST[@]+"${ONLY_LIST[@]}"}; do ONLY+=("-only-testing:$t"); done
xcodebuild test-without-building "${COMMON[@]}" -parallel-testing-enabled NO ${ONLY[@]+"${ONLY[@]}"} \
    -resultBundlePath "$OUT/Resona.xcresult" > "$OUT/logs/xcodebuild-test.log" 2>&1
TEST_STATUS=$?
grep -E "Test Case .*(passed|failed)|error:|\*\* TEST" "$OUT/logs/xcodebuild-test.log" | head -120
kill -INT $VIDEO_PID 2>/dev/null; wait $VIDEO_PID 2>/dev/null

step "Export screenshots"
xcrun xcresulttool export attachments --path "$OUT/Resona.xcresult" --output-path "$OUT/attachments" >/dev/null 2>&1 || true
python3 - "$OUT/attachments" "$OUT/screenshots" <<'PY'
# Tour screenshots → screenshots/<name>.png (landscape ones rotated upright:
# XCUIScreen delivers the raw portrait framebuffer); everything else XCTest
# attached (debug descriptions, automatic screenshots) → screenshots/other/
# with file-system-safe names (artifact upload rejects quotes etc.).
import json, re, shutil, sys
from pathlib import Path
try:
    from PIL import Image
except ImportError:
    Image = None
src, dst = Path(sys.argv[1]), Path(sys.argv[2])
other = dst / "other"
other.mkdir(parents=True, exist_ok=True)
manifest = src / "manifest.json"
tour = rest = 0
if manifest.exists():
    for test in json.loads(manifest.read_text()):
        for a in test.get("attachments", []):
            file = src / a["exportedFileName"]
            if not file.exists():
                continue
            name = a.get("suggestedHumanReadableName") or a["exportedFileName"]
            name = re.sub(r"_\d+_[0-9A-Fa-f-]{36}", "", name)
            name = re.sub(r'[^A-Za-z0-9._ -]+', "_", name).strip() or a["exportedFileName"]
            if re.match(r"(portrait|landscape)-\d\d-", name):
                target = dst / name
                if not target.suffix:
                    target = target.with_suffix(".png")
                shutil.copy(file, target)
                if Image and name.startswith("landscape-"):
                    with Image.open(target) as im:
                        if im.height > im.width:
                            im.rotate(90, expand=True).save(target)
                tour += 1
            else:
                shutil.copy(file, other / name)
                rest += 1
print(f"{tour} tour screenshots, {rest} other attachments exported")
PY
xcrun xcresulttool get test-results summary --path "$OUT/Resona.xcresult" --compact > "$OUT/test-summary.json" 2>/dev/null || true
xcrun xcresulttool get test-results tests --path "$OUT/Resona.xcresult" --compact > "$OUT/test-list.json" 2>/dev/null || true

step "Crossfade measurements"
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null)"
if [ "${SKIP_CROSSFADE:-false}" = "true" ]; then
    echo "skipped (SKIP_CROSSFADE)"
elif [ -z "$DATA" ]; then
    echo "app not installed — no crossfade measurement"
else
    for case in fade3 fade10 skip pause off; do
        xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
        rm -f "$DATA/Documents/crossfade-$case".*
        echo "case $case"
        xcrun simctl launch "$UDID" "$BUNDLE_ID" -ResonaCrossfadeTest "$case" -ResonaUITest >/dev/null
        for _ in $(seq 1 150); do
            [ -f "$DATA/Documents/crossfade-$case.done" ] && break
            sleep 1
        done
        cp "$DATA/Documents/crossfade-$case".csv "$DATA/Documents/crossfade-$case".events "$OUT/crossfade/raw/" 2>/dev/null \
            || echo "  no result for $case"
    done
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    python3 scripts/analyze_crossfade.py "$OUT/crossfade/raw" "$OUT/crossfade" | tee "$OUT/crossfade/summary.md"
fi
kill $LOG_PID 2>/dev/null

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "## Simulator: $(cat "$OUT/logs/simulator.txt")"
        echo
        python3 - "$OUT/test-summary.json" <<'PY'
import json, sys
try:
    s = json.load(open(sys.argv[1]))
    print(f"Tests: {s.get('passedTests', '?')} bestanden, {s.get('failedTests', '?')} fehlgeschlagen, "
          f"{s.get('skippedTests', '?')} übersprungen — Ergebnis: {s.get('result', '?')}")
    for f in s.get("testFailures", [])[:40]:
        print(f"- ❌ {f.get('testName', '')}: {f.get('failureText', '')}")
except Exception as e:
    print("keine Testzusammenfassung:", e)
PY
        echo
        echo "### Crossfade"
        cat "$OUT/crossfade/summary.md" 2>/dev/null
    } >> "$GITHUB_STEP_SUMMARY"
fi

exit $TEST_STATUS
