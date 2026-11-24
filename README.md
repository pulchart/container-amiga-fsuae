# container-amiga-fsuae

Container images that run Amiga software headless in FS-UAE, for tests in CI and locally, such as those of fat95, pfs3aio and cfd. The image brings the emulator, the OS and the host tools to make and check disk images; the test brings the software it built and its steps.

## Images

On GHCR and Docker Hub, same tags and digests.

| image | tag | contents |
|---|---|---|
| `pulchart/amiga-fsuae` | `<fsuae version>`, e.g. `3.2.35` | Fedora, FS-UAE, Xvfb, xauth, xdotool, amitools, PyYAML, Pillow, mtools, dosfstools, exfatprogs, lhasa |
| | `<fsuae version>-<build date>`, e.g. `3.2.35-20261119` | one build |
| | `latest` | newest build |
| `pulchart/amiga-fsuae-aros` | `<AROS commit date>`, e.g. `20261121` | `amiga-fsuae` and AROS m68k in `/opt/aros`, ROM in `/opt/aros-rom` |
| | `<AROS commit date>-<build date>`, e.g. `20261121-20261121` | one build |
| | `latest` | newest build |
| `pulchart/amiga-fsuae-apolloos` | `<ApolloOS commit date>`, e.g. `20261010` | `amiga-fsuae` and ApolloOS for UAE in `/opt/apolloos`, ROM in `/opt/apolloos-rom` |
| | `<ApolloOS commit date>-<build date>`, e.g. `20261010-20261121` | one build |
| | `latest` | newest build |

```sh
podman pull ghcr.io/pulchart/amiga-fsuae-aros:20261121-20261121
podman pull docker.io/pulchart/amiga-fsuae-aros:20261121-20261121
```

Pin CI to a tag with a build date. GHCR keeps the newest 10 versions of each image, Docker Hub keeps every copied tag. The labels `fedora.version`, `fsuae.version`, `amitools.version`, `build.date` and `org.opencontainers.image.revision` show what an image holds. An OS image adds `<os>.commit`, `<os>.prs`, `<os>.version` with the commit date and `<os>.build`:

```sh
podman image inspect ghcr.io/pulchart/amiga-fsuae-aros:latest --format '{{json .Labels}}'
```

An OS image names its system directory in `AMIGA_SYSTEM` and its ROM in `AMIGA_KICKSTART`, plus `AMIGA_KICKSTART_EXT` when the ROM has a second half, so a test needs no OS specific paths. A test disk goes on the FS-UAE controller in `AMIGA_HD_CONTROLLER`, `ide0` when it is not set. ApolloOS finds IDE only on Apollo boards, so `amiga-fsuae-apolloos` sets `uae`. The OS images have no PFS3 handler, so a PFS3 handler under test is the only one.

## Versions

`FEDORA_VERSION`, `AROS_COMMIT`, `APOLLOOS_COMMIT` and `FSUAE_COMMIT` are pinned in the `Containerfile`. Renovate keeps one pull request with all updates and refreshes it daily between 4 and 8 UTC. The commits follow `master` of AROS and ApolloOS and `wip/master/pcmcia-hotplug` of pulchart/fs-uae. Fedora releases come from endoflife.date, so no prerelease.

FS-UAE (RPM Fusion) and amitools (PyPI) take their newest release at every build. Tags and labels come from the versions found in the image.

