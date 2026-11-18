# Attribution and distribution notice

## No Microsoft material is bundled

This repository contains **no Windows installation media, no ADK executables,
no drivers, and no Microsoft binaries of any kind**. It consists only of text:
PowerShell scripts, JSON recipes, templates and documentation.

You must supply your own lawfully obtained Windows 11 installation ISO.
Downloading, installing and activating Windows remain subject to
[Microsoft's license terms](https://www.microsoft.com/en-us/legal/windows/agreements).
Nothing here bypasses activation, modifies `setup.exe`, or changes the Windows kernel.

## Relationship to tiny11

The idea of a script-driven, user-supplied-image builder is inspired by
[ntdevlabs/tiny11builder](https://github.com/ntdevlabs/tiny11builder) by NTDEV.
That project's own notice states that Windows installation media and ADK
executables are not bundled and that Windows use remains subject to Microsoft's
terms. We follow the same model: distribute the tool, not the image.

No source code from tiny11builder is copied into this package; the implementation
here was written from scratch for a Russian-language Pro image and the aeroOS branding.

## Third-party software

The build scripts download the following at build time **from their official
endpoints**, verify hashes where a stable hash is available, and embed them into
the image you build on your own machine:

| Component | Official source | License |
| --- | --- | --- |
| Node.js | nodejs.org | MIT |
| Eclipse Temurin JDK | adoptium.net / GitHub releases | GPLv2 + Classpath Exception |
| Google Chrome Enterprise | dl.google.com | Google Chrome Terms |
| Git for Windows | github.com/git-for-windows | GPLv2 |
| Python | python.org | PSF License |
| Visual Studio Code | update.code.visualstudio.com | MIT (product license applies to binaries) |
| ExplorerPatcher | github.com/valinet/ExplorerPatcher | GPLv3 |

No installer is stored in this repository. Redistribution of those installers is
governed by each vendor's own license — read them before sharing anything.
ExplorerPatcher is distributed as an unsigned executable by its author; the
scripts report that fact and it can be disabled with `-NoExplorerPatcher`.

## Trademarks

aeroOS is an unofficial hobby branding applied on top of Windows. It is not a
Microsoft product and is not affiliated with, endorsed by or supported by
Microsoft Corporation. Windows, Edge, Defender and Explorer are trademarks of
Microsoft. Apple is not affiliated with this project either; no Apple artwork
is included.

## No warranty

THE SCRIPTS ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND. Modifying a
Windows image can break updates, recovery, drivers or applications. Always test
the resulting ISO in a virtual machine before using it on real hardware. Keep
your original ISO and a recoverable backup.

## What you may publish

- ✅ These scripts, recipes, docs and your own configuration changes
- ✅ Screenshots, logs, build instructions
- ❌ The resulting ISO or WIM containing Windows
- ❌ ISO images with Defender/Edge removed, even "for personal use" shared publicly
- ❌ Any image containing activation cracks or bypasses (never included here)
