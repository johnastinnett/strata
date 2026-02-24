# Strata — World State Migration Framework for Roblox

## Overview

Strata is an append-only, source-controlled migration framework for managing Roblox world state. It brings database-migration principles to 3D world building: every change to the world — whether scripted generation or a hand-placed Studio edit — is captured as an immutable, ordered migration with explicit dependencies.

Strata sits alongside Rojo, Wally, Selene, and Stylua in the modern Roblox toolchain.

---

## Core Principles

### 1. Origin Must Be Scripted

Every Strata project begins with migration `0001_origin`, which must be a `script` type. Even if the starting world is a single Part, it must be emitted by code. This guarantees:

- The system is self-bootstrapping with no manual setup prerequisites.
- Every project has a deterministic, reproducible root.
- The migration chain always has a verifiable starting point.

### 2. Append-Only / Fix-Forward

Migrations are immutable once committed. There is no rebase, no editing history. If migration `0003` introduced a bug, the fix lives in `0009`. The history is a permanent, ordered log of every change ever made to the world.

This is not a guideline — it is enforced by the framework's git hooks at push time.

### 3. Dependency Graph via Tags

Every migration:

- **Declares dependencies** on one or more tags emitted by previous migrations.
- **Emits one or more tags** that downstream migrations can depend on.

Exception: `0001_origin` has no dependencies and emits the root tag(s).

The migration chain forms a **directed acyclic graph (DAG)**, not a flat list. The runtime resolves migrations in topological order. Cycles are a hard error.

### 4. Delta Over Snapshot

Migrations describe **what changed**, not what the world looks like after. Each migration contains only the objects it introduces, modifies, or removes. This provides:

- Smaller storage footprint.
- Composability — each migration's impact is independently understandable.
- Merge-friendliness — parallel work on different zones won't conflict.
- Auditability — trace any object's existence by walking the dependency chain.

### 5. The Manifest Is Law

The committed `strata-manifest.toml` is the single source of truth. It tracks every migration, its type, its dependencies, and its emitted tags. What is in the repository is final. Merge conflicts on the manifest are the designed mechanism for flagging when developers step on each other's tags during active development.

### 6. No Orphans

Every `.rbxmx` asset file in the project must have a corresponding migration entry in the manifest. Every migration must declare at least one dependency (except `0001_origin`) and emit at least one tag. Violations are hard errors enforced by git hooks and runtime validation.

---

## Migration Types

### `script`

A Luau ModuleScript that receives a context object and performs world mutations — creating Parts, modifying Terrain, destroying objects, etc.

```luau
-- strata/migrations/0003_terrain.luau
local Migration = {}

function Migration.up(context: Strata.MigrationContext)
    -- context.workspace: reference to workspace or target container
    -- context.tags: resolved tag registry (read previous tags' outputs)
    -- context.emit: function to register emitted tag data

    local terrain = context.workspace.Terrain
    terrain:FillBlock(
        CFrame.new(0, -5, 0),
        Vector3.new(500, 10, 500),
        Enum.Material.Grass
    )

    context.emit("terrain", {
        surfaceY = 0,
        radius = 250,
    })
end

return Migration
```

### `asset`

A `.rbxmx` file exported from Roblox Studio, representing a delta — only the objects this migration introduces or modifies. Accompanied by a metadata block in the manifest.

Asset migrations can also declare **removals** — objects from prior migrations that this asset replaces.

### `remove`

A lightweight migration type that only destroys/removes objects emitted by a previous tag. Used when a scripted or asset migration needs to clean up prior state without introducing new geometry.

---

## Manifest Format

The manifest is the authoritative ledger. It lives at the project root as `strata-manifest.toml`.

