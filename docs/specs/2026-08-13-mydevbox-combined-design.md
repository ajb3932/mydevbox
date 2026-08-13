# mydevbox: combined VS Code + Zen dev box — Design

Date: 2026-08-13

## Goal

A single Docker container, `mydevbox`, that boots into a remote Linux
desktop (Openbox) reachable via RDP, auto-launching both VS Code and
Zen Browser so the two apps can be used side by side (copy/paste
between IDE and browser) without running two separate containers.
Combines the `vscodeXrdp` and `zenXrdp` images, which are otherwise
near-identical in architecture.

## Why not just run two containers side by side

That's what `vscodeXrdp` and `zenXrdp` already do. The pain point is
that copying between the browser and the editor means switching RDP
sessions entirely. `mydevbox` puts both apps in one X session so
clipboard sharing between them works like a normal desktop.

## Architecture

- **Base image**: `debian:bookworm-slim`
- **Window manager**: Openbox (unmodified default `rc.xml` — no
  custom keybindings needed)
- **RDP stack**: `xrdp` + `xorgxrdp`, same as both source images
- **Panel/app switcher**: `tint2`, configured as a thin bottom bar
  showing only the taskbar (`panel_items = T`) — no clock, systray,
  or launcher icons. This replaces Alt-Tab as the switching mechanism
  because Alt-Tab is frequently intercepted by RDP clients / Guacamole
  before it reaches the remote session; a clickable taskbar entry
  works regardless of client.
- **Apps**: VS Code (installed from Microsoft's apt repo, as in
  vscodeXrdp) and Zen Browser (installed from the official release
  tarball to `/opt/zen`, as in zenXrdp). Both auto-launch via Openbox's
  `autostart` script.
- **Window layout**: both windows launch maximized. Openbox has no
  built-in "start maximized" without per-application `rc.xml` rules
  keyed on window class, which is fragile to guess/version-drift.
  Instead, `wmctrl` (new dependency, small) is used post-launch to
  maximize whatever top-level windows exist — app-agnostic, doesn't
  depend on matching a specific window title or class.
- **User**: fixed non-root `rdpuser`, same as both source images.
  Username not configurable, only `RDP_PASSWORD`.

## Build (Dockerfile)

Union of both source Dockerfiles' apt packages, plus `tint2` and
`wmctrl`:

- Base set: `xrdp xorgxrdp openbox dbus dbus-x11 ca-certificates curl gnupg git`
- Zen's runtime libs: `xz-utils fonts-liberation2 libgtk-3-0 libx11-xcb1 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libasound2 libdbus-1-3 libxcb-shm0 ffmpeg`
- New: `tint2 wmctrl`
- Create `rdpuser` (`useradd -m -s /bin/bash rdpuser`)
- Install VS Code from Microsoft's apt repo (same steps as vscodeXrdp)
- Download/extract Zen tarball to `/opt/zen`, symlink `zen` to
  `/usr/local/bin/zen` (same as zenXrdp), set `LD_LIBRARY_PATH`
- Copy in `docker/startwm.sh`, `docker/openbox-autostart`,
  `docker/tint2rc`, `docker/entrypoint.sh` to their standard
  locations, matching both source images' file layout
- `EXPOSE 3389`, `ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]`

## Runtime (autostart)

`docker/openbox-autostart`:

1. Start `tint2` first, so its `_NET_WM_STRUT` reserves panel space
   before any window maximizes.
2. Launch `zen &` and `code --no-sandbox /home/rdpuser/workspace &`.
3. Poll `wmctrl -l` (up to ~10s, checking window count, not a blind
   sleep) until both windows exist, then maximize every top-level
   window found via `wmctrl -i -r <id> -b add,maximized_vert,maximized_horz`.

## Runtime (entrypoint)

Same shape as both source entrypoints, simplified since there's now
one volume instead of several:

1. Set `rdpuser`'s password from `RDP_PASSWORD`, or generate+log a
   random one if unset (unchanged from both originals).
2. `ADDITIONAL_PACKAGES` support carried over from vscodeXrdp's
   entrypoint (comma-separated apt packages installed once at boot,
   skipped on subsequent starts if already present).
3. `mkdir -p /home/rdpuser/workspace`, then
   `chown -R rdpuser:rdpuser /home/rdpuser` — one recursive chown
   covers VS Code config/extensions, the Zen profile, Downloads,
   `.ssh`, and the workspace dir, since they're all under the single
   home-directory volume mount.
4. Start `dbus`, `xrdp-sesman`, then `xrdp` in the foreground (`exec`,
   PID 1), unchanged from both originals.

## Persistence

One bind mount, covering everything under the home directory:

- `/home/rdpuser` — VS Code settings (`.config/Code`) and extensions
  (`.vscode`), the full Zen profile (`.zen`) and `Downloads`, `.ssh`,
  and `workspace` (project files, opened automatically in VS Code).

This replaces the 4–5 separate bind mounts the two source
`docker-compose.yml` files used.

## docker-compose.yml

```yaml
services:
  mydevbox:
    image: ajb3932/mydevbox:latest
    ports:
      - "3392:3389"
    environment:
      - RDP_PASSWORD=changeme
      # - ADDITIONAL_PACKAGES=openssh-client,net-tools
    volumes:
      - /mydevbox/home:/home/rdpuser
    restart: unless-stopped
```

## README

Rewritten to match the other two projects' README structure (quick
start, port note, persistence, additional packages, notes), covering
both apps and the panel-based switching.

## Testing plan

- `docker build` succeeds
- Container starts; `docker logs` shows xrdp listening on 3389
- Connect with an RDP client; confirm Openbox session comes up, both
  VS Code and Zen launch automatically, both start maximized, and the
  tint2 taskbar at the bottom shows both as clickable entries
- Click between taskbar entries; confirm focus switches and clipboard
  copy/paste works between the two apps
- Restart the container; confirm VS Code settings/extensions, Zen
  profile/downloads, and workspace files all persist via the single
  home volume
- Confirm login fails with the wrong password and succeeds with the
  one set via `RDP_PASSWORD`
- Confirm `ADDITIONAL_PACKAGES` installs on first boot and is skipped
  on a plain restart

## Explicitly out of scope

- Audio redirection
- GPU/hardware acceleration
- Configurable RDP username
- Multi-user support
- Persisting the xrdp TLS certificate across recreations
- Publishing `ajb3932/mydevbox` to Docker Hub (build/push handled by
  the user separately)
- Changes to `vscodeXrdp` or `zenXrdp` — both remain standalone,
  unmodified
