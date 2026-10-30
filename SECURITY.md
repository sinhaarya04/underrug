# Security Policy

## What Underrug can and can't do

Underrug is built to be harmless to your files:

- **Finder (Automation).** Underrug asks Finder for the names and positions of desktop icons, the current selection,
  and to change icon positions. It never asks Finder to move, rename, copy or delete files.
- **Desktop folder (Files and Folders).** Optional. It only lists the Desktop's file names to show a count in the menu.
- **No network.** Underrug makes no network connections.
- **Local state only.** Rug settings live in `UserDefaults` (`com.sinhaarya04.underrug`) and the positions saved by a
  sweep in `~/Library/Application Support/Underrug/swept.json`.

If you find Underrug doing anything outside that list, please treat it as a security issue.

## Supported versions

Only the latest release gets fixes.

## Reporting a vulnerability

Please report privately through GitHub:
[**Report a vulnerability**](https://github.com/sinhaarya04/underrug/security/advisories/new). Don't open a public
issue.

You can expect an acknowledgement within a week. Once a fix ships, the advisory will be published with credit to you
unless you'd rather stay anonymous.
