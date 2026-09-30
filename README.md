# Right Click Ninja

Everyday file fixes from a right-click. Date Shift and screenshots ship today; more tools on the way.

- **Site:** https://rightclick.ninja
- **Publisher:** Outlaw Apps / Johnny Outlaw LLC

## Desktop app (Windows)

```bat
installer\build.bat
```

Needs .NET Framework 4.x `csc.exe` and [Inno Setup 6](https://jrsoftware.org/isinfo.php). Put `exiftool.exe` + `exiftool_files\` in `bin\` before building (same layout ExifTool's Windows package ships).

Installer output: `installer\dist\RightClickNinja-Setup-*.exe`

## Desktop app (macOS)

Native menu-bar app (macOS 14+): **Change Date…** and **Take Screenshot** directly in Finder's right-click menu, plus Blue Shot-style region/full-screen capture with copy, save, and an annotation editor.

```bash
cd mac
./build.sh debug          # ad-hoc, this machine
./build.sh                # release → dist/RightClickNinja.app + .pkg (signed + notarized)
```

Headless checks:

```bash
swift build -c debug
BIN="$(swift build -c debug --show-bin-path)/RightClickNinja"
"$BIN" --selftest /tmp/rcn-selftest.png
"$BIN" --dateshift-selftest
```

Release builds sign with a Developer ID Application certificate, notarize (profile `blueshot-notary` by default), and write `web/public/downloads/RightClickNinja-Mac.pkg`. A `.pkg` installs to `/Applications` so Screen Recording permission can stick; a zip dragged out of Downloads is translocated and will not.

Shortcuts: Print Screen / F13, or ⌃⇧⌘4 (region) and ⌃⇧⌘3 (full screen). If BlueShot is also running, one of them will fail to claim F13 — quit the other app.

Finder: launch the app once after install and approve **Right Click Ninja Finder Menu** when macOS opens Extensions settings. Then select files → right-click → **Change Date…**, or right-click in a Finder window → **Take Screenshot**. The original Services action remains available as a fallback.

## Website

```bash
cd web
npm install
npm run dev
```

Vercel builds from the `web/` directory.
