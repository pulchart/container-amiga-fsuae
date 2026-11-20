# Images that run Amiga software headless in FS-UAE.
#   base: amiga-fsuae, FS-UAE, Xvfb, X tools, amitools and disk tools on Fedora
#   aros: amiga-fsuae-aros, base and an AROS m68k nightly in /opt/aros,
#   booted with the ROM in rom/ until the nightly has its ata.device fix
#   test: boots AROS from aros, answers a requester with xdotool, takes a
#   screenshot with Pillow
#   amigaos-3.2.3, amigaos-3.1: amiga-fsuae-amigaos, base and an installed
#   AmigaOS in /opt/amigaos<version>, built locally from own install media
#   and never published
#   amigaos-test: test for the AmigaOS of AMIGAOS_VERSION, with an RDB disk
# FS-UAE and amitools follow their newest releases for that Fedora, Renovate
# moves FEDORA_VERSION and AROS_DATE.

# renovate: datasource=endoflife-date depName=fedora
ARG FEDORA_VERSION=45
# renovate: datasource=custom.aros-nightly depName=aros-nightly
ARG AROS_DATE=20261118
# where /opt/aros comes from: aros-fetch, or a released amiga-fsuae-aros of
# the same AROS_DATE and aros-fetch and aros stages
ARG AROS_SOURCE=aros-fetch
# AmigaOS that amigaos-test boots: 3.2.3 or 3.1
ARG AMIGAOS_VERSION=3.2.3

FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION} AS base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3013,DL3041
RUN dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    && dnf install -y \
        fs-uae \
        xorg-x11-server-Xvfb xauth xdotool \
        python3 python3-pip python3-pyyaml python3-pillow \
        mtools dosfstools exfatprogs lhasa \
        procps-ng findutils \
    && pip install --no-cache-dir --root-user-action=ignore amitools \
    && dnf clean all \
    && rm -rf /root/.cache

ENV SDL_VIDEODRIVER=x11 \
    SDL_AUDIODRIVER=dummy

