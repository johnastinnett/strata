--!strict
-- StrataValidation: DAG validation for the migration graph.

local StrataTypes = require(script.Parent.StrataTypes)

type MigrationEntry = StrataTypes.MigrationEntry

local StrataValidation = {}

local function validateOriginRule(entries: { MigrationEntry })
  local hasOrigin = false
  for _, entry in ipairs(entries) do
    if string.match(entry.id, "^0001_") then
      hasOrigin = true
      if entry.type ~= "script" then
        error(`[Strata] Origin migration "{entry.id}" must have type "script".`)
      end
      if #entry.depends > 0 then
        error(`[Strata] Origin migration "{entry.id}" must have no dependencies.`)
      end
      break
    end
  end

  if not hasOrigin then
    error(
      '[Strata] No origin migration found. The manifest must contain a migration with id starting with "0001_".'
    )
  end
end

local function validateTagUniqueness(entries: { MigrationEntry })
  local tagToEmitter: { [string]: string } = {}

  for _, entry in ipairs(entries) do
    for _, tag in ipairs(entry.emits) do
      local existingEmitter = tagToEmitter[tag]
      if existingEmitter then
        error(
          `[Strata] Tag "{tag}" is emitted by both "{existingEmitter}" and "{entry.id}". Tags must be globally unique.`
        )
      end
      tagToEmitter[tag] = entry.id
    end
  end
end

local function validateDependencyResolution(entries: { MigrationEntry })
  -- Build set of all emitted tags.
  local allEmittedTags: { [string]: boolean } = {}
  local entryEmits: { [string]: { [string]: boolean } } = {}

  for _, entry in ipairs(entries) do
    local emitSet: { [string]: boolean } = {}
    for _, tag in ipairs(entry.emits) do
      allEmittedTags[tag] = true
      emitSet[tag] = true
    end
    entryEmits[entry.id] = emitSet
  end

  for _, entry in ipairs(entries) do
    local ownEmits = entryEmits[entry.id]
    for _, dep in ipairs(entry.depends) do
      -- Check self-dependency first (more specific error).
      if ownEmits[dep] then
        error(`[Strata] Migration "{entry.id}" depends on its own emitted tag "{dep}".`)
      end
      if not allEmittedTags[dep] then
        error(
          `[Strata] Migration "{entry.id}" depends on tag "{dep}" which is not emitted by any migration.`
        )
      end
    end
  end
end

local function validateNoCycles(entries: { MigrationEntry })
  -- Build tag-to-emitter map.
  local tagToEmitter: { [string]: string } = {}
  for _, entry in ipairs(entries) do
    for _, tag in ipairs(entry.emits) do
      tagToEmitter[tag] = entry.id
    end
  end

  -- Build migration-to-migration adjacency and in-degrees.
  local inDegree: { [string]: number } = {}
  local dependents: { [string]: { string } } = {}

  for _, entry in ipairs(entries) do
    if inDegree[entry.id] == nil then
      inDegree[entry.id] = 0
    end
    if dependents[entry.id] == nil then
      dependents[entry.id] = {}
    end
  end

  for _, entry in ipairs(entries) do
    -- Deduplicate dependency sources (multiple depends tags may point to the same migration).
    local seenSources: { [string]: boolean } = {}
    for _, dep in ipairs(entry.depends) do
      local sourceId = tagToEmitter[dep]
      if sourceId and not seenSources[sourceId] then
        seenSources[sourceId] = true
        inDegree[entry.id] = (inDegree[entry.id] :: number) + 1
        table.insert(dependents[sourceId] :: { string }, entry.id)
      end
    end
  end

  -- Kahn's algorithm.
  local queue: { string } = {}
  for _, entry in ipairs(entries) do
    if (inDegree[entry.id] :: number) == 0 then
      table.insert(queue, entry.id)
    end
  end

  local processedCount = 0
  local head = 1
  while head <= #queue do
    local current = queue[head]
    head += 1
    processedCount += 1

    for _, dependentId in ipairs(dependents[current] :: { string }) do
      local newDegree = (inDegree[dependentId] :: number) - 1
      inDegree[dependentId] = newDegree
      if newDegree == 0 then
        table.insert(queue, dependentId)
      end
    end
  end

  if processedCount ~= #entries then
    -- Collect the migrations stuck in the cycle.
    local cycleIds: { string } = {}
    for _, entry in ipairs(entries) do
      if (inDegree[entry.id] :: number) > 0 then
        table.insert(cycleIds, entry.id)
      end
    end
    error(
      `[Strata] Dependency cycle detected involving migrations: {table.concat(cycleIds, ", ")}.`
    )
  end
end

function StrataValidation.validate(entries: { MigrationEntry })
  validateOriginRule(entries)
  validateTagUniqueness(entries)
  validateDependencyResolution(entries)
  validateNoCycles(entries)
end

return StrataValidation
