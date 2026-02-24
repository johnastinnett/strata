--!strict
-- Strata: Append-only world state migration framework for Roblox.
-- https://github.com/johnastinnett/strata

local StrataTypes = require(script.StrataTypes)
local StrataManifest = require(script.StrataManifest)
local StrataValidation = require(script.StrataValidation)
local StrataRunner = require(script.StrataRunner)

local Strata = {}

-- Re-export types for consumers.
export type MigrationContext = StrataTypes.MigrationContext
export type MigrationModule = StrataTypes.MigrationModule
export type MigrationEntry = StrataTypes.MigrationEntry
export type ManifestData = StrataTypes.ManifestData
export type StrataConfig = StrataTypes.StrataConfig

function Strata.run(config: StrataTypes.StrataConfig)
  if type(config) ~= "table" then
    error("[Strata] Invalid config: expected a table.")
  end
  if type(config.manifest) ~= "table" then
    error("[Strata] Invalid config: manifest must be a table.")
  end
  if typeof(config.migrations) ~= "Instance" then
    error("[Strata] Invalid config: migrations must be an Instance (folder of ModuleScripts).")
  end
  if typeof(config.target) ~= "Instance" then
    error("[Strata] Invalid config: target must be an Instance.")
  end

  local entries = StrataManifest.parse(config.manifest)
  StrataValidation.validate(entries)
  local ordered = StrataRunner.buildOrder(entries)
  StrataRunner.execute(config, ordered)
end

return Strata
