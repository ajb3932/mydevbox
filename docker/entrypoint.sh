#!/bin/bash
set -euo pipefail

TZ="${TZ:-UTC}"
if [ -f "/usr/share/zoneinfo/${TZ}" ]; then
    ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime
    echo "${TZ}" > /etc/timezone
else
    echo "Unknown TZ '${TZ}'; falling back to UTC" >&2
    TZ="UTC"
    ln -sf /usr/share/zoneinfo/UTC /etc/localtime
    echo "UTC" > /etc/timezone
fi

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
