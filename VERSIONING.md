# Versioning & Release Naming

Canonical version is **semver** `MAJOR.MINOR.PATCH+BUILD` in `pubspec.yaml`. The
number is the source of truth (drives the update feed comparison + `releases/{version}/`
asset path). The **codename** is cosmetic identity only — it never enters comparison.

## What bumps each position (automated by commit type)

| Position | Bumps on | Commit prefix |
|----------|----------|---------------|
| **PATCH** `0.0.X` | bug fix, tweak, hotfix | `fix:` |
| **MINOR** `0.X.0` | feature, notable rollout | `feat:` |
| **MAJOR** `X.0.0` | **public launch only — manual** | `--launch` |

- Positions are independent integers — **no odometer carry** (`0.0.9` + fix → `0.0.10`).
- A higher bump resets everything to its right (`0.4.3` + feat → `0.5.0`).
- `+BUILD` increments on every release for unique, orderable assets.
- **Pre-1.0 (`MAJOR == 0`)**: a breaking change only bumps MINOR (0.x may break);
  MAJOR is frozen at 0. `0.x` means *not yet shown to the world*.
- The `0.x → 1.0.0` jump **is** the public launch — a deliberate human command,
  never triggered by a commit.

## Codename ladder (Apple-style — name rides the MAJOR line)

Theme: **major Indian cargo ports** (where weighbridges actually run). The name
stays constant across all minors/patches of a major, like macOS 15.x = "Sequoia".

| Major | Port codename |
|-------|---------------|
| 1.x | **Mundra** |
| 2.x | Kandla |
| 3.x | Vizag |
| 4.x | Paradip |
| 5.x | Tuticorin |
| 6.x | Haldia |

Public display: `Tulanam 1.0 "Mundra"` (number = truth, name = identity). Compact: `Tulanam · Mundra`.

## Cutting a release

```bash
tool/bump_version.sh            # dry-run: shows the bump it would make from commits
tool/bump_version.sh --apply    # writes pubspec, commits, tags vX.Y.Z
git push && git push origin vX.Y.Z   # the tag triggers .github/workflows/release.yml
#   -> build -> upload releases/{version}/ -> onReleaseUploaded writes global/app_version
```

Going public (one time): `tool/bump_version.sh --launch --apply` → `1.0.0 "Mundra"`.

> Day-to-day, just write `feat:` / `fix:` commits and the version decides itself.