LABEL org.opencontainers.image.title="amiga-fsuae" \
      org.opencontainers.image.description="FS-UAE, Xvfb, X tools, amitools and disk tools for headless Amiga tests" \
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
    && { curl -fsSL --retry 3 --retry-all-errors -o /tmp/aros.zip "${AROS_URL}" \
         || { echo "AROS nightly ${AROS_DATE} has no amiga-m68k boot ISO" >&2; exit 1; }; } \
    && curl -fsSL --retry 3 --retry-all-errors -o /tmp/aros.zip.md5 "${AROS_URL}.md5" \
    && echo "$(cut -d' ' -f1 /tmp/aros.zip.md5)  /tmp/aros.zip" | md5sum -c - \
    && mkdir -p /tmp/aros /opt/aros \
    && bsdtar -xf /tmp/aros.zip -C /tmp/aros \
    && bsdtar -xf /tmp/aros/*/aros-amiga-m68k.iso -C /opt/aros \
    && cp /tmp/aros/*/LICENSE /tmp/aros/*/ACKNOWLEDGEMENTS /opt/aros/ \
    && rm /opt/aros/L/pfs3-handler \
    && chmod -R u+w /opt/aros


FROM ${AROS_SOURCE} AS aros-files


FROM base AS aros

ARG AROS_DATE

COPY --from=aros-files /opt/aros /opt/aros

# The nightly ata.device fails PIO writes at times with error 45. Until a
# nightly has the fix (aros-development-team/AROS#2350), the ROM in rom/ is
# built from pulchart/AROS 2b2d724966, that fix on AROS master 7539b08c14.
# A checkout without Git LFS has pointer files there, which fail the check.
COPY rom/aros-amiga-m68k-rom.bin rom/aros-amiga-m68k-ext.bin /opt/aros-rom/
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN printf '%s\n' \
        '7566b66ce1abe41b8cf2b0ce557adbf797ff7c2b4379d50985e7e527eb073006  /opt/aros-rom/aros-amiga-m68k-rom.bin' \
        '05afce22eedc95b75e4270569d658ecfafd9150b90bbc906bd59ca7f79da1454  /opt/aros-rom/aros-amiga-m68k-ext.bin' \
    | sha256sum -c --quiet

ENV AMIGA_SYSTEM=/opt/aros \
    AMIGA_KICKSTART=/opt/aros-rom/aros-amiga-m68k-rom.bin \
    AMIGA_KICKSTART_EXT=/opt/aros-rom/aros-amiga-m68k-ext.bin

LABEL org.opencontainers.image.title="amiga-fsuae-aros" \
      org.opencontainers.image.description="FS-UAE, Xvfb, amitools and AROS m68k for headless Amiga tests" \
      aros.version="${AROS_DATE}" \
      aros.rom="pulchart/AROS 2b2d724966, aros-development-team/AROS#2350"


# AROS reports Kickstart 51, AmigaOS 3.x up to 47
FROM aros AS test

# run.sh expands its own variables
# hadolint ignore=SC2016
RUN w=$(mktemp -d) \
    && mkdir -p "$w/out" "$w/base" \
    && printf '%s\n' 'Version >OUT:version.txt' \
        'RequestChoice >OUT:choice.txt TITLE "Test" BODY "Answer" GADGETS "Yes|No"' 'Echo "DONE" >OUT:done' >"$AMIGA_SYSTEM/S/Startup-Sequence" \
    && printf '%s\n' "[fs-uae]" "amiga_model = A1200" "cpu = 68040-NOMMU" "fast_memory = 8192" \
        "kickstart_file = $AMIGA_KICKSTART" "kickstart_ext_file = $AMIGA_KICKSTART_EXT" \
        "hard_drive_0 = $w/out" "hard_drive_0_label = OUT" "hard_drive_0_priority = -128" \
        "hard_drive_2 = $AMIGA_SYSTEM" "hard_drive_2_label = Boot" "hard_drive_2_priority = 10" \
        "joystick_port_1 = none" "uae_cpu_speed = max" "base_dir = $w/base" >"$w/run.fs-uae" \
    && printf '%s\n' 'fs-uae "$1/run.fs-uae" >"$1/fsuae.log" 2>&1 &' \
        'for _ in $(seq 120); do [ -e "$1/out/done" ] && break; xdotool key super+v; sleep 1; done' \
        'python3 -c "from PIL import ImageGrab; ImageGrab.grab(xdisplay=\"\").save(\"$1/screen.png\")"' \
        'kill -TERM $!; wait $!' >"$w/run.sh" \
    && xvfb-run -a sh "$w/run.sh" "$w" \
    && if ! grep -q "Kickstart 51" "$w/out/version.txt" 2>/dev/null; then \
           echo "AROS did not boot or did not report Kickstart 51" >&2; cat "$w/fsuae.log" >&2; exit 1; \
       fi \
    && tr '\r' '\n' <"$w/out/version.txt" \
    && { grep -q 1 "$w/out/choice.txt" || { echo "xdotool did not answer the requester" >&2; exit 1; }; } \
    && { [ -s "$w/screen.png" ] || { echo "Pillow took no screenshot" >&2; exit 1; }; }


# AmigaOS is not free: its stages take the install media from a build context
# that holds AmigaOS3.2/adf, Update3.2.3 and AmigaOS3.1, e.g.
#   podman build --build-context amigaos=/opt/AmigaOS --target amigaos-3.2.3 .

# AmigaOS 3.2 from its ADFs as its Installer puts it on a hard drive of a
# machine with a 3.2.3 ROM, which needs no Kickstart modules, then Update
# 3.2.3. The result has to match the MD5 list of the update's InstallCheck.
FROM base AS amigaos-3.2.3-install

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# amigaos is the build context
# hadolint ignore=DL3022
COPY --from=amigaos AmigaOS3.2/adf /tmp/adf
# hadolint ignore=DL3022
COPY --from=amigaos Update3.2.3 /tmp/update

WORKDIR /tmp/disk

RUN s=/opt/amigaos3.2.3 \
    && for f in /tmp/adf/{install3.2,workbench3.2,locale,extras3.2,classes3.2,fonts,storage3.2}.adf \
                /tmp/update/ADFs/{Update3.2.3,Classes3.2.3,DiskDoctor3.2.3,Extras3.2.3}.adf; do \
           xdftool "$f" unpack "$(basename "$f" .adf)" >/dev/null; \
       done \
    && rm -r {workbench3.2,extras3.2,classes3.2,fonts}/Disk.info workbench3.2/S/Startup-sequence \
    && mkdir -p "$s"/{Tools,System,Libs,Locale,Storage,Devs/Kickstarts} \
    && cp -r workbench3.2/. extras3.2/. classes3.2/. "$s/" \
    && cp -r fonts "$s/Fonts" \
    && cp install3.2/HDTools/HDToolBox* "$s/Tools/" \
    && cp install3.2/Installer "$s/System/" \
    && cp install3.2/Libs/{workbench,icon}.library "$s/Libs/" \
    && cp -r locale/Countries "$s/Locale/" \
    && cp storage3.2/{DataTypes,DOSDrivers,Keymaps,Monitors,Printers}.info "$s/Storage/" \
    && cp -r storage3.2/{Monitors,DOSDrivers} "$s/Storage/" \
    && cp -r storage3.2/{Classes,C,WBStartup} "$s/" \
    && cp -r storage3.2/LIBS/. "$s/Libs/" \
    && cp -r storage3.2/{Printers,Keymaps} "$s/Devs/" \
    && cp storage3.2/DefIcons/*.info storage3.2/Env-Archive/Pointer.prefs "$s/Prefs/Env-Archive/Sys/" \
    && cp storage3.2/Env-Archive/deficons.prefs "$s/Prefs/Env-Archive/" \
    && mkdir -p "$s/Prefs/Presets" && cp -r storage3.2/Presets/Pointers "$s/Prefs/Presets/" \
    && mkdir -p "$s/Prefs/Env-Archive/Versions" \
    && cp Update3.2.3/Update/Release "$s/Prefs/Env-Archive/Versions/" \
    && gzip -dc Update3.2.3/Update/Startup-HardDrive.Z >"$s/S/Startup-Sequence" \
    && gzip -dc Update3.2.3/Update/Startup-HardDrive_NOMEMFKICK.Z >"$s/S/Startup-Sequence_NOMEMFKICK" \
    && cp Update3.2.3/T/ed-backup "$s/T/" \
    && rm -r Update3.2.3/Update \
    && cp DiskDoctor3.2.3/C/{DAControl,DiskDoctor,Eval,Execute,List,MakeDir,Protect,SetPatch,Type} "$s/C/" \
    && cp DiskDoctor3.2.3/Devs/trackfile.device "$s/Devs/" \
    && find Update3.2.3 Classes3.2.3 Extras3.2.3 -name '*.Z' | while read -r f; do \
           t=$(sed 's|^[^/]*/||; s|^DEVS/|Devs/|; s|^LIBS/|Libs/|; s|^Classes/Datatypes/|Classes/DataTypes/|; s|\.Z$||' <<<"$f"); \
           mkdir -p "$(dirname "$s/$t")" && gzip -dc "$f" >"$s/$t" || exit 1; \
       done \
    && cp /tmp/update/ROMs/A1200.47.115.rom "$s/Devs/Kickstarts/" \
    && tr -d '\r' </tmp/update/InstallCheck/AOS_FILES_MD5 | sed "s|  SYS:|  $s/|" | md5sum -c --quiet \
    && d=$(find "$s" | tr '[:upper:]' '[:lower:]' | sort | uniq -d) \
    && { [ -z "$d" ] || { echo "names that differ in case only: $d" >&2; exit 1; }; } \
    && { [ -z "$(find "$s" -iname 'pfs3*')" ] || { echo "AmigaOS has a PFS3 handler" >&2; exit 1; }; }


