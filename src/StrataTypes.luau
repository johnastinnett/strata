--!strict
-- StrataTypes: All type definitions for the Strata migration framework.

local StrataTypes = {}

export type MigrationType = "script" | "asset" | "remove"

-- A single entry in the manifest's migrations array.
export type MigrationEntry = {
  id: string,
  type: MigrationType,
  depends: { string },
  emits: { string },
  removes: { string }?,
  description: string,
}

-- The shape of the manifest module's return value.
export type ManifestData = {
  version: string,
  migrations: { MigrationEntry },
}

-- The context object passed to each migration's up() function.
export type MigrationContext = {
  target: Instance,
  tags: { [string]: any },
  emit: (tagName: string, data: any?) -> (),
}

-- The contract for a migration ModuleScript's return value.
export type MigrationModule = {
  up: (context: MigrationContext) -> (),
}

-- Configuration passed by the consumer to Strata.run().
export type StrataConfig = {
  manifest: ManifestData,
  migrations: Instance,
  target: Instance,
}

return StrataTypes
