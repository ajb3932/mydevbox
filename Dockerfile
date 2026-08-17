FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        xrdp \
        xorgxrdp \
        openbox \
        tint2 \
        wmctrl \
        x11-utils \
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
        #Optional Packages
        flameshot \
        gh \
        7zip \
        alacritty \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/7zz /usr/local/bin/7z

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
    && ln -s /opt/zen/zen /usr/local/bin/zen \
    && update-alternatives --install /usr/bin/x-www-browser x-www-browser /opt/zen/zen 100

ENV LD_LIBRARY_PATH=/opt/zen
RUN echo "LD_LIBRARY_PATH=/opt/zen" >> /etc/environment

COPY docker/startwm.sh /etc/xrdp/startwm.sh
COPY docker/openbox-autostart /etc/xdg/openbox/autostart
COPY docker/tint2rc /etc/xdg/tint2/tint2rc
COPY docker/zen.desktop /usr/share/applications/zen.desktop
COPY docker/menu.xml /etc/xdg/openbox/menu.xml
COPY docker/rc.xml /etc/xdg/openbox/rc.xml
RUN chmod +x /etc/xrdp/startwm.sh /etc/xdg/openbox/autostart

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3389

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
