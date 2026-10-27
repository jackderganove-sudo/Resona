#!/usr/bin/env python3
"""Writes/updates the AltStore-compatible app source (apps.json) that ESign
(and AltStore, Feather, SideStore …) can add as a source.

Usage: update_app_source.py <apps.json> <version> <build> <download-url>
                            <size-bytes> <changelog-file>

Keeps both the current `versions` array and the legacy top-level app fields
(version, versionDate, downloadURL, size, versionDescription), because some
sideloading apps only read one of the two layouts."""

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = "jackderganove-sudo/Resona"
SOURCE_URL = f"https://raw.githubusercontent.com/{REPO}/app-source/apps.json"
ICON_URL = f"https://raw.githubusercontent.com/{REPO}/main/Trop/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
BUNDLE_ID = "dev.jackderganove.resona"
MAX_VERSIONS = 15


def main() -> None:
    path, version, build, url, size, changelog_file = sys.argv[1:7]
    changelog = Path(changelog_file).read_text(encoding="utf-8").strip() or "Bug fixes and improvements."
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    source_path = Path(path)
    source = json.loads(source_path.read_text(encoding="utf-8")) if source_path.exists() else {}
    previous = []
    for app in source.get("apps", []):
        if app.get("bundleIdentifier") == BUNDLE_ID:
            previous = app.get("versions", [])

    entry = {
        "version": version,
        "buildVersion": build,
        "date": now,
        "localizedDescription": changelog,
        "downloadURL": url,
        "size": int(size),
        "minOSVersion": "18.0",
    }
    versions = [entry] + [v for v in previous if v.get("version") != version]

    app = {
        "name": "Resona",
        "bundleIdentifier": BUNDLE_ID,
        "developerName": "Resona",
        "subtitle": "YouTube Music client in Material 3 Expressive",
        "localizedDescription": "Resona is a YouTube Music client for iPhone and iPad with dynamic cover colours, "
                                "word-synced karaoke lyrics, downloads and a Material 3 Expressive design.",
        "iconURL": ICON_URL,
        "tintColor": "#99CCF9",
        "category": "entertainment",
        "screenshots": [],
        "versions": versions[:MAX_VERSIONS],
        # Legacy layout (read by older AltStore-style clients)
        "version": version,
        "versionDate": now,
        "versionDescription": changelog,
        "downloadURL": url,
        "size": int(size),
        "appPermissions": {"entitlements": [], "privacy": {}},
    }
    source = {
        "name": "Resona",
        "identifier": f"{BUNDLE_ID}.source",
        "subtitle": "Official Resona builds",
        "sourceURL": SOURCE_URL,
        "iconURL": ICON_URL,
        "website": f"https://github.com/{REPO}",
        "tintColor": "#99CCF9",
        "apps": [app],
        "news": [],
    }
    source_path.write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"apps.json -> {version} ({build}), {len(app['versions'])} versions")


if __name__ == "__main__":
    main()
