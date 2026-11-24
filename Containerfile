# Images that run Amiga software headless in FS-UAE, see README.md

# renovate: datasource=endoflife-date depName=fedora
ARG FEDORA_VERSION=45
# <OS>_PRS are merged on top of <OS>_COMMIT, <OS>_SOURCE holds the built OS
# renovate: datasource=git-refs depName=https://github.com/aros-development-team/AROS currentValue=master
ARG AROS_COMMIT=21200a1a876f7bae0fa94fe55f4e07530eb7602d
ARG AROS_PRS="2340:9e8a89a62a02 2390:d5e6776e454d"
ARG AROS_SOURCE=aros-build
# renovate: datasource=git-refs depName=https://github.com/ApolloTeam-dev/ApolloOS currentValue=master
ARG APOLLOOS_COMMIT=6230dc2a8692e422e11a5ec3776f365c97d5a75d
ARG APOLLOOS_PRS="163:1d5728111681 164:6d51ee88bc83 165:cefa58fa65c7 166:44e256b6e0cf 167:a3a965478f28"
ARG APOLLOOS_SOURCE=apolloos-build
# AmigaOS that amigaos-test boots: 3.2.3 or 3.1
ARG AMIGAOS_VERSION=3.2.3
# the base stage, or an amiga-fsuae image to build the OS images on
ARG BASE=base
# FS-UAE from the upstream fs-uae-3 branch, plus uaelib function 120, which
# takes the PCMCIA card out of the slot and puts it back
ARG FSUAE_REPO=https://github.com/pulchart/fs-uae.git
# renovate: datasource=git-refs depName=https://github.com/pulchart/fs-uae currentValue=wip/master/pcmcia-hotplug
ARG FSUAE_COMMIT=baf0fb4b2eb9bd640078fcde1fa57eb4d11a036e

# the FS-UAE source; podman build --build-context fs-uae-source=<dir> takes
# <dir>/src instead
FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION} AS fs-uae-source

ARG FSUAE_REPO
ARG FSUAE_COMMIT
# hadolint ignore=DL3041
RUN dnf install -y git-core \
    && dnf clean all \
    && git clone -q "$FSUAE_REPO" /src \
    && git -C /src checkout -q "$FSUAE_COMMIT"


# FS-UAE built as RPM Fusion builds it, without JIT
FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION} AS fs-uae-build

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3041
RUN dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
        dnf-plugins-core \
    && dnf builddep -y --enablerepo=rpmfusion-free-source fs-uae \
    && dnf install -y git-core autoconf automake libtool gettext-devel \
    && dnf clean all

COPY --from=fs-uae-source /src /src
WORKDIR /src
RUN ./bootstrap \
    && CXXFLAGS="-O2" ./configure --disable-jit \
    && make -j"$(nproc)" \
    && strip fs-uae

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

# the RPM Fusion package brings the libraries and data files, the build the program
COPY --from=fs-uae-build /src/fs-uae /usr/bin/fs-uae
ARG FSUAE_COMMIT
LABEL fsuae.commit="${FSUAE_COMMIT}"

ENV SDL_VIDEODRIVER=x11 \
    SDL_AUDIODRIVER=dummy \
    FSUAE_PCMCIA_HOTPLUG=1

LABEL org.opencontainers.image.title="amiga-fsuae" \
      org.opencontainers.image.description="FS-UAE, Xvfb, X tools, amitools and disk tools for headless Amiga tests" \
      org.opencontainers.image.source="https://github.com/pulchart/container-amiga-fsuae" \
      org.opencontainers.image.url="https://github.com/pulchart/container-amiga-fsuae" \
      org.opencontainers.image.vendor="Jaroslav Pulchart" \
      org.opencontainers.image.licenses="NOASSERTION"


# host tools for the AROS and ApolloOS builds
FROM docker.io/library/ubuntu:22.04 AS os-build

