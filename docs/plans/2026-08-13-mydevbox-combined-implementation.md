# mydevbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `mydevbox` Docker image — a single container combining vscodeXrdp and zenXrdp, launching both VS Code and Zen Browser maximized in one Openbox/xrdp session, switchable via a minimal tint2 taskbar instead of Alt-Tab.

**Architecture:** `debian:bookworm-slim` base, `xrdp`+`xorgxrdp` for the RDP stack, unmodified default Openbox `rc.xml`, `tint2` as a taskbar-only bottom panel, `wmctrl` used by the autostart script to maximize whatever windows exist after launch (app-agnostic, no window-class guessing). Fixed non-root `rdpuser`, single home-directory bind mount for all persistence.

**Tech Stack:** Docker, bash/sh, Debian apt packages (xrdp, xorgxrdp, openbox, tint2, wmctrl, VS Code via MS apt repo, Zen Browser via release tarball).

## Global Constraints

- Base image: `debian:bookworm-slim` (from spec)
- Fixed username `rdpuser`, not configurable — only `RDP_PASSWORD` is (from spec)
- No custom Openbox `rc.xml` — default keybindings/behavior only (from spec)
- tint2 panel: `panel_items = T` only — no clock, systray, or launcher icons (from spec)
- Single volume: `/mydevbox/home` → `/home/rdpuser` — no other bind mounts (from spec)
- Host port `3392` → container port `3389`; image tag `ajb3932/mydevbox:latest` (from spec)
- Workspace path is `/home/rdpuser/workspace` (under the home volume), not `/workspace` (from spec)
- Out of scope: audio redirection, GPU acceleration, configurable username, multi-user support, persisting the TLS cert, publishing to Docker Hub, any changes to `vscodeXrdp`/`zenXrdp` (from spec)
- All work happens in `/lab/projects/mydevbox` (already `git init`-ed, empty history)

---

### Task 1: Openbox session glue — startwm.sh, tint2rc, openbox-autostart

**Files:**
- Create: `/lab/projects/mydevbox/docker/startwm.sh`
- Create: `/lab/projects/mydevbox/docker/tint2rc`
- Create: `/lab/projects/mydevbox/docker/openbox-autostart`

