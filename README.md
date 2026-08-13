# mydevbox

A lightweight Docker container that runs both VS Code and Zen Browser
side by side inside an Openbox desktop, reachable over RDP. Combines
vscodeXrdp and zenXrdp into a single dev box so you can copy/paste
between the browser and the editor without switching RDP sessions.

## Quick start

1. Edit `RDP_PASSWORD` in `docker-compose.yml` (or override it at runtime).
2. Create the host directory used for persistence:
   ```bash
   mkdir -p /mydevbox/home
   ```
3. Start the container (pulls `ajb3932/mydevbox:latest` from Docker Hub):
   ```bash
   docker compose up -d
   ```
4. Connect with any RDP client to `<host>:3392`, username `rdpuser`,
   password whatever you set `RDP_PASSWORD` to.

If `RDP_PASSWORD` is not set, a random password is generated on each
start and printed once to `docker logs mydevbox` — set `RDP_PASSWORD`
explicitly if you want it to stay the same across restarts.

## Switching between VS Code and Zen

Both apps launch maximized on session start. Alt-Tab is unreliable
over RDP/Guacamole (many clients intercept it before it reaches the
remote session), so switching is done via the thin taskbar docked to
the bottom of the screen (tint2) — click an app's entry there to
bring it to the front.

## Port

The container listens on 3389 internally, but is published on host
port **3392** by default (`docker-compose.yml`'s `ports:
["3392:3389"]`) — adjust this if 3389 is free on your host and you'd
rather use it directly, but check first (`ss -tlnp | grep 3389` or
equivalent), since many hosts already run their own RDP service on
that port. 3392 was picked to sit alongside vscodeXrdp (3391) and
zenXrdp (3390) if you're running all three.

## Persistence

- `/mydevbox/home` → `/home/rdpuser` — everything under the user's
  home directory: VS Code settings (`~/.config/Code`) and extensions
  (`~/.vscode`), the full Zen profile (`~/.zen`) and downloads
  (`~/Downloads`), `~/.ssh`, and your project files (`~/workspace`,
  opened automatically in VS Code).

This survives `docker compose down` / `up` as long as the host
directory isn't removed.

## Additional packages

The image ships minimal by design. To install extra `apt` packages at
container startup (no rebuild needed), set `ADDITIONAL_PACKAGES` to a
comma-separated list:

```yaml
environment:
  - ADDITIONAL_PACKAGES=openssh-client,net-tools
```

Packages are installed once, at boot, before the RDP session starts.
If a package fails to install (typo, doesn't exist, no network), the
container will fail to start — check `docker logs` for details. On
restart, packages already present in the container's writable layer
are skipped, so subsequent starts don't re-hit the network.

Note: this only persists in the container's writable layer, not the
image — a `docker compose up -d --force-recreate` or image update will
require the packages to install again.

## Notes

- No audio redirection.
- No GPU acceleration.
- The RDP username (`rdpuser`) is fixed and not configurable — only
  the password is.
- The image is intentionally minimal and rdpuser has no sudo access.
- This is a separate image from `vscodeXrdp` and `zenXrdp` — those two
  are unaffected and still work standalone if you'd rather run the
  apps in isolation.

## Known limitations

- Automated verification covers container startup, password handling,
  the presence of the VS Code/Zen/tint2/wmctrl binaries, and that
  Openbox launches both apps maximized with a working taskbar (tested
  under Xvfb) — it does not drive an actual RDP session end to end. Do
  a manual RDP login to confirm the graphical session renders
  correctly, including through xrdp/xorgxrdp specifically, before
  relying on a freshly built image.
