# NeonSwitch

Cyberpunk, circular, neon replacement for the macOS ⌘Tab app switcher.

![NeonSwitch](docs/img/theme-magenta.jpg)

**[Download the latest DMG](https://github.com/mahmoud-eslami/neonswitch/releases/latest/download/NeonSwitch.dmg)** · [Website](https://mahmoud-eslami.github.io/neonswitch/)

The app isn't signed with an Apple Developer ID. On first launch, allow it in
System Settings → Privacy & Security → **Open Anyway**, or run
`xattr -dr com.apple.quarantine /Applications/NeonSwitch.app`.

## Build & run

```sh
./build.sh          # → build/NeonSwitch.app and build/NeonSwitch.dmg
open build/NeonSwitch.dmg   # drag NeonSwitch into Applications
open /Applications/NeonSwitch.app
```

On first launch, grant **Accessibility** access (System Settings → Privacy & Security → Accessibility).
NeonSwitch starts working as soon as access is granted.

## Keys

| Key | Action |
| --- | --- |
| ⌘Tab / ⌘⇧Tab | Cycle forward / back (release ⌘ to switch) |
| Arrows | Move selection |
| Return | Switch now |
| Esc | Cancel |
| Q / H | Quit / hide the selected app |
| Mouse | Point at an icon's slice of the ring to select, click to switch |
| Click center / outside | Switch to selection / cancel |
| Scroll wheel | Rotate selection |

## Notes

- The native switcher is disabled while NeonSwitch runs and restored when it quits.
  If it is force-killed, relaunch and quit it (or log out) to restore the native ⌘Tab.
- Builds are ad-hoc signed. After rebuilding, remove and re-add the app in Accessibility settings.
- Menu bar icon → *Launch at Login* / *Quit*.
