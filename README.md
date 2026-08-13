# Right Click Ninja

Everyday file fixes from Explorer's right-click menu. Date Shift ships first; more tools on the way.

- **Site:** https://rightclick.ninja
- **Publisher:** Outlaw Apps / Johnny Outlaw LLC

## Desktop app (Windows)

```bat
installer\build.bat
```

Needs .NET Framework 4.x `csc.exe` and [Inno Setup 6](https://jrsoftware.org/isinfo.php). Put `exiftool.exe` + `exiftool_files\` in `bin\` before building (same layout ExifTool's Windows package ships).

Installer output: `installer\dist\RightClickNinja-Setup-*.exe`

## Website

```bat
cd web
npm install
npm run dev
```

Vercel builds from the `web/` directory.
