# Preparing a mod release

Use **Actions > Prepare release > Run workflow** from the default branch. Select
`VerdantStamina` and an existing tag in the form `VerdantStamina/vX.Y.Z` or
`VerdantStamina/vX.Y.Z-alpha.N`.

## Prepare sources

1. Finish implementation separately and record actual checks. In-game testing
   and screenshots are currently deferred; keep that limitation in the notes.
2. Update the mod's `VERSION`, `CHANGELOG.md`, `README.md`, runtime startup banner
   in `Scripts/main.lua`, and `release_notes.md` heading together. Packaging and
   the installer read `VERSION`.
3. Review `nexus_description.txt` against the current behavior. Choose Nexus
   permissions consistent with the mod's MIT license and apply the relevant AI
   tags. The description is BBCode for the page, not a file installed in the game.
4. Run these checks from the repository root:

   ```powershell
   New-Item -ItemType Directory -Path build -Force
   python -m pip install -r mods/VerdantStamina/dev/requirements.txt
   python mods/VerdantStamina/dev/test_mod.py
   python mods/VerdantStamina/dev/build.py
   python mods/VerdantStamina/dev/check_release.py --tag VerdantStamina/vX.Y.Z
   python mods/VerdantStamina/dev/test_release.py
   ```

5. Commit the release sources, create an annotated mod-specific tag on that
   commit, then push the commit and that tag. Never move an existing release tag.

The original `VerdantStamina/v0.1.0-alpha.3` tag predates this workflow and release
files. It cannot be prepared by this workflow. Keep that historical snapshot;
prepare a new version/tag containing these files when ready for a release.

## Build a draft

The workflow installs Lua test dependencies on a clean Windows runner, runs the
offline tests, builds the archive, and validates version metadata, archive paths,
documentation and all source hashes. The ZIP includes Lua, procedural masks,
README, MIT license, release notes, enabled.txt and a source manifest. It contains
no loader, development scripts or extracted game assets.

Only successful checks reach draft creation. Prerelease versions are marked as
prereleases. An existing draft or release for the tag is not overwritten.
No personal access token is required; the workflow uses `GITHUB_TOKEN` with
`contents: write`. Repository policy must allow GitHub Actions and this permission.

## Review and publish later

Download and inspect the CI-produced ZIP, test that exact package in game, and
capture screenshots. Review the pending-check statements before publishing.
Publish the GitHub draft manually when ready and upload that same ZIP to Nexus;
GitHub's automatic source archives are not installable mod packages. Nexus
publication and permissions are separate from the GitHub release.

If an upload fails, inspect Releases before retrying: a partial draft may exist.
Remove only the unpublished partial draft after review before retrying. Source
changes require a new version/tag rather than replacing an old tag.
