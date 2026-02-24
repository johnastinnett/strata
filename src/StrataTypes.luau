--!strict
-- StrataTypes: All type definitions for the Strata migration framework.

local StrataTypes = {}

-- The type of migration. Phase 1 only supports "script".
export type MigrationType = "script"

-- A single entry in the manifest's migrations array.
export type MigrationEntry = {
  id: string,
  type: MigrationType,
  depends: { string },
  emits: { string },
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
