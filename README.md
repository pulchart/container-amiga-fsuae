# container-amiga-fsuae

Container images that run Amiga software headless in FS-UAE, for tests in CI and locally, such as those of fat95, pfs3aio and cfd. The image brings the emulator, the OS and the host tools to make and check disk images; the test brings the software it built and its steps.

## Images

On GHCR and Docker Hub, same tags and digests.

| image | tag | contents |
|---|---|---|
| `pulchart/amiga-fsuae` | `<fsuae version>`, e.g. `3.2.35` | Fedora, FS-UAE, Xvfb, xauth, amitools, PyYAML, mtools, dosfstools, exfatprogs, lhasa |
| | `<fsuae version>-<build date>`, e.g. `3.2.35-20261119` | one build |
| | `latest` | newest build |
| `pulchart/amiga-fsuae-aros` | `<AROS nightly date>`, e.g. `20261118` | `amiga-fsuae` and AROS m68k in `/opt/aros` |
| | `<AROS nightly date>-<build date>`, e.g. `20261118-20261119` | one build |
| | `latest` | newest build |

```sh
podman pull ghcr.io/pulchart/amiga-fsuae-aros:20261118-20261119
podman pull docker.io/pulchart/amiga-fsuae-aros:20261118-20261119
```

Pin CI to a tag with a build date. GHCR keeps the newest 10 versions of each image, Docker Hub keeps every copied tag. The labels `fedora.version`, `fsuae.version`, `amitools.version` and `aros.version` show what an image holds:

```sh
podman image inspect ghcr.io/pulchart/amiga-fsuae-aros:latest --format '{{json .Labels}}'
```

`amiga-fsuae-aros` has no `L:pfs3-handler`, so a PFS3 handler under test is the only one. `$AROS` is the system directory, the ROM halves are in `$AROS/boot/amiga`.

## Versions

`FEDORA_VERSION` and `AROS_DATE` are pinned in the `Containerfile`. Renovate keeps one pull request with all updates and refreshes it daily between 4 and 8 UTC, after SourceForge has the night's AROS build. Fedora releases come from endoflife.date, so no prerelease.

FS-UAE (RPM Fusion) and amitools (PyPI) take their newest release at every build. Tags and labels come from the versions found in the image.

SourceForge drops nightlies after a few days, so merge the Renovate pull request while its nightly is there. A nightly without an amiga-m68k build fails with "has no amiga-m68k boot ISO" until Renovate moves on. The build checks the archive against the MD5 SourceForge publishes.

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

## Build

```sh
podman build --target base -t amiga-fsuae .
podman build --target aros -t amiga-fsuae-aros .
podman build --target test .    # boots AROS, checks it ran its Startup-Sequence
```

| workflow | when | does |
|---|---|---|
| `Images` | pull request | lint, build, `test` stage; a pull request from this repository also pushes `amiga-fsuae-pr:pr-<number>` and `amiga-fsuae-aros-pr:pr-<number>`, closing it deletes them |
| | `master`, manual on `master` | also tags, pushes to GHCR with `GITHUB_TOKEN`, attests provenance, keeps 10 versions |
| `Copy to Docker Hub` | manual, owner, `master` | copies `latest` and the version tags with `skopeo sync`; the only user of the Docker Hub token |

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