# AmigaOS 3.1: its Workbench disk without L/PPaint, a bundle drawer with a
# damaged file, and 68040.library from its Install disk
FROM base AS amigaos-3.1-install

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# amigaos is the build context
# hadolint ignore=DL3022
COPY --from=amigaos AmigaOS3.1 /tmp/amigaos

WORKDIR /opt/amigaos3.1

RUN mkdir L \
    && for e in C Classes Devs Expansion Libs Prefs Rexxc S System T Utilities WBStartup \
                Devs.info Expansion.info Prefs.info System.info Utilities.info WBStartup.info \
                L/aux-handler L/port-handler L/queue-handler; do \
           xdftool /tmp/amigaos/ADFs/wbench31.adf read "$e" "$e"; \
       done \
    && xdftool /tmp/amigaos/ADFs/install31.adf read Libs/68040.library Libs/68040.library \
    && mkdir Devs/Kickstarts && cp /tmp/amigaos/ROMs/kick40068.A1200 Devs/Kickstarts/ \
    && d=$(find . | tr '[:upper:]' '[:lower:]' | sort | uniq -d) \
    && { [ -z "$d" ] || { echo "names that differ in case only: $d" >&2; exit 1; }; } \
    && { [ -z "$(find . -iname 'pfs3*')" ] || { echo "AmigaOS has a PFS3 handler" >&2; exit 1; }; }


FROM base AS amigaos-3.2.3

COPY --from=amigaos-3.2.3-install /opt/amigaos3.2.3 /opt/amigaos3.2.3

ENV AMIGA_SYSTEM=/opt/amigaos3.2.3 \
    AMIGA_KICKSTART=/opt/amigaos3.2.3/Devs/Kickstarts/A1200.47.115.rom