```toml
[strata]
version = "0.1.0"
schema_version = 1

# Tracking: which migrations have been applied to the current place.
# This section is updated by the runtime after applying migrations.
# It is NOT manually edited.
[applied]
last_applied = "0007_trees"
applied_at = "2026-02-24T12:00:00Z"

# --- Migration Definitions (append-only) ---

[[migrations]]
id = "0001_origin"
type = "script"
source = "migrations/0001_origin.luau"
depends = []
emits = ["world_root"]
description = "Bootstrap empty world container"

[[migrations]]
id = "0003_terrain"
type = "script"
source = "migrations/0003_terrain.luau"
depends = ["world_root"]
emits = ["terrain"]
description = "Generate base island terrain and water"

[[migrations]]
id = "0005_sidewalks"
type = "script"
source = "migrations/0005_sidewalks.luau"
depends = ["terrain"]
emits = ["sidewalks"]
description = "Generate walkway paths between zones"

[[migrations]]
id = "0007_trees"
type = "script"
source = "migrations/0007_trees.luau"
depends = ["terrain", "sidewalks"]
emits = ["trees"]
description = "Generate procedural tree placement"

[[migrations]]
id = "0012_tree_mesh_swap"
type = "asset"
source = "migrations/assets/0012_tree_mesh_swap.rbxmx"
depends = ["trees"]
emits = ["trees_v2"]
removes = ["trees"]
description = "Replace procedural cylinder trees with mesh models from Creator Store"
```

### Numbering Convention

Migration IDs use zero-padded numbers with a descriptive suffix: `NNNN_description`. Numbers do not need to be sequential — gaps are expected and encouraged (similar to database migrations using increments of 10). This leaves room for inserting migrations between existing ones during development.

---

## Runtime Behavior

### Incremental Application

Strata uses incremental migration application. The runtime tracks which migrations have already been applied to the current place via the `[applied]` section of the manifest.

On server start:

1. Read `strata-manifest.toml`.
2. Resolve the dependency DAG.
3. Determine which migrations are new (not yet in `[applied]`).
4. Apply new migrations in topological order.
5. Update the `[applied]` tracking state.

This means the first server start after a fresh place runs the full chain. Subsequent starts only apply new migrations added since the last run.

### Tag Registry

The tag registry is a runtime key-value store. When a migration calls `context.emit("terrain", data)`, the tag `"terrain"` becomes available to all downstream migrations via `context.tags["terrain"]`.

Tag data is serialized and persisted alongside the applied-migration tracking so that future incremental runs can resolve dependencies without re-executing already-applied migrations.

### Topological Ordering

Migrations are applied in topological order of the dependency DAG, not by ID number. ID numbers suggest intent and reading order, but the DAG is authoritative. If `0012` depends only on `0003`, it can run before `0007` (assuming `0007` depends on `0005` which isn't ready yet).

### Validation

Before applying any migration, the runtime validates:

- All declared dependencies resolve to previously emitted tags.
- No dependency cycles exist.
- No duplicate tag emissions (a tag can only be emitted once across the entire chain).
- For `asset` migrations: the referenced `.rbxmx` file exists.
- For `remove` migrations: the referenced tags exist and were previously emitted.

Validation failures halt the migration chain and surface a clear error identifying the failing migration and the specific violation.

---

## Git Hook Enforcement

Strata ships with git hooks that enforce framework invariants at push time. These are installed automatically when the project is initialized.

### pre-push Hook

Validates the manifest on every push:

1. **No history rewrites.** Compares the local manifest against the remote. Any modification to an existing migration entry (changed dependencies, changed source path, changed emitted tags) is rejected.
2. **No orphaned assets.** Every `.rbxmx` file under the migrations directory must have a corresponding `[[migrations]]` entry.
3. **No missing assets.** Every `type = "asset"` migration must reference an existing file.
4. **Dependency integrity.** All `depends` entries resolve to tags emitted by earlier migrations. No cycles.
5. **Tag uniqueness.** No two migrations emit the same tag.
6. **Origin rule.** `0001_origin` must exist, must be `type = "script"`, and must have `depends = []`.

### Merge Conflict as Feature

When two developers add migrations that emit the same tag, or when both append to the manifest simultaneously, git's merge conflict on `strata-manifest.toml` is the intended signaling mechanism. This is by design — it forces developers to reconcile their world changes explicitly.

---

## Project Structure

```
my-roblox-game/
  strata-manifest.toml
  strata/
    migrations/
      0001_origin.luau
      0003_terrain.luau
      0005_sidewalks.luau
      0007_trees.luau
      assets/
        0012_tree_mesh_swap.rbxmx
    lib/
      Strata.luau          -- Runtime: manifest parser, DAG resolver, migration runner
      StrataTypes.luau      -- Type definitions
      StrataTags.luau       -- Tag registry implementation
      StrataValidation.luau -- Validation logic (shared by runtime + hooks)
    hooks/
      pre-push             -- Git hook script
    cli/
      strata-init.luau     -- Initialize a new Strata project
      strata-new.luau      -- Scaffold a new migration
      strata-validate.luau -- Run validation without applying
      strata-status.luau   -- Show applied vs pending migrations
```

---

## CLI Commands

### `strata init`

Initializes a new Strata project in the current directory. Creates the manifest, directory structure, git hooks, and scaffolds `0001_origin`.

### `strata new <name> [--type=script|asset]`

Scaffolds a new migration with the next available ID. Creates the source file and appends the entry to the manifest.

For `asset` type, creates a placeholder `.rbxmx` entry and prints instructions for exporting from Studio.

### `strata validate`

Runs the full validation suite against the manifest without applying anything. Used in CI pipelines and local development.

### `strata status`

Shows which migrations have been applied, which are pending, and the current state of the tag registry.

### `strata apply`

Manually triggers migration application (for development/testing outside of live server startup).

---

## Integration with Rojo

Strata's `strata/lib/` directory syncs into `ReplicatedStorage.Strata` (or `ServerStorage.Strata` depending on the project's security model) via the standard Rojo project file. The migration runner is invoked from a server Script that runs on game start.

