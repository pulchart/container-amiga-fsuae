# container-amiga-fsuae

Container images that run Amiga software headless in FS-UAE, for tests in CI and locally, such as those of fat95, pfs3aio and cfd. The image brings the emulator, the OS and the host tools to make and check disk images; the test brings the software it built and its steps.

## Images

On GHCR and Docker Hub, same tags and digests.

| image | tag | contents |
|---|---|---|
| `pulchart/amiga-fsuae` | `<fsuae version>`, e.g. `3.2.35` | Fedora, FS-UAE, Xvfb, xauth, xdotool, amitools, PyYAML, Pillow, mtools, dosfstools, exfatprogs, lhasa |
| | `<fsuae version>-<build date>`, e.g. `3.2.35-20261119` | one build |
| | `latest` | newest build |
| `pulchart/amiga-fsuae-aros` | `<AROS nightly date>`, e.g. `20261118` | `amiga-fsuae` and AROS m68k in `/opt/aros` |
| | `<AROS nightly date>-<build date>`, e.g. `20261118-20261119` | one build |
| | `latest` | newest build |

```sh
podman pull ghcr.io/pulchart/amiga-fsuae-aros:20261118-20261119
podman pull docker.io/pulchart/amiga-fsuae-aros:20261118-20261119
```

Pin CI to a tag with a build date. GHCR keeps the newest 10 versions of each image, Docker Hub keeps every copied tag. The labels `fedora.version`, `fsuae.version`, `amitools.version`, `aros.version`, `build.date` and `org.opencontainers.image.revision` show what an image holds:

```sh
podman image inspect ghcr.io/pulchart/amiga-fsuae-aros:latest --format '{{json .Labels}}'
```

An OS image names its system directory in `AMIGA_SYSTEM` and its ROM in `AMIGA_KICKSTART`, plus `AMIGA_KICKSTART_EXT` when the ROM has a second half, so a test needs no OS specific paths. `amiga-fsuae-aros` has no `L:pfs3-handler`, so a PFS3 handler under test is the only one.

## Versions

`FEDORA_VERSION` and `AROS_DATE` are pinned in the `Containerfile`. Renovate keeps one pull request with all updates and refreshes it daily between 4 and 8 UTC, after SourceForge has the night's AROS build. Fedora releases come from endoflife.date, so no prerelease.

FS-UAE (RPM Fusion) and amitools (PyPI) take their newest release at every build. Tags and labels come from the versions found in the image.

SourceForge drops nightlies after a few days, so a pull request with a new `AROS_DATE` has to build while its nightly is there. A nightly without an amiga-m68k build fails with "has no amiga-m68k boot ISO" until Renovate moves on. The build checks the archive against the MD5 SourceForge publishes.

## Use

```sh
podman run --rm -v "$PWD:/work" -w /work ghcr.io/pulchart/amiga-fsuae-aros:20261118-20261119 \
    xvfb-run -a fs-uae run.fs-uae
```

```yaml
jobs:
  test:
    runs-on: ubuntu-24.04
    container: ghcr.io/pulchart/amiga-fsuae-aros:20261118-20261119
```

FS-UAE names directory drives after their slot (`hard_drive_0` is `DH0:`), so partitions on test disks need other names. Stop FS-UAE with SIGTERM and wait for it to exit, or its last disk writes are lost.

A requester stops a headless run until it is answered. `xdotool key super+v` sends left Amiga V, which picks its left gadget. `python3 -c 'from PIL import ImageGrab; ImageGrab.grab(xdisplay="").save("screen.png")'` shows where a stalled run stopped.

## Build

```sh
podman build --target base -t amiga-fsuae .
podman build --target aros -t amiga-fsuae-aros .
podman build --target test .    # boots AROS, answers a requester, takes a screenshot
```

| workflow | when | does |
|---|---|---|
| `Images` | pull request | lint; when it changes the `Containerfile` or `images.yml` also build, `test` stage, labels, and a pull request from this repository pushes `amiga-fsuae-pr:pr-<number>` and `amiga-fsuae-aros-pr:pr-<number>` and attests them |
| | pull request from this repository merged into `master` | copies the tested `pr-<number>` images to the release tags when it changed the `Containerfile` or `images.yml`, same digests, keeps 10 versions |
| | pull request closed | deletes its `pr-<number>` images |
| | manual on `master` | builds and publishes the release tags directly, e.g. for a newer FS-UAE without a pull request |
| `Copy to Docker Hub` | manual, owner, `master` | copies `latest` and the version tags with `skopeo sync`, lists each tag as copied, unchanged or differs in the job summary and fails on differs; the only user of the Docker Hub token |

The release images are the ones the pull request tested, so a pull request must be up to date with `master` before it merges.

Check where an image was built:

```sh
gh attestation verify oci://ghcr.io/pulchart/amiga-fsuae-aros:20261118-20261119 -R pulchart/container-amiga-fsuae
```

## Licenses

The build recipes are MPL-2.0 (`LICENSE`). The software in the images keeps its own license.

| component | license | source |
|---|---|---|
| FS-UAE | GPL-2.0-or-later | [fs-uae.net](https://fs-uae.net), RPM Fusion source package |
| AROS | AROS Public License | [aros-development-team/AROS](https://github.com/aros-development-team/AROS), [SourceForge nightlies](https://sourceforge.net/projects/aros/files/nightly2/) |
| amitools | GPL-2.0-or-later | [cnvogelg/amitools](https://github.com/cnvogelg/amitools) |
| Fedora packages | per package | Fedora source packages |