LABEL org.opencontainers.image.title="amiga-fsuae-amigaos" \
      org.opencontainers.image.description="FS-UAE, Xvfb, amitools and AmigaOS 3.2.3 for headless Amiga tests, local only" \
      amigaos.version="3.2.3"


FROM base AS amigaos-3.1

COPY --from=amigaos-3.1-install /opt/amigaos3.1 /opt/amigaos3.1

ENV AMIGA_SYSTEM=/opt/amigaos3.1 \
    AMIGA_KICKSTART=/opt/amigaos3.1/Devs/Kickstarts/kick40068.A1200

LABEL org.opencontainers.image.title="amiga-fsuae-amigaos" \
      org.opencontainers.image.description="FS-UAE, Xvfb, amitools and AmigaOS 3.1 for headless Amiga tests, local only" \
      amigaos.version="3.1"


# As test, with the memory and the RDB disk on ide0 of the pfs3aio tests,
# which it formats and fills. AmigaOS 3.1 reports Kickstart 40, 3.2.x 47.
# a stage of this file, not an image
# hadolint ignore=DL3006
FROM amigaos-${AMIGAOS_VERSION} AS amigaos-test

ARG AMIGAOS_VERSION

# run.sh expands its own variables
# hadolint ignore=SC2016
RUN w=$(mktemp -d) \
    && case "$AMIGAOS_VERSION" in 3.1) k=40 ;; *) k=47 ;; esac \
    && mkdir -p "$w/out" "$w/base" \
    && rdbtool "$w/disk.hdf" create size=16M + init + add size=100% name=TST0 dostype=DOS3 >/dev/null \
    && printf '%s\n' 'FailAt 1000' 'MakeDir RAM:T RAM:ENV' 'Assign >NIL: ENV: RAM:ENV' 'Assign >NIL: T: RAM:T' \
        'Echo "" >RAM:enter' 'Version >OUT:version.txt' 'CPU >OUT:cpu.txt' \
        'SYS:System/Format DRIVE TST0: NAME Test QUICK NOICONS <RAM:enter >NIL:' \
        'MakeDir TST0:c' 'Copy C: TST0:c QUIET' 'Delete TST0:c/List QUIET' 'Wait 1' \
        'C:List TST0:c FILES LFORMAT "%n" >OUT:list.txt' \
        'RequestChoice >OUT:choice.txt TITLE "Test" BODY "Answer" GADGETS "Yes|No"' 'Echo "DONE" >OUT:done' >"$AMIGA_SYSTEM/S/Startup-Sequence" \
    && printf '%s\n' "[fs-uae]" "amiga_model = A1200" "cpu = 68040-NOMMU" "chip_memory = 2048" "fast_memory = 8192" \
        "kickstart_file = $AMIGA_KICKSTART" \
        "hard_drive_0 = $w/out" "hard_drive_0_label = OUT" "hard_drive_0_priority = -128" \
        "hard_drive_1 = $w/disk.hdf" "hard_drive_1_type = rdb" "hard_drive_1_controller = ide0" \
        "hard_drive_2 = $AMIGA_SYSTEM" "hard_drive_2_label = Boot" "hard_drive_2_priority = 10" \
        "joystick_port_1 = none" "uae_cpu_speed = max" "base_dir = $w/base" >"$w/run.fs-uae" \
    && printf '%s\n' 'fs-uae "$1/run.fs-uae" >"$1/fsuae.log" 2>&1 &' \
        'for _ in $(seq 120); do [ -e "$1/out/done" ] && break; xdotool key super+v; sleep 1; done' \
        'python3 -c "from PIL import ImageGrab; ImageGrab.grab(xdisplay=\"\").save(\"$1/screen.png\")"' \
        'kill -TERM $!; wait $!' >"$w/run.sh" \
    && xvfb-run -a sh "$w/run.sh" "$w" \
    && if ! grep -q "Kickstart $k\." "$w/out/version.txt" 2>/dev/null; then \
           echo "AmigaOS did not boot or did not report Kickstart $k" >&2; cat "$w/fsuae.log" >&2; exit 1; \
       fi \
    && tr '\r' '\n' <"$w/out/version.txt" \
    && cat "$w/out/cpu.txt" \
    && { grep -qx Copy "$w/out/list.txt" && ! grep -qx List "$w/out/list.txt" \
         || { echo "Format, MakeDir, Copy, Delete or List failed on the RDB disk" >&2; exit 1; }; } \
    && { grep -q 1 "$w/out/choice.txt" || { echo "xdotool did not answer the requester" >&2; exit 1; }; } \
    && { [ -s "$w/screen.png" ] || { echo "Pillow took no screenshot" >&2; exit 1; }; }
