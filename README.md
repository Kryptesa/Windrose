# Windrose

Monorepo for client mods for Windrose. Each mod has independent versions and release tags.

| Mod | Description | Version |
| --- | --- | --- |
| [Verdant Stamina](mods/VerdantStamina/README.md) | Smooth concentric stamina HUD with a separate temporary reserve | 0.1.0-alpha.4 |

## Layout

- `mods/<ModName>/Scripts/` and `Assets/`: files installed through UE4SS.
- `mods/<ModName>/dev/`: development, tests, packaging and installation.
- `mods/<ModName>/VERSION`, `CHANGELOG.md`, `README.md`: independent version and documentation.
- `tools/`, `research/`, `build/`, `dist/`: local dependencies, research and generated outputs; excluded from Git.

## Verdant Stamina development

Run from the repository root with Python and local Lupa/Pillow dependencies in `tools/python`:

```powershell
python mods/VerdantStamina/dev/test_mod.py
python mods/VerdantStamina/dev/build.py
```

See the mod README for installation and remaining live validation limits. When migrating from WindroseStamina, close the game and remove its old mod folder before installing VerdantStamina.

## Versioning

Update each mod's `VERSION` and changelog for its own release. Package and installer read `VERSION`; keep runtime banners and documentation in sync. Release tags use `<ModName>/v<version>` (for example `VerdantStamina/v0.1.0-alpha.4`). Tags identify source snapshots; publication of downloadable releases is separate.

New mods belong in their own `mods/<ModName>/` directory and do not change other mods' versions. Game assets, saves, logs, credentials and third-party executables must stay outside tracked files.

Release preparation uses the manual [Prepare release workflow](.github/workflows/prepare-release.yml).
See [the release guide](docs/releases.md) for tagging, validation and draft review.
Verdant Stamina is [MIT licensed](mods/VerdantStamina/LICENSE); future mods choose their own license.
