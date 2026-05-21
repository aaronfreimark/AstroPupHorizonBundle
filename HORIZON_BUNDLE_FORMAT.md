# `.horizon` Bundle Format — v1

A `.horizon` is a **file-system package** (Finder treats it as an opaque
file, but it's really a directory). The format is designed to be:

- **Portable.** Any program that can read JSON + PNG + JPEG can read
  the parts that matter to it. No proprietary blobs.
- **Sparsely populated.** A bundle may have any subset of `{horizon
  data, panoramas, source frames}`. Consumers must check before reading.
- **Single source of truth.** Every piece of bundle metadata (name,
  capture date, location, etc.) lives in exactly one place inside
  `bundle.json`. No duplicated fields.
- **Versioned.** `bundle.json::formatVersion` declares the schema
  version. This doc describes v1.

The package's directory name is treated as opaque storage. The
user-visible identity lives in `bundle.json::name`.

## Layout

```
MyHorizon.horizon/
├── bundle.json         # REQUIRED — all metadata + horizon + pano + frame manifests
├── pano-photo.png      # optional — listed in bundle.json::panos[]
├── pano-synthetic.png  # optional — additional pano, listed in bundle.json::panos[]
├── frames/             # optional — source-frame subdirectory
│   ├── 0001.jpg        # listed in bundle.json::frames[]
│   ├── 0002.jpg
│   └── …
└── undo.json           # optional — editor's undo history; opaque to other apps
```

Any file outside this list should be tolerated (ignored) by readers,
to leave room for forward-compatible extensions.

---

## `bundle.json` (required)

The single source of truth for everything *about* the bundle and for
the structured data (horizon points, pano manifests, frame manifests).
Binary assets (panos, frame JPEGs) live as sibling files; this file
indexes them.

```json
{
  "formatVersion": 1,
  "id": "F1B2A3C4-D5E6-7890-1234-56789ABCDEF0",
  "name": "Brooklyn Heights",
  "capturedAt": "2025-09-15T10:30:00Z",
  "modifiedAt": "2025-09-15T10:35:12Z",
  "captureLocation": {
    "latitude": 40.6962,
    "longitude": -73.9961,
    "elevation": 12.5
  },
  "compassOffsetDegrees": 12.3,
  "appVersion": "ExampleApp 1.0 (1)",

  "horizon": {
    "points": [
      { "azimuth": 0,  "altitude": 12.3 },
      { "azimuth": 1,  "altitude": 12.5 },
      { "azimuth": 15, "altitude": 18.1 }
    ]
  },

  "panos": [
    {
      "filename": "pano-photo.png",
      "kind": "photo",
      "projection": "equirectangular",
      "altitudeMin": -5.0,
      "altitudeMax": 90.0
    },
    {
      "filename": "pano-synthetic.png",
      "kind": "synthetic",
      "projection": "equirectangular",
      "altitudeMin": 0.0,
      "altitudeMax": 90.0
    }
  ],

  "frames": [
    {
      "filename": "0001.jpg",
      "capturedAt": "2025-09-15T10:30:01.234Z",
      "azimuth": 0.5,
      "altitude": 12.0
    },
    {
      "filename": "0002.jpg",
      "capturedAt": "2025-09-15T10:30:01.434Z",
      "azimuth": 15.0,
      "altitude": 11.8
    }
  ]
}
```

### Top-level metadata fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `formatVersion` | integer | yes | `1` for this spec. Bump on breaking changes. |
| `id` | string (UUID) | no\* | Stable per-bundle identifier. Assigned at create time, never changes. Survives renames, directory moves, and cross-device iCloud syncs of the same bundle. \*Optional in the spec for backward compatibility with bundles written before this field existed; readers should treat absence as "legacy" and consider falling back to directory-name matching. Writers MUST emit it on all new bundles and SHOULD auto-fill on first save of any legacy bundle they modify. |
| `name` | string | yes | User-visible name. Single source of truth. |
| `capturedAt` | RFC3339 timestamp | no | When source frames were shot. Immutable after capture. Absent for bundles authored without a capture event (e.g. HRZ imports). |
| `modifiedAt` | RFC3339 timestamp | no | Last modification. Writers SHOULD set this on every save when known; readers MUST tolerate absence (HRZ imports, etc.). |
| `captureLocation.latitude` / `.longitude` | number | no | Decimal degrees, WGS84. Absent if location wasn't available. |
| `captureLocation.elevation` | number | no | Height above mean sea level, in meters. Optional; many writers don't have this. Useful for atmospheric refraction correction in consumers that compute apparent vs. true altitudes. |
| `compassOffsetDegrees` | number | no | Degrees to add to AR-session-local azimuths to recover true-north azimuths. Captured once at session start; never updated. Absent on bundles authored without an AR session. |
| `appVersion` | string | no | Free-form identifier of the writing program. Diagnostic only. |
| `horizon` | object | no | Horizon points; absent or null when not yet analyzed. |
| `panos` | array | no | Pano manifests; absent or empty when no panos. |
| `frames` | array | no | Source-frame manifests; absent or empty when no frames. |

Readers MUST:
- Refuse to open bundles with `formatVersion > 1`.
- Tolerate unknown extra top-level fields (forward compat).
- Use UTF-8 throughout.

Writers MUST update `modifiedAt` on every save when they know it.
`capturedAt` never changes after the bundle is created.

---

### `horizon` (optional)

The horizon altitude points. Absent or null when the bundle has been
captured but not analyzed, or when no horizon data is yet known.

```json
"horizon": {
  "points": [
    { "azimuth": 0,  "altitude": 12.3 },
    { "azimuth": 1,  "altitude": 12.5 },
    { "azimuth": 15, "altitude": 18.1 }
  ]
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `points` | array | yes (if `horizon` present) | One entry per measured azimuth. May be sparse — see below. May be empty. |
| `points[].azimuth` | integer | yes | Compass azimuth, 0–359°, where 0 = true north. |
| `points[].altitude` | number | yes | Altitude above the *true horizontal* (perpendicular to local gravity), in degrees. Positive = above level horizon; negative = below. Matches ARKit's altitude convention. |

#### Sparse horizons

The array does **not** have to cover all 360 azimuths. A bundle may
contain only 50 measurements — that's still useful. Consumers that
need a full 360-point representation (e.g. planetarium-app exports)
should interpolate or zero-fill explicitly, treating gaps as "no
data" rather than "altitude 0".

The array does not have to be sorted; readers should sort by
`azimuth` themselves. There must not be duplicate `azimuth` values.

---

### `panos` (optional)

Manifest entries for any stitched/rendered 360° panoramas stored in
the bundle. Absent or empty means no panos.

Multiple panos with different `kind` values may coexist (e.g. a
captured `photo` pano *and* a rendered `synthetic` pano). The
display convention is **first entry in `panos[]` is the preferred
default**; consumers may iterate if they want alternatives.

```json
"panos": [
  {
    "filename": "pano-photo.png",
    "kind": "photo",
    "projection": "equirectangular",
    "altitudeMin": -5.0,
    "altitudeMax": 90.0
  }
]
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `filename` | string | yes | Bare filename (no path) of the image file at the bundle root. Writer's choice — by convention `pano-<kind>.png` for clarity, but readers MUST trust this field rather than enumerate the directory. |
| `kind` | string | yes | Open string. Recognised values: `"photo"` (stitched from captured frames), `"synthetic"` (rendered from `horizon.points`). Unknown values: readers should treat as "unknown" rather than reject the bundle. |
| `projection` | string | yes | Open string. Recognised value: `"equirectangular"` (linear in azimuth across the full 360°, linear in altitude across `[altitudeMin, altitudeMax]`). Unknown values: readers may skip displaying this pano but MUST NOT reject the bundle. |
| `altitudeMin` | number | yes | Altitude (degrees) at the bottom edge of the image. |
| `altitudeMax` | number | yes | Altitude (degrees) at the top edge of the image. |

#### Equirectangular projection details

For `projection: "equirectangular"`:
- Horizontal axis: full 360° sweep. `x = 0` represents azimuth 0°
  (true north); the image wraps left-to-right.
- Vertical axis: linear in altitude across `[altitudeMin,
  altitudeMax]`. `y = 0` (top row) represents `altitudeMax`;
  `y = height − 1` (bottom row) represents `altitudeMin`.

#### Pano image files

PNG is the default and supports RGBA. Alpha channel is meaningful —
fully transparent pixels are "sky" or "uncovered seam" regions.
Display code should let whatever background is behind the pano show
through. Other formats (JPEG, etc.) are permitted; readers determine
format from the file itself, not from `filename`'s extension.

---

### `frames` (optional)

Manifest entries for source frames captured during the AR session.
Each entry corresponds to a `.jpg` (or similar) file inside the
`frames/` subdirectory. Absent or empty means no source frames are
kept.

```json
"frames": [
  {
    "filename": "0001.jpg",
    "capturedAt": "2025-09-15T10:30:01.234Z",
    "azimuth": 0.5,
    "altitude": 12.0,
    "camera": {
      "intrinsics": [1328.94, 0, 966.08, 0, 1328.94, 715.07, 0, 0, 1],
      "imageWidth": 518,
      "imageHeight": 1126,
      "cameraBufferWidth": 1920,
      "cameraBufferHeight": 1440,
      "viewportWidth": 402,
      "viewportHeight": 874
    }
  }
]
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `filename` | string | yes | Bare filename, relative to `frames/`. By convention `0001.jpg`, `0002.jpg`, …, but readers MUST trust this field rather than enumerate the directory. |
| `capturedAt` | RFC3339 timestamp | yes | When this individual frame was shot. |
| `azimuth` | number | yes | AR-session-local azimuth of the camera at capture time, degrees. Add `bundle.json::compassOffsetDegrees` to get true-north azimuth. |
| `altitude` | number | yes | Camera pitch at capture time, degrees. |
| `camera` | object | no | Camera-calibration data needed to back-project image pixels to rays. Required for re-running stitching/analysis on the bundle. Writers without a calibrated camera at capture time omit it; readers that don't perform re-projection ignore it. See "`frames[].camera`" below. |

#### `frames[].camera`

| Field | Type | Required (if `camera` present) | Notes |
|---|---|---|---|
| `intrinsics` | array of 9 numbers | yes | 3×3 row-major pinhole-camera intrinsics matrix, in camera-buffer pixel coordinates. Order: `[fx, 0, cx, 0, fy, cy, 0, 0, 1]`. |
| `imageWidth` / `imageHeight` | number | yes | Pixel dimensions of the JPEG file. May be a downsampled view of the camera buffer. |
| `cameraBufferWidth` / `cameraBufferHeight` | number | yes | Pixel dimensions of the original camera sensor buffer that the intrinsics were calibrated against. |
| `viewportWidth` / `viewportHeight` | number | yes | Pixel dimensions of the on-screen viewport at capture time. iOS-specific; not meaningful for non-iOS bundles. Writers from other platforms may set these to image dimensions or omit the `camera` object entirely. |

### Pure source frames

A bundle with `frames[]` populated but no `horizon` and no `panos[]`
is the on-disk form of an un-analyzed capture. Re-running analysis
should populate the `horizon` field and append/replace entries in
`panos[]` without touching `frames[]`.

---

## `undo.json` (optional)

An optional sidecar containing an editing app's per-bundle
undo/redo stack. Opaque to other applications — readers should
ignore unrecognized sidecar files. Kept separate from `bundle.json`
so editor-internal state doesn't churn the publicly-portable parts
on every undo-stack push.

The same pattern (an additional file alongside `bundle.json`)
applies to any app-specific sidecar — favorite-object lists,
annotation layers, etc. The shared schema in `bundle.json` covers
only the cross-app data.

---

## Invariants

The following MUST hold for a bundle to be considered well-formed:

- `bundle.json` is always present and decodes against this schema.
- For every entry in `panos[]`, the file named by `filename` exists
  at the bundle root. Conversely, image files at the bundle root
  not listed in `panos[]` are orphans and MUST be ignored by
  readers (not displayed, not exported).
- For every entry in `frames[]`, the file named by `filename` exists
  at `frames/<filename>`. Conversely, files inside `frames/` not
  listed in `frames[]` are orphans and MUST be ignored.
- A bundle with neither `horizon`, nor `panos[]`, nor `frames[]` is
  technically valid (it's just metadata about *something*) but is
  not useful. Tools may surface this as a warning.

A bundle that violates any of the above is **malformed**. Readers
SHOULD surface a graceful error rather than crashing or producing
incorrect output.

---

## Optionality matrix

Common valid combinations:

| Has frames | Has horizon | Has panos | What it represents |
|---|---|---|---|
| ✓ | ✗ | ✗ | Captured, not yet analyzed |
| ✓ | ✓ | ✓ (photo) | Captured + fully analyzed |
| ✓ | ✓ | ✓ (photo + synthetic) | Same as above, plus a rendered alternative |
| ✗ | ✓ | ✓ (photo) | Analyzed, source frames discarded (export-ready) |
| ✗ | ✓ | ✗ | Pure horizon-line data (e.g. HRZ import; no `capturedAt` / `modifiedAt`) |
| ✗ | ✓ | ✓ (synthetic only) | Authored horizon with a rendered visualization |

---

## File-system conventions

- Bundle directory MUST have the `.horizon` extension. iOS treats
  these as packages (`LSTypeIsPackage`).
- All text files are UTF-8 encoded JSON. Pretty-printing is allowed
  but not required.
- `bundle.json` writes SHOULD be atomic (write to a temp file
  alongside, then `rename` over the target) so a mid-crash never
  leaves the bundle's index inconsistent with its files. Helper
  files (image saves, frame writes) follow whatever atomicity their
  format/filesystem provides.
- Bundle directory names SHOULD track the user-visible
  `bundle.json::name` so the Files app surfaces the same identity
  the user sees in-app. Writers MAY sanitize path-unsafe characters
  (`/`, `:`, `\`, null) and SHOULD disambiguate sibling collisions
  by appending ` 2`, ` 3`, … (e.g. two bundles named "Brooklyn" can
  live as `Brooklyn.horizon` and `Brooklyn 2.horizon` — the counter
  is in the directory name only, not in `bundle.json::name`).
  Renaming a bundle's display name should move its directory to
  match, subject to the same sanitization + collision rules.
- Readers MUST NOT depend on the directory name carrying any
  semantic meaning beyond storage; the source of truth for the
  user-visible identity remains `bundle.json::name`.
