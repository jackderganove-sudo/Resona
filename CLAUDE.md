# Resona (iPad) – notes for Claude

## Android device tests
- The Android twin (Resona-Android) is tested on Emil's Pixel. Skill `pixel-adb`
  (`~/.claude/skills/pixel-adb/`): before any adb step run
  `export ANDROID_SERIAL=$(~/.claude/skills/pixel-adb/connect.sh)` (mDNS, by serial,
  max. 3 attempts); on failure continue without the device and collect the tests.
- The iPad itself is not reachable from this PC: iPad changes are checked in the simulator
  CI (GitHub Actions) only.
