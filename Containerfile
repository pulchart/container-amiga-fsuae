# Images that run Amiga software headless in FS-UAE.
#   base: amiga-fsuae, FS-UAE, Xvfb, amitools and disk tools on Fedora
#   aros: amiga-fsuae-aros, base and an AROS m68k nightly in /opt/aros
#   test: boots AROS from aros and checks that it ran its Startup-Sequence
# FS-UAE and amitools follow their newest releases for that Fedora, Renovate
# moves FEDORA_VERSION and AROS_DATE.

# renovate: datasource=endoflife-date depName=fedora
ARG FEDORA_VERSION=45
# renovate: datasource=custom.aros-nightly depName=aros-nightly
ARG AROS_DATE=20261118

FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION} AS base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3013,DL3041
RUN dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    && dnf install -y \
        fs-uae \
        xorg-x11-server-Xvfb xauth \
        python3 python3-pip python3-pyyaml \
        mtools dosfstools exfatprogs lhasa \
        procps-ng findutils \
    && pip install --no-cache-dir --root-user-action=ignore amitools \
    && dnf clean all \
    && rm -rf /root/.cache

ENV SDL_VIDEODRIVER=x11 \
    SDL_AUDIODRIVER=dummy

LABEL org.opencontainers.image.title="amiga-fsuae" \
      org.opencontainers.image.description="FS-UAE, Xvfb, amitools and disk tools for headless Amiga tests" \
      org.opencontainers.image.source="https://github.com/pulchart/container-amiga-fsuae" \
      org.opencontainers.image.url="https://github.com/pulchart/container-amiga-fsuae" \
      org.opencontainers.image.vendor="Jaroslav Pulchart" \
      org.opencontainers.image.licenses="NOASSERTION"


# Download AROS, check it against the MD5 SourceForge publishes and unpack
# it; only /opt/aros goes into the aros image.
FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION} AS aros-fetch

ARG AROS_DATE
ARG AROS_URL=https://downloads.sourceforge.net/project/aros/nightly2/${AROS_DATE}/Binaries/AROS-${AROS_DATE}-amiga-m68k-boot-iso.zip

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# AROS's own PFS3 handler goes, so a handler under test is the only PFS3
# hadolint ignore=DL3041
RUN dnf install -y bsdtar \
    && dnf clean all \
    && { curl -fsSL --retry 3 -o /tmp/aros.zip "${AROS_URL}" \
         || { echo "AROS nightly ${AROS_DATE} has no amiga-m68k boot ISO" >&2; exit 1; }; } \
    && curl -fsSL --retry 3 -o /tmp/aros.zip.md5 "${AROS_URL}.md5" \
    && echo "$(cut -d' ' -f1 /tmp/aros.zip.md5)  /tmp/aros.zip" | md5sum -c - \
    && mkdir -p /tmp/aros /opt/aros \
    && bsdtar -xf /tmp/aros.zip -C /tmp/aros \
    && bsdtar -xf /tmp/aros/*/aros-amiga-m68k.iso -C /opt/aros \
    && cp /tmp/aros/*/LICENSE /tmp/aros/*/ACKNOWLEDGEMENTS /opt/aros/ \
    && rm /opt/aros/L/pfs3-handler \
    && chmod -R u+w /opt/aros


FROM base AS aros

ARG AROS_DATE

COPY --from=aros-fetch /opt/aros /opt/aros

ENV AROS=/opt/aros

LABEL org.opencontainers.image.title="amiga-fsuae-aros" \
      org.opencontainers.image.description="FS-UAE, Xvfb, amitools and AROS m68k for headless Amiga tests" \
      aros.version="${AROS_DATE}"


# AROS reports Kickstart 51, AmigaOS 3.x up to 47
FROM aros AS test

RUN w=$(mktemp -d) \
    && mkdir -p "$w/out" "$w/base" \
    && printf '%s\n' 'Version >OUT:version.txt' 'Echo "DONE" >OUT:done' >"$AROS/S/Startup-Sequence" \
    && printf '%s\n' "[fs-uae]" "amiga_model = A1200" "cpu = 68040-NOMMU" "fast_memory = 8192" \
        "kickstart_file = $AROS/boot/amiga/aros-rom.bin" "kickstart_ext_file = $AROS/boot/amiga/aros-ext.bin" \
        "hard_drive_0 = $w/out" "hard_drive_0_label = OUT" "hard_drive_0_priority = -128" \
        "hard_drive_2 = $AROS" "hard_drive_2_label = Boot" "hard_drive_2_priority = 10" \
        "joystick_port_1 = none" "uae_cpu_speed = max" "base_dir = $w/base" >"$w/run.fs-uae" \
    && { xvfb-run -a fs-uae "$w/run.fs-uae" >"$w/fsuae.log" 2>&1 & } \
    && for _ in $(seq 120); do [ -e "$w/out/done" ] && break; sleep 1; done \
    && { pkill -TERM -f "fs-uae $w/run.fs-uae" || true; } \
    && if grep -q "Kickstart 51" "$w/out/version.txt" 2>/dev/null; then \
           tr '\r' '\n' <"$w/out/version.txt"; \
       else \
           echo "AROS did not boot or did not report Kickstart 51" >&2; cat "$w/fsuae.log" >&2; exit 1; \
       fi