# hadolint ignore=DL3008,DL3015
RUN apt-get update \
    && apt-get install -y autoconf automake bison byacc bzip2 ca-certificates cmake curl file \
       flex g++ gawk gcc gcc-multilib genisoimage git libc6-dev liblzo2-dev libpng-dev \
       libsdl1.2-dev libx11-dev libxcursor-dev libxext-dev libxxf86vm-dev make netpbm \
       python3 python3-mako python3-yaml unzip wget \
    && rm -rf /var/lib/apt/lists/*

COPY os-source.sh /usr/local/bin/os-source


FROM os-build AS aros-build

ARG AROS_REPO=https://github.com/aros-development-team/AROS.git
ARG AROS_COMMIT
ARG AROS_PRS

WORKDIR /usr/src/aros
RUN os-source "$AROS_REPO" "$AROS_COMMIT" "$AROS_PRS" /opt/aros-rom/source

WORKDIR /usr/src/build
RUN /usr/src/aros/configure --target=amiga-m68k --with-cpu=68040 \
    && make -j"$(nproc)" \
    && cp -a bin/amiga-m68k/AROS /opt/aros \
    && rm -r /opt/aros/Developer \
    && cp /usr/src/aros/LICENSE /usr/src/aros/ACKNOWLEDGEMENTS /opt/aros/ \
    && find /opt/aros -iname 'pfs3*-handler' -delete \
    && cp bin/amiga-m68k/gen/boot/aros-amiga-m68k-rom.bin bin/amiga-m68k/gen/boot/aros-amiga-m68k-ext.bin \
       /opt/aros-rom/


FROM ${AROS_SOURCE} AS aros-files


# hadolint ignore=DL3006
FROM ${BASE} AS aros

ARG AROS_COMMIT
ARG AROS_PRS

COPY --from=aros-files /opt/aros /opt/aros
COPY --from=aros-files /opt/aros-rom /opt/aros-rom

ENV AMIGA_SYSTEM=/opt/aros \
    AMIGA_KICKSTART=/opt/aros-rom/aros-amiga-m68k-rom.bin \
    AMIGA_KICKSTART_EXT=/opt/aros-rom/aros-amiga-m68k-ext.bin

LABEL org.opencontainers.image.title="amiga-fsuae-aros" \
      org.opencontainers.image.description="FS-UAE, Xvfb, amitools and AROS m68k for headless Amiga tests" \
      aros.commit="${AROS_COMMIT}" \
      aros.prs="${AROS_PRS}"


FROM aros AS test

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


# AmigaOS stages take the install media from build context amigaos, see README.md

FROM base AS amigaos-3.2.3-install

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

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
    && cp /tmp/update/ROMs/A1200.47.115.rom "$s/Devs/Kickstarts/A1200.rom" \
    && cp /tmp/update/ROMs/CDTVA500A600A2000.47.115.rom "$s/Devs/Kickstarts/A600.rom" \
    && tr -d '\r' </tmp/update/InstallCheck/AOS_FILES_MD5 | sed "s|  SYS:|  $s/|" | md5sum -c --quiet \
    && d=$(find "$s" | tr '[:upper:]' '[:lower:]' | sort | uniq -d) \
    && { [ -z "$d" ] || { echo "names that differ in case only: $d" >&2; exit 1; }; } \
    && { [ -z "$(find "$s" -iname 'pfs3*')" ] || { echo "AmigaOS has a PFS3 handler" >&2; exit 1; }; }


# Workbench 3.1 without L/PPaint, which is damaged on the disk
FROM base AS amigaos-3.1-install

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

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
    && mkdir Devs/Kickstarts && cp /tmp/amigaos/ROMs/kick40068.A1200 Devs/Kickstarts/A1200.rom \
    && cp /tmp/amigaos/ROMs/kick40063.A600 Devs/Kickstarts/A600.rom \
    && d=$(find . | tr '[:upper:]' '[:lower:]' | sort | uniq -d) \
    && { [ -z "$d" ] || { echo "names that differ in case only: $d" >&2; exit 1; }; } \
    && { [ -z "$(find . -iname 'pfs3*')" ] || { echo "AmigaOS has a PFS3 handler" >&2; exit 1; }; }


FROM base AS amigaos-3.2.3

COPY --from=amigaos-3.2.3-install /opt/amigaos3.2.3 /opt/amigaos3.2.3

ENV AMIGA_SYSTEM=/opt/amigaos3.2.3 \
    AMIGA_KICKSTART=/opt/amigaos3.2.3/Devs/Kickstarts/A1200.rom

LABEL org.opencontainers.image.title="amiga-fsuae-amigaos" \
      org.opencontainers.image.description="FS-UAE, Xvfb, amitools and AmigaOS 3.2.3 for headless Amiga tests, local only" \
      amigaos.version="3.2.3"


FROM base AS amigaos-3.1

COPY --from=amigaos-3.1-install /opt/amigaos3.1 /opt/amigaos3.1

ENV AMIGA_SYSTEM=/opt/amigaos3.1 \
    AMIGA_KICKSTART=/opt/amigaos3.1/Devs/Kickstarts/A1200.rom

LABEL org.opencontainers.image.title="amiga-fsuae-amigaos" \
      org.opencontainers.image.description="FS-UAE, Xvfb, amitools and AmigaOS 3.1 for headless Amiga tests, local only" \
      amigaos.version="3.1"


# hadolint ignore=DL3006
FROM amigaos-${AMIGAOS_VERSION} AS amigaos-test

ARG AMIGAOS_VERSION

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


# ApolloOS for UAE, configured as its BuildApolloOS_UAE workflow
FROM os-build AS apolloos-build

ARG APOLLOOS_REPO=https://github.com/ApolloTeam-dev/ApolloOS.git
ARG APOLLOOS_COMMIT
ARG APOLLOOS_PRS

WORKDIR /usr/src/apolloos
RUN os-source "$APOLLOOS_REPO" "$APOLLOOS_COMMIT" "$APOLLOOS_PRS" /opt/apolloos-rom/source \
    && . ./make_dist_config.sh \
    && ./configure "--enable-dist-name=${DISTRONAME}" "--enable-dist-version=${DISTROVERSION}" \
       --target=amiga-m68k --with-optimization=-O2 --with-aros-prefs=classic \
       --with-resolution=640x256x4 --with-cpu=68040 --disable-mmu --with-nonvampire-support \
    && make -j"$(nproc)" compiler \
    && make -j"$(nproc)" \
    && cp -a bin/amiga-m68k/AROS /opt/apolloos \
    && rm -r /opt/apolloos/Developer \
    && cp LICENSE ACKNOWLEDGEMENTS /opt/apolloos/ \
    && find /opt/apolloos -iname 'pfs3*-handler' -delete \
    && cp bin/amiga-m68k/gen/boot/aros-amiga-m68k-rom.bin bin/amiga-m68k/gen/boot/aros-amiga-m68k-ext.bin \
       /opt/apolloos-rom/


FROM ${APOLLOOS_SOURCE} AS apolloos-files


# hadolint ignore=DL3006
FROM ${BASE} AS apolloos

ARG APOLLOOS_COMMIT
ARG APOLLOOS_PRS

COPY --from=apolloos-files /opt/apolloos /opt/apolloos
COPY --from=apolloos-files /opt/apolloos-rom /opt/apolloos-rom

ENV AMIGA_SYSTEM=/opt/apolloos \
    AMIGA_KICKSTART=/opt/apolloos-rom/aros-amiga-m68k-rom.bin \
    AMIGA_KICKSTART_EXT=/opt/apolloos-rom/aros-amiga-m68k-ext.bin \
    AMIGA_HD_CONTROLLER=uae

LABEL org.opencontainers.image.title="amiga-fsuae-apolloos" \
      org.opencontainers.image.description="FS-UAE, Xvfb, amitools and ApolloOS for headless Amiga tests" \
      apolloos.commit="${APOLLOOS_COMMIT}" \
      apolloos.prs="${APOLLOOS_PRS}"


FROM apolloos AS apolloos-test

# hadolint ignore=SC2016
RUN w=$(mktemp -d) \
    && mkdir -p "$w/out" "$w/base" \
    && rdbtool "$w/disk.hdf" create size=16M + init + add size=100% name=TST0 dostype=DOS3 >/dev/null \
    && printf '%s\n' 'FailAt 1000' 'Echo "" >RAM:enter' 'Version >OUT:version.txt' \
        'SYS:System/Format DRIVE TST0: NAME Test QUICK NOICONS <RAM:enter >NIL:' \
        'MakeDir TST0:c' 'Copy C: TST0:c QUIET' 'Delete TST0:c/List QUIET' 'Wait 1' \
        'C:List TST0:c FILES LFORMAT "%n" >OUT:list.txt' \
        'RequestChoice >OUT:choice.txt TITLE "Test" BODY "Answer" GADGETS "Yes|No"' 'Echo "DONE" >OUT:done' >"$AMIGA_SYSTEM/S/Startup-Sequence" \
    && printf '%s\n' "[fs-uae]" "amiga_model = A1200" "cpu = 68040-NOMMU" "chip_memory = 2048" "fast_memory = 8192" \
        "kickstart_file = $AMIGA_KICKSTART" "kickstart_ext_file = $AMIGA_KICKSTART_EXT" \
        "hard_drive_0 = $w/out" "hard_drive_0_label = OUT" "hard_drive_0_priority = -128" \
        "hard_drive_1 = $w/disk.hdf" "hard_drive_1_type = rdb" "hard_drive_1_controller = $AMIGA_HD_CONTROLLER" \
        "hard_drive_2 = $AMIGA_SYSTEM" "hard_drive_2_label = Boot" "hard_drive_2_priority = 10" \
        "joystick_port_1 = none" "uae_cpu_speed = max" "base_dir = $w/base" >"$w/run.fs-uae" \
    && printf '%s\n' 'fs-uae "$1/run.fs-uae" >"$1/fsuae.log" 2>&1 &' \
        'for _ in $(seq 120); do [ -e "$1/out/done" ] && break; xdotool key super+v; sleep 1; done' \
        'python3 -c "from PIL import ImageGrab; ImageGrab.grab(xdisplay=\"\").save(\"$1/screen.png\")"' \
        'kill -TERM $!; wait $!' >"$w/run.sh" \
    && xvfb-run -a sh "$w/run.sh" "$w" \
    && if ! grep -q "Kickstart 51\." "$w/out/version.txt" 2>/dev/null; then \
           echo "ApolloOS did not boot or did not report Kickstart 51" >&2; cat "$w/fsuae.log" >&2; exit 1; \
       fi \
    && tr '\r' '\n' <"$w/out/version.txt" \
    && { grep -qx Copy "$w/out/list.txt" && ! grep -qx List "$w/out/list.txt" \
         || { echo "Format, MakeDir, Copy, Delete or List failed on the RDB disk" >&2; exit 1; }; } \
    && { grep -q 1 "$w/out/choice.txt" || { echo "xdotool did not answer the requester" >&2; exit 1; }; } \
    && { [ -s "$w/screen.png" ] || { echo "Pillow took no screenshot" >&2; exit 1; }; }