Example Rojo integration in `default.project.json`:

```json
{
  "tree": {
    "ServerStorage": {
      "Strata": {
        "$path": "strata/lib"
      },
      "StrataMigrations": {
        "$path": "strata/migrations"
      }
    }
  }
}
```

The server-side entry point:

```luau
-- src/server/StrataRunner.server.luau
local ServerStorage = game:GetService("ServerStorage")
local Strata = require(ServerStorage.Strata.Strata)

Strata.run({
    migrations = ServerStorage.StrataMigrations,
    target = workspace,
})
```

---

## Integration with Wally

Strata is distributed as a Wally package for easy adoption:

```toml
# wally.toml
[dependencies]
Strata = "stinnettserver/strata@0.1.0"
```

The CLI tools are distributed separately (likely as a standalone binary or Lune script) since they operate outside the Roblox runtime.

---

## Future Considerations

### Branching / Environments

Migration chains could support named branches for development vs. staging vs. production world states. Out of scope for v0.1 but the DAG structure supports it naturally.

### Rollback Snapshots

While migrations are fix-forward only, the framework could periodically snapshot the world state after applying N migrations, enabling faster cold starts by loading a snapshot and only replaying recent migrations.

### Studio Plugin

A Roblox Studio plugin that integrates with Strata to:

- Automatically scaffold `asset` migrations when exporting selections.
- Visualize the migration DAG.
- Show which objects in the world came from which migration.
- Run `strata validate` and `strata status` from within Studio.

### Collaborative Workflows

Patterns for teams working on the same world simultaneously — zone ownership conventions, tag namespacing, manifest section locking.

---

## Design FAQ

**Q: Why not just use Rojo and source control directly?**
A: Rojo syncs files to instances. It doesn't track the *history* of how the world was built, enforce dependency ordering, or provide a framework for mixing scripted generation with manual edits. Strata sits on top of Rojo — it uses Rojo for syncing its own source files.

**Q: Why TOML for the manifest?**
A: Human-readable, diff-friendly, and consistent with the Roblox ecosystem (Wally uses TOML). Merge conflicts are clearly visible.

**Q: Why not sequential numbering?**
A: Gaps allow inserting migrations between existing ones during development without renumbering. This matches established database migration conventions.

**Q: What happens if a migration fails mid-execution?**
A: The framework halts, logs the error with the migration ID and failure context, and does not update the applied tracking. The next server start will re-attempt the failed migration. Migrations should be written to be idempotent where possible to handle this case cleanly.

**Q: Can I run Strata in a local Studio test session?**
A: Yes. The runtime detects the environment and operates the same way. The `[applied]` tracking resets each Studio session (since there's no persistent place state), so the full chain re-applies — but this is desirable for testing.