The `fs-uae` program itself is built from [pulchart/fs-uae](https://github.com/pulchart/fs-uae) at `FSUAE_COMMIT`, the upstream `fs-uae-3` branch with uaelib function 120 ([FrodeSolheim/fs-uae#398](https://github.com/FrodeSolheim/fs-uae/pull/398)), which takes the PCMCIA card out of the slot and puts it back from the Amiga side, so a test can keep the slot empty. The images set `FSUAE_PCMCIA_HOTPLUG=1` and the label `fsuae.commit`. Locally, `podman build --build-context fs-uae-source=<dir>` builds `<dir>/src` instead of the commit.

AROS and ApolloOS build from source at their commit, with the pull requests in `AROS_PRS` and `APOLLOOS_PRS` merged on top. Each pull request is pinned to a prefix of its head commit as `<number>:<head commit prefix>`, so a pull request that moved stops the build until its pin is updated. `os-source.sh` does the fetch and the merges.

A build takes the OS from an earlier image of the pull request or from the released `latest` when its `<os>.build` label matches the hash of the build stages, the commit, the pull requests and `os-source.sh`, so an OS builds only when one of them changes. Locally, `podman build --build-arg AROS_SOURCE=<image>` or `APOLLOOS_SOURCE=<image>` takes the OS from that image without the label check.

## Use

```sh
podman run --rm -v "$PWD:/work" -w /work ghcr.io/pulchart/amiga-fsuae-aros:20261121-20261121 \
    xvfb-run -a fs-uae run.fs-uae
```

```yaml
jobs:
  test:
    runs-on: ubuntu-24.04
    container: ghcr.io/pulchart/amiga-fsuae-aros:20261121-20261121
```

FS-UAE names directory drives after their slot (`hard_drive_0` is `DH0:`), so partitions on test disks need other names. Stop FS-UAE with SIGTERM and wait for it to exit, or its last disk writes are lost.

A requester stops a headless run until it is answered. `xdotool key super+v` sends left Amiga V, which picks its left gadget. `python3 -c 'from PIL import ImageGrab; ImageGrab.grab(xdisplay="").save("screen.png")'` shows where a stalled run stopped.

## Build

```sh
podman build --target base -t amiga-fsuae .
podman build --target aros -t amiga-fsuae-aros .
podman build --target test .    # boots AROS, answers a requester, takes a screenshot
podman build --target apolloos -t amiga-fsuae-apolloos .
podman build --target apolloos-test .
```

| workflow | when | does |
|---|---|---|
| `Images` | pull request | lint; when it changes the `Containerfile`, `os-source.sh` or `images.yml`, job `base` builds `amiga-fsuae` and the `os` jobs build AROS and ApolloOS on it side by side, a fork on its own base, and run their test stages; a pull request from this repository pushes `amiga-fsuae-pr`, `amiga-fsuae-aros-pr` and `amiga-fsuae-apolloos-pr` as `pr-<number>` and attests them; job `images` is the required check |
| | pull request from this repository merged into `master` | copies the tested `pr-<number>` images to the release tags when it changed the `Containerfile`, `os-source.sh` or `images.yml`, same digests, keeps 10 versions |
| | pull request closed | deletes its `pr-<number>` images |
| | manual on `master` | builds and tests as a pull request, pushes as `run-<id>`, copies those images to the release tags when all passed and deletes the `run-<id>` images, e.g. for a newer FS-UAE without a pull request |
| `Copy to Docker Hub` | manual, owner, `master` | copies `latest` and the version tags with `skopeo sync`, lists each tag as copied, unchanged or differs in the job summary and fails on differs; the only user of the Docker Hub token |

The AROS and ApolloOS images build on the `base` stage, or on the image in `BASE`, which CI sets to the `amiga-fsuae` of the run. `.github/scripts/publish.sh` copies tested images to the release tags and `.github/scripts/delete-pr-images.sh` deletes the tested images.

The release images are the ones the pull request tested, so a pull request must be up to date with `master` before it merges.

Check where an image was built:

```sh
gh attestation verify oci://ghcr.io/pulchart/amiga-fsuae-aros:20261121-20261121 -R pulchart/container-amiga-fsuae
```

## AmigaOS, local only

AmigaOS is not free, so `amiga-fsuae-amigaos` is built locally from own install media and never pushed. The `amigaos` build context holds `AmigaOS3.2/adf`, `Update3.2.3` and `AmigaOS3.1`:

```sh
podman build --build-context amigaos=/opt/AmigaOS --target amigaos-3.2.3 -t localhost/amiga-fsuae-amigaos:3.2.3 .
podman build --build-context amigaos=/opt/AmigaOS --target amigaos-3.1 -t localhost/amiga-fsuae-amigaos:3.1 .
podman build --build-context amigaos=/opt/AmigaOS --target amigaos-test --build-arg AMIGAOS_VERSION=3.1 .
```

`amigaos-3.2.3` installs 3.2 from its ADFs as its Installer does with the 3.2.3 ROM, then Update 3.2.3, and checks the result against the MD5 list of the update's InstallCheck. `amigaos-3.1` is the Workbench 3.1 disk without its damaged `L/PPaint` drawer, plus `68040.library`. Both hold the A1200 and the A600 ROM as `Devs/Kickstarts/A1200.rom` and `A600.rom`, as the installed system is the same for both models; `AMIGA_KICKSTART` names the A1200 one. `amigaos-test` boots one with an RDB disk on ide0 and formats and fills that disk.

## Licenses

The build recipes are MPL-2.0 (`LICENSE`). The software in the images keeps its own license.

| component | license | source |
|---|---|---|
| FS-UAE | GPL-2.0-or-later | [fs-uae.net](https://fs-uae.net), RPM Fusion source package; the program from [pulchart/fs-uae](https://github.com/pulchart/fs-uae) at `fsuae.commit` |
| AROS | AROS Public License | [aros-development-team/AROS](https://github.com/aros-development-team/AROS) at `aros.commit` with `aros.prs` |
| ApolloOS | AROS Public License | [ApolloTeam-dev/ApolloOS](https://github.com/ApolloTeam-dev/ApolloOS) at `apolloos.commit` with `apolloos.prs` |
| amitools | GPL-2.0-or-later | [cnvogelg/amitools](https://github.com/cnvogelg/amitools) |
| Fedora packages | per package | Fedora source packages |