**Interfaces:**
- Produces: three files at exact paths above, later `COPY`-ed by the Dockerfile (Task 3) to `/etc/xrdp/startwm.sh`, `/etc/xdg/tint2/tint2rc`, `/etc/xdg/openbox/autostart` respectively. `openbox-autostart` assumes `tint2`, `zen`, `code`, and `wmctrl` are all on `PATH` and that VS Code should open `/home/rdpuser/workspace` (matches Task 2's entrypoint, which creates that directory).

- [ ] **Step 1: Write `docker/startwm.sh`**

```sh
#!/bin/sh
exec dbus-launch --exit-with-session openbox-session
```

- [ ] **Step 2: Write `docker/tint2rc`**

```
#-------------------------------------
# mydevbox tint2 config: thin bottom taskbar, task list only.
# No clock, no systray, no launcher icons.
#-------------------------------------

[background]
rounded = 0
border_width = 0
background_color = #1a1a2e 100
border_color = #000000 0

[background]
rounded = 0
border_width = 1
background_color = #3a3a5e 100
border_color = #55557f 100

#-------------------------------------
# Panel
#-------------------------------------
panel_items = T
panel_size = 100% 28
panel_margin = 0 0
panel_padding = 0 0 0
panel_position = bottom center horizontal
panel_layer = top
panel_monitor = all
panel_background_id = 1
autohide = 0
strut_policy = follow_window

#-------------------------------------
# Taskbar
#-------------------------------------
taskbar_mode = single_desktop
taskbar_padding = 0 0 0
taskbar_background_id = 1
taskbar_active_background_id = 1
taskbar_name = 0

#-------------------------------------
# Task buttons
#-------------------------------------
task_text = 1
task_icon = 1
task_centered = 1
task_maximum_size = 200 28
task_padding = 6 2
task_background_id = 1
task_active_background_id = 2
task_font = sans 9
task_font_color = #eeeeee 100
task_active_font_color = #ffffff 100
task_tooltip = 0

#-------------------------------------
# Misc
#-------------------------------------
mouse_left = toggle_iconify
mouse_middle = none
mouse_right = close
mouse_scroll_up = none
mouse_scroll_down = none
```

- [ ] **Step 3: Write `docker/openbox-autostart`**

```sh
#!/bin/sh
tint2 &

zen &
code --no-sandbox /home/rdpuser/workspace &

(
    i=0
    while [ "$i" -lt 20 ]; do
        count=$(wmctrl -l 2>/dev/null | wc -l)
        [ "$count" -ge 2 ] && break
        sleep 0.5
        i=$((i + 1))
    done
    for id in $(wmctrl -l | awk '{print $1}'); do
        wmctrl -i -r "$id" -b add,maximized_vert,maximized_horz
    done
) &
```

- [ ] **Step 4: Syntax-check the two shell scripts**

Run: `sh -n /lab/projects/mydevbox/docker/startwm.sh && sh -n /lab/projects/mydevbox/docker/openbox-autostart && echo SYNTAX_OK`
Expected: `SYNTAX_OK` printed, no errors.

- [ ] **Step 5: Validate tint2rc actually parses (functional check, not just eyeballing)**

Run this disposable-container test — it installs tint2 fresh, starts a virtual display, loads the config, and confirms tint2 is still alive after startup instead of having exited on a parse error:

```bash
docker run --rm -v /lab/projects/mydevbox/docker/tint2rc:/tint2rc:ro debian:bookworm-slim bash -c "
  set -e
  apt-get update >/dev/null
  apt-get install -y --no-install-recommends tint2 xvfb >/dev/null 2>&1
  Xvfb :99 -screen 0 1280x800x24 >/tmp/xvfb.log 2>&1 &
  sleep 1
  DISPLAY=:99 tint2 -c /tint2rc >/tmp/tint2.log 2>&1 &
  TINT2_PID=\$!
  sleep 2
  if kill -0 \$TINT2_PID 2>/dev/null; then
    echo TINT2_ALIVE
  else
    echo TINT2_DIED
    cat /tmp/tint2.log
    exit 1
  fi
"
```

Expected: `TINT2_ALIVE`. If it prints `TINT2_DIED`, the logged tint2 output will name the offending config line — fix that line in `docker/tint2rc` and re-run this step.

- [ ] **Step 6: Commit**

```bash
cd /lab/projects/mydevbox
git add docker/startwm.sh docker/tint2rc docker/openbox-autostart
git commit -m "Add Openbox session glue: startwm, tint2 taskbar config, autostart"
```

---

### Task 2: entrypoint.sh

**Files:**
- Create: `/lab/projects/mydevbox/docker/entrypoint.sh`

**Interfaces:**
- Consumes: env vars `RDP_PASSWORD` (optional), `ADDITIONAL_PACKAGES` (optional, comma-separated apt package list)
- Produces: `/home/rdpuser/workspace` directory, owned `rdpuser:rdpuser`, before the RDP session can start — Task 1's `openbox-autostart` opens this exact path in VS Code. Also produces the running `dbus`/`xrdp-sesman`/`xrdp` daemons that Task 5's smoke test connects to on port 3389.

- [ ] **Step 1: Write `docker/entrypoint.sh`**

```bash
#!/bin/bash
set -euo pipefail

if [ -z "${RDP_PASSWORD:-}" ]; then
    RDP_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16 || true)"
    [ "${#RDP_PASSWORD}" -eq 16 ] || { echo "failed to generate password" >&2; exit 1; }
    echo "RDP_PASSWORD not set; generated random password for rdpuser: ${RDP_PASSWORD}"
fi
echo "rdpuser:${RDP_PASSWORD}" | chpasswd

if [ -n "${ADDITIONAL_PACKAGES:-}" ]; then
    IFS=',' read -ra _requested_packages <<< "$ADDITIONAL_PACKAGES"
    _missing_packages=()
    for pkg in "${_requested_packages[@]}"; do
        pkg="$(echo "$pkg" | xargs)"
        [ -z "$pkg" ] && continue
        dpkg -s "$pkg" >/dev/null 2>&1 || _missing_packages+=("$pkg")
    done
    if [ "${#_missing_packages[@]}" -gt 0 ]; then
        echo "Installing additional packages: ${_missing_packages[*]}"
        apt-get update
        apt-get install -y --no-install-recommends "${_missing_packages[@]}"
        rm -rf /var/lib/apt/lists/*
    fi
fi

mkdir -p /home/rdpuser/workspace
chown -R rdpuser:rdpuser /home/rdpuser

rm -rf /run/dbus /run/xrdp
mkdir -p /run/dbus /run/xrdp /run/xrdp/sockdir
chown root:xrdp /run/xrdp /run/xrdp/sockdir
chmod 2775 /run/xrdp
chmod 3777 /run/xrdp/sockdir

dbus-daemon --system --fork

/usr/sbin/xrdp-sesman --nodaemon &

exec /usr/sbin/xrdp --nodaemon
```

- [ ] **Step 2: Syntax-check it**

Run: `bash -n /lab/projects/mydevbox/docker/entrypoint.sh && echo SYNTAX_OK`
Expected: `SYNTAX_OK`, no errors.

(Full behavioral testing — password generation, `ADDITIONAL_PACKAGES`, ownership of the mounted home volume, daemons actually starting — needs the full image and happens in Task 5, not here, so this logic isn't duplicated in a second harness.)

- [ ] **Step 3: Commit**

```bash
cd /lab/projects/mydevbox
git add docker/entrypoint.sh
git commit -m "Add entrypoint: password handling, additional packages, daemon startup"
```

---

### Task 3: Dockerfile and .dockerignore

**Files:**
- Create: `/lab/projects/mydevbox/Dockerfile`
- Create: `/lab/projects/mydevbox/.dockerignore`

**Interfaces:**
- Consumes: `docker/startwm.sh`, `docker/tint2rc`, `docker/openbox-autostart` (Task 1), `docker/entrypoint.sh` (Task 2) — all `COPY`-ed by exact relative path.
- Produces: image tag `mydevbox:test` (local build tag for this plan's testing; the real `ajb3932/mydevbox:latest` tag is applied by the user when they publish, per spec's out-of-scope note) containing binaries `code`, `zen`, `tint2`, `wmctrl`, `xrdp`, `xrdp-sesman`, `openbox`, `dbus-daemon` — Task 5 depends on all of these being present and on `PATH` (or at their standard `/usr/sbin` locations).

- [ ] **Step 1: Write `.dockerignore`**

```
.git
docs
README.md
```

- [ ] **Step 2: Write `Dockerfile`**

```dockerfile
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        xrdp \
        xorgxrdp \
        openbox \
        tint2 \
        wmctrl \
        dbus \
        dbus-x11 \
        ca-certificates \
        curl \
        gnupg \
        git \
        xz-utils \
        fonts-liberation2 \
        libgtk-3-0 \
        libx11-xcb1 \
        libxcomposite1 \
        libxcursor1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxi6 \
        libxrandr2 \
        libxrender1 \
        libasound2 \
        libdbus-1-3 \
        libxcb-shm0 \
        ffmpeg \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash rdpuser

RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends code \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/zen.tar.xz \
        https://github.com/zen-browser/desktop/releases/latest/download/zen.linux-x86_64.tar.xz \
    && mkdir -p /opt/zen \
    && tar -xJf /tmp/zen.tar.xz -C /opt/zen --strip-components=1 \
    && rm /tmp/zen.tar.xz \
    && ln -s /opt/zen/zen /usr/local/bin/zen

ENV LD_LIBRARY_PATH=/opt/zen
RUN echo "LD_LIBRARY_PATH=/opt/zen" >> /etc/environment

COPY docker/startwm.sh /etc/xrdp/startwm.sh
COPY docker/openbox-autostart /etc/xdg/openbox/autostart
COPY docker/tint2rc /etc/xdg/tint2/tint2rc
RUN chmod +x /etc/xrdp/startwm.sh /etc/xdg/openbox/autostart

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3389

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

- [ ] **Step 3: Build the image**

Run: `cd /lab/projects/mydevbox && docker build -t mydevbox:test .`
Expected: build completes with `Successfully tagged mydevbox:test` (or BuildKit's equivalent final `naming to docker.io/library/mydevbox:test done`). No errors. This step also downloads the real Zen tarball and VS Code package, so it needs network access — if it fails on the `curl`/`apt-get install code` steps, confirm network egress to `packages.microsoft.com` and `github.com` is available before debugging further.

- [ ] **Step 4: Verify all required binaries are present**

Run:
```bash
docker run --rm mydevbox:test bash -c "which code zen tint2 wmctrl openbox dbus-daemon && ls /usr/sbin/xrdp /usr/sbin/xrdp-sesman"
```
Expected: a path printed for each of `code`, `zen`, `tint2`, `wmctrl`, `openbox`, `dbus-daemon`, and both `/usr/sbin/xrdp` and `/usr/sbin/xrdp-sesman` listed — no "not found" errors.

- [ ] **Step 5: Commit**

```bash
cd /lab/projects/mydevbox
git add Dockerfile .dockerignore
git commit -m "Add Dockerfile combining vscodeXrdp and zenXrdp base images"
```

---

### Task 4: docker-compose.yml

**Files:**
- Create: `/lab/projects/mydevbox/docker-compose.yml`

**Interfaces:**
- Consumes: image tag `ajb3932/mydevbox:latest` (published name, per spec — doesn't need to exist locally for `docker compose config` to validate syntax)
- Produces: the compose service definition referenced by Task 6's README quick-start instructions.

- [ ] **Step 1: Write `docker-compose.yml`**

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

- [ ] **Step 2: Validate syntax**

Run: `cd /lab/projects/mydevbox && docker compose config`
Expected: prints the fully-resolved compose config (service `mydevbox`, port mapping `3392:3389`, the one volume, `RDP_PASSWORD=changeme`) with no parse errors. It doesn't need to pull the image to validate.

- [ ] **Step 3: Commit**

```bash
cd /lab/projects/mydevbox
git add docker-compose.yml
git commit -m "Add docker-compose.yml for mydevbox"
```

---

### Task 5: Full container smoke test

**Files:**
- None created — this task verifies Tasks 1–4's output together as a running container. No commit at the end (nothing changes on disk).

**Interfaces:**
- Consumes: `mydevbox:test` image built in Task 3.

- [ ] **Step 1: Explicit `RDP_PASSWORD` is honored and xrdp listens on 3389**

```bash
docker rm -f mydevbox-smoketest 2>/dev/null || true
docker run -d --name mydevbox-smoketest -e RDP_PASSWORD=testpass123 -p 13392:3389 mydevbox:test
sleep 3
docker logs mydevbox-smoketest
docker exec mydevbox-smoketest bash -c "ss -tlnp | grep 3389"
```
Expected: logs show no "generated random password" line (since one was supplied), and the `ss` output shows a listener on `:3389`.

- [ ] **Step 2: Missing `RDP_PASSWORD` falls back to a generated, logged password**

```bash
docker rm -f mydevbox-smoketest2 2>/dev/null || true
docker run -d --name mydevbox-smoketest2 mydevbox:test
sleep 3
docker logs mydevbox-smoketest2 | grep "generated random password for rdpuser"
```
Expected: one matching line found.

- [ ] **Step 3: `ADDITIONAL_PACKAGES` installs at boot**

```bash
docker rm -f mydevbox-smoketest3 2>/dev/null || true
docker run -d --name mydevbox-smoketest3 -e ADDITIONAL_PACKAGES=tree mydevbox:test
sleep 8
docker exec mydevbox-smoketest3 which tree
```
Expected: a path to the `tree` binary is printed.

- [ ] **Step 4: Home volume is chowned to rdpuser, workspace dir is created**

```bash
mkdir -p /tmp/mydevbox-test-home
docker rm -f mydevbox-smoketest4 2>/dev/null || true
docker run -d --name mydevbox-smoketest4 -v /tmp/mydevbox-test-home:/home/rdpuser mydevbox:test
sleep 3
docker exec mydevbox-smoketest4 stat -c '%U:%G' /home/rdpuser/workspace
```
Expected: `rdpuser:rdpuser`.

- [ ] **Step 5: Openbox launches tint2 + both apps, and both windows end up maximized**

This is the core new behavior (the app switcher) — verified under Xvfb, which exercises the real Openbox/tint2/autostart/wmctrl chain without needing an actual RDP client:

```bash
docker exec mydevbox-smoketest4 bash -c "apt-get update && apt-get install -y --no-install-recommends xvfb x11-utils >/dev/null 2>&1"
docker exec -u rdpuser mydevbox-smoketest4 bash -c "
  Xvfb :99 -screen 0 1280x800x24 >/tmp/xvfb.log 2>&1 &
  sleep 1
  DISPLAY=:99 /etc/xrdp/startwm.sh >/tmp/session.log 2>&1 &
  sleep 12
  echo '--- windows ---'
  DISPLAY=:99 wmctrl -l -G
  echo '--- processes ---'
  pgrep -x tint2 && echo tint2_running
  pgrep -f code && echo code_running
  pgrep -f zen && echo zen_running
"
```
Expected: `tint2_running`, `code_running`, and `zen_running` all printed, and `wmctrl -l -G` lists at least 2 windows whose width/height are close to the 1280x800 screen (height slightly less to account for the 28px tint2 panel) — i.e. both apps came up maximized, not at some small default size.

- [ ] **Step 6: Clean up**

```bash
docker rm -f mydevbox-smoketest mydevbox-smoketest2 mydevbox-smoketest3 mydevbox-smoketest4 2>/dev/null || true
rm -rf /tmp/mydevbox-test-home
```

---

### Task 6: README.md

**Files:**
- Create: `/lab/projects/mydevbox/README.md`

**Interfaces:**
- None — terminal task, documents the outputs of Tasks 1–4.

- [ ] **Step 1: Write `README.md`**

```markdown
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
```

- [ ] **Step 2: Sanity-check key facts are present**

Run: `grep -q "3392" README.md && grep -q "ajb3932/mydevbox" README.md && grep -q "/mydevbox/home" README.md && echo README_OK`
Expected: `README_OK`.

- [ ] **Step 3: Commit**

```bash
cd /lab/projects/mydevbox
git add README.md
git commit -m "Add README for mydevbox"
```

---

## Self-Review Notes

- **Spec coverage:** Dockerfile/packages (Task 3), entrypoint/persistence/ADDITIONAL_PACKAGES (Task 2), autostart/tint2/wmctrl maximize behavior (Task 1), docker-compose (Task 4), README (Task 6), and the spec's testing plan items (password explicit/random, ADDITIONAL_PACKAGES, home persistence, xrdp listening, app launch+maximize+taskbar) are all covered by Task 5. Every spec section maps to a task.
- **Placeholders:** none — all file contents are complete, no TBD/TODO.
- **Type/name consistency:** workspace path `/home/rdpuser/workspace` is consistent across Task 1 (`openbox-autostart`), Task 2 (`entrypoint.sh` creates it), and Task 6 (README). Volume path `/mydevbox/home` and image tag `ajb3932/mydevbox:latest` consistent across Task 4 and Task 6. Port `3392` consistent across Task 4 and Task 6.
