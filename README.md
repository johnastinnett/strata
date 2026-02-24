# Strata

Append-only world state migration framework for Roblox.

Strata brings database-migration principles to 3D world building. Every change to your game world — scripted generation or hand-placed Studio edits — is captured as an immutable, ordered migration with explicit dependencies.

**Status:** Specification phase. See [SPEC.md](SPEC.md) for the full design.

## Quick Concept

```
0001_origin (script)        → emits: "world_root"
0003_terrain (script)       → depends: ["world_root"]          → emits: "terrain"
0005_sidewalks (script)     → depends: ["terrain"]              → emits: "sidewalks"
0007_trees (script)         → depends: ["terrain", "sidewalks"] → emits: "trees"
0012_tree_mesh_swap (asset) → depends: ["trees"]                → emits: "trees_v2"
```

- Migrations are **immutable** once committed. Fix forward, never rewrite.
- Dependencies form a **DAG** — the framework resolves and validates topological order.
- **Scripts** and **Studio assets** are both first-class migration types.
- The committed **manifest is law**. Merge conflicts are the signaling mechanism.
- Ships with **git hooks** that enforce all invariants at push time.

## Ecosystem

Strata is designed to sit alongside Rojo, Wally, Selene, and Stylua in the modern Roblox toolchain.
