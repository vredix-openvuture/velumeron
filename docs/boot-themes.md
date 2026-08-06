# Boot themes — Plymouth, GRUB, SDDM

The shell, GTK and Qt all follow the wallust palette. Everything *before* quickshell
starts does not: the GRUB menu, the Plymouth splash and the login greeter are the
three surfaces the machine shows while Velumeron does not exist yet.

This is the management surface for those three — **Settings → Boot & Login**, backed
by `assets/scripts/boot-theme.py`.

## What it does

It manages whatever is installed. Each of the three components gets a card listing
every theme present on the system, which one is selected right now, a preview, and an
Apply button. Velumeron's own theme is **one entry in those lists** — offered, never forced, and
removable by picking something else.

A component that is not installed says so and stays inert. Nothing here installs
packages, enables a display manager, or takes over a boot chain that already works.

## The command

```
boot-theme.py status                   what is installed / active / selected  (JSON)
boot-theme.py preview <comp> <theme>   path to a preview image, or nothing
boot-theme.py generate [comp…]         (re)build the `velumeron` themes
boot-theme.py apply <comp> <theme>     switch the component to <theme>   ← needs root
boot-theme.py doctor                   plain-text sanity report
```

`<comp>` is `plymouth`, `grub` or `sddm`. `doctor` is the quickest way to see what the
GUI sees.

## Root

Only `apply` needs it, and it refuses to run without it. Everything else — listing,
previewing, generating — is unprivileged: generation writes to
`$VELUMERON_USER_DIR/boot/`, the listings read world-readable directories only.

Apply goes through a **visible terminal**, not a silent `pkexec`: the GUI runs
`term-run.sh → boot-theme-run.sh`, which prints which files are about to be written,
warns that the initramfs rebuild is the slow step, and shows a framed `sudo` prompt in
the current palette. Same mechanism as the bar's Updates module. No polkit policy file
ships, and no passwordless sudo rule is created.

`boot-theme.py` derives its own paths, so it needs no environment: `VELUMERON_DIR`
comes from its resolved location and the user dirs are re-anchored from `$SUDO_USER`.
(That is deliberate — `sudo -E` *fails outright* under the default `env_reset`
sudoers, rather than merely failing to preserve the environment.)

## What each apply actually costs

| Component | Written | Rebuild | Visible |
|---|---|---|---|
| Plymouth | `/etc/plymouth/plymouthd.conf` | `mkinitcpio -P` (~10–60 s) | next boot |
| GRUB | `GRUB_THEME` in `/etc/default/grub` | `grub-mkconfig` (a few seconds) | next boot |
| SDDM | `/etc/sddm.conf.d/zz-velumeron.conf` | — | next login screen |

The `zz-` prefix is not cosmetic: sddm applies `/etc/sddm.conf.d/*.conf`
alphabetically and the **last** one wins, so a drop-in named `10-velumeron.conf` would
be silently overridden by a distro's `kde_settings.conf`.

## The generated themes

Sources live in `boot/<component>/velumeron/` as real, editable files. Anything ending
`.in` is a template: `generate` replaces the known `@tokens@` with the brand colours and
drops the suffix; everything else is copied verbatim, and the artwork
(`background.png`, the GRUB 9-slices, previews) is rendered with Pillow.

Colours come from `BRAND` in `boot-theme.py` — **fixed Velumeron purple, not the
wallust palette**. `@accent@` (#482898) is sampled from the logo itself, so artwork and
colour cannot drift apart. Plymouth additionally gets `@bg_r@`-style 0..1 floats,
because its script language speaks nothing else.

The gradient is **dithered** (triangular PDF, ±1 LSB). A 1080-row ramp between two dark,
close colours only passes through ~40 distinct 8-bit values and renders as visible
bands; no amount of tweaking the endpoints fixes that, only dithering does.

Edit a template, run `boot-theme.py generate <comp>` (or press **Rebuild from
palette** in the settings card), then Apply.

### Why the boot chain does not follow the wallpaper

Two reasons, and the second is the hard one. The Plymouth theme lives *inside the
initramfs* and GRUB reads its theme from disk before any filesystem is up, so neither
can react to a palette change without a privileged rebuild. And the three surfaces
have to look like *each other* — a boot chain that shifts hue with the wallpaper stops
reading as one thing. So they carry the mark instead, and the palette keeps the shell.

### Previewing without a reboot

- **GRUB** — real, and worth doing before every change: `grub-mkrescue` a throwaway ISO
  carrying the theme and boot it in qemu. Needs no root. This is what caught the
  highlight overrunning its row and the progress bar ignoring its height; a
  hand-drawn mock of `theme.txt` showed neither, because it drew what the file *says*
  rather than what GRUB *does*.
- **SDDM** — `sddm-greeter-qt6 --test-mode --theme <dir>` opens the greeter in a window.
- **Plymouth** — the x11 renderer (`/usr/lib/plymouth/renderers/x11.so`) lets `plymouthd`
  draw into a window instead of a VT, but it needs root.

## Fonts

Both GRUB and SDDM use **Fredoka** (`assets/fonts/Fredoka-500.ttf`), by two different
routes, because neither can just name a system font:

- **GRUB** cannot read a TTF and cannot scale a bitmap font, so `boot-theme.py`
  converts it with `grub-mkfont` into one `.pf2` per size and drops them beside
  `theme.txt`. `grub-mkconfig`'s `00_header` loads every `*.pf2` it finds in a theme
  dir, so the real boot needs no wiring — but a hand-written `grub.cfg` (the qemu
  preview) must `loadfont` them itself. The names in `theme.txt` are exactly what
  `grub-mkfont` writes ("Fredoka Regular 20"); naming a font that was not loaded
  drops the **whole theme** back to the plain text menu, silently.
- **SDDM** gets the TTF copied into the theme dir and loaded by a QML `FontLoader`.
  The greeter runs as the `sddm` user before any session, so relying on fontconfig
  to find it there is a bet.

## Avatars

`apply sddm` copies the invoking user's `~/.face` to
`/usr/share/sddm/faces/<user>.face.icon`. Without that the avatar never appears: the
greeter runs as `sddm`, and a home directory is typically `700`/`710`, so it cannot
traverse into it to read the file at all.

## Known edges

- **`/boot` is `700 root:root`** on most installs, so GRUB themes stored under
  `/boot/grub/themes` cannot be listed by the GUI. Only `/usr/share/grub/themes` is
  shown, and the card says so. Velumeron installs its own theme to the readable
  location; GRUB resolves it as long as `/boot` is on the root filesystem.
- **Plymouth needs its mkinitcpio hook.** If `plymouth` is missing from `HOOKS`, the
  card warns — a theme applies fine but nothing will ever show it.
- **SDDM only counts if it runs the greeter.** The card reports the display manager
  systemd actually starts; with lightdm or gdm in charge, an applied SDDM theme waits.
- The generated Plymouth theme includes a **password prompt**. A splash without one
  swallows every keystroke on an encrypted root, which looks exactly like a hang.
