--!strict
-- StrataManifest: Manifest loading and structural normalization.

local StrataTypes = require(script.Parent.StrataTypes)

type MigrationEntry = StrataTypes.MigrationEntry
type ManifestData = StrataTypes.ManifestData

local StrataManifest = {}

local SUPPORTED_TYPES: { [string]: boolean } = {
  script = true,
  asset = true,
  remove = true,
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

  local entryType = raw.type :: string

  if not SUPPORTED_TYPES[entryType] then
    error(`[Strata] Migration "{id}" has unsupported type "{entryType}".`)
  end

  if type(raw.depends) ~= "table" then
    error(`[Strata] Migration "{id}" is missing required field "depends" (array of strings).`)
  end

  for i, dep in ipairs(raw.depends :: { any }) do
    if type(dep) ~= "string" then
      error(`[Strata] Migration "{id}" depends[{i}] must be a string, got {type(dep)}.`)
    end
  end

  -- Validate "emits" field.
  if type(raw.emits) ~= "table" then
    error(`[Strata] Migration "{id}" is missing required field "emits" (array of strings).`)
  end

  local emits = raw.emits :: { any }

  -- script and asset: emits must be non-empty. remove: emits can be empty.
  if (entryType == "script" or entryType == "asset") and #emits == 0 then
    error(`[Strata] Migration "{id}" (type "{entryType}") must emit at least one tag.`)
  end

  for i, tag in ipairs(emits) do
    if type(tag) ~= "string" then
      error(`[Strata] Migration "{id}" emits[{i}] must be a string, got {type(tag)}.`)
    end
  end

  -- Parse optional "removes" field.
  local removes: { string }? = nil
  if raw.removes ~= nil then
    if type(raw.removes) ~= "table" then
      error(`[Strata] Migration "{id}" field "removes" must be an array of strings.`)
    end
    local removesList = raw.removes :: { any }
    for i, tag in ipairs(removesList) do
      if type(tag) ~= "string" then
        error(`[Strata] Migration "{id}" removes[{i}] must be a string, got {type(tag)}.`)
      end
    end
    removes = raw.removes :: { string }
  end

  -- remove type: removes must be non-empty.
  if entryType == "remove" then
    if removes == nil or #(removes :: { string }) == 0 then
      error(`[Strata] Migration "{id}" (type "remove") must declare a non-empty "removes" array.`)
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
    removes = removes,
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
