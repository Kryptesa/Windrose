# Verdant Stamina 0.1.0-alpha.4

Release packaging update for the renamed Verdant Stamina alpha. HUD behavior is unchanged.

## Changed

- Include the MIT license and release notes in the installable ZIP.
- Add Nexus page materials and a manual Prepare release workflow.
- Validate version metadata, archive contents and source hashes before draft creation.

## Features

- Smooth concentric stamina rings with paint, hatch and flat surfaces.
- Green permanent capacity and a separate yellow temporary food/buff reserve.
- Gradual low-stamina color warning and configurable scale and smoothing.
- F8 toggle, F9 diagnostics and F10 script/settings reload.

## Installation and updating

Requires the Windows Windrose client and UE4SS 4.0.0, installed separately.
Set the UE4SS engine override to 5.6. Close the game and extract the mod ZIP
into `Windrose/R5/Binaries/Win64`. Back up custom `config.lua` settings before
updates. Remove the old `ue4ss/Mods/WindroseStamina` development folder first;
keep only `VerdantStamina`. See README.md for full instructions and removal.

## Validation and compatibility

All 34 offline Lua model and native-boundary contract tests and 3 release-validator
tests passed locally. The package and its source-manifest hashes were checked.
These tests do not establish actual engine marshalling or multiplayer behavior.
The release workflow repeats the offline checks against the selected tag.

Development targeted an inspected UE 5.6.1 client and UE4SS 4.0.0. A final
in-game installation check of the renamed archive, screenshots, death/respawn,
multiplayer and long-session validation remain pending. No compatibility with
other game builds or loaders is claimed. This is an alpha, not a stable release.
