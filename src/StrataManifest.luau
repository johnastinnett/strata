--!strict
-- StrataManifest: Manifest loading and structural normalization.

local StrataTypes = require(script.Parent.StrataTypes)

type MigrationEntry = StrataTypes.MigrationEntry
type ManifestData = StrataTypes.ManifestData

local StrataManifest = {}

local SUPPORTED_TYPES: { [string]: boolean } = {
  script = true,
}

local function validateEntry(entry: any, index: number): MigrationEntry
  if type(entry) ~= "table" then
    error(`[Strata] Migration at index {index} must be a table.`)
  end

  local raw = entry :: { [string]: any }

  if type(raw.id) ~= "string" or raw.id == "" then
    error(`[Strata] Migration at index {index} is missing required field "id".`)
  end

  local id = raw.id :: string

  if type(raw.type) ~= "string" then
    error(`[Strata] Migration "{id}" is missing required field "type".`)
  end

  if not SUPPORTED_TYPES[raw.type :: string] then
    error(
      `[Strata] Migration "{id}" has unsupported type "{raw.type}". Phase 1 only supports "script".`
    )
  end

  if type(raw.depends) ~= "table" then
    error(`[Strata] Migration "{id}" is missing required field "depends" (array of strings).`)
  end

  for i, dep in ipairs(raw.depends :: { any }) do
    if type(dep) ~= "string" then
      error(`[Strata] Migration "{id}" depends[{i}] must be a string, got {type(dep)}.`)
    end
  end

  if type(raw.emits) ~= "table" then
    error(`[Strata] Migration "{id}" is missing required field "emits" (array of strings).`)
  end

  local emits = raw.emits :: { any }
  if #emits == 0 then
    error(`[Strata] Migration "{id}" must emit at least one tag.`)
  end

  for i, tag in ipairs(emits) do
    if type(tag) ~= "string" then
      error(`[Strata] Migration "{id}" emits[{i}] must be a string, got {type(tag)}.`)
    end
  end

  if type(raw.description) ~= "string" then
    error(`[Strata] Migration "{id}" is missing required field "description".`)
  end

  return {
    id = id,
    type = raw.type :: StrataTypes.MigrationType,
    depends = raw.depends :: { string },
    emits = raw.emits :: { string },
    description = raw.description :: string,
  }
end

function StrataManifest.parse(raw: ManifestData): { MigrationEntry }
  if type(raw) ~= "table" then
    error("[Strata] Manifest must be a table.")
  end

  local manifest = raw :: { [string]: any }

  if type(manifest.version) ~= "string" or (manifest.version :: string) == "" then
    error('[Strata] Manifest is missing "version" field.')
  end

  if type(manifest.migrations) ~= "table" then
    error('[Strata] Manifest "migrations" must be a non-empty array.')
  end

  local rawMigrations = manifest.migrations :: { any }
  if #rawMigrations == 0 then
    error('[Strata] Manifest "migrations" must be a non-empty array.')
  end

  local entries: { MigrationEntry } = {}
  local seenIds: { [string]: number } = {}

  for index, rawEntry in ipairs(rawMigrations) do
    local entry = validateEntry(rawEntry, index)

    if seenIds[entry.id] then
      error(`[Strata] Duplicate migration id "{entry.id}" found at index {index}.`)
    end
    seenIds[entry.id] = index

    table.insert(entries, entry)
  end

  return entries
end

return StrataManifest
