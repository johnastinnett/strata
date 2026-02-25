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

local function validateRemoves(entries: { MigrationEntry })
  -- Build tag-to-emitter map.
  local tagToEmitter: { [string]: string } = {}
  for _, entry in ipairs(entries) do
    for _, tag in ipairs(entry.emits) do
      tagToEmitter[tag] = entry.id
    end
  end

  -- Collect all tags that get removed and which migration removes them.
  local removedTags: { [string]: string } = {}
  for _, entry in ipairs(entries) do
    local removes = entry.removes
    if removes == nil then
      continue
    end
    for _, tagName in ipairs(removes :: { string }) do
      if not tagToEmitter[tagName] then
        error(
          `[Strata] Migration "{entry.id}" removes tag "{tagName}" which is not emitted by any migration.`
        )
      end
      local existingRemover = removedTags[tagName]
      if existingRemover then
        error(
          `[Strata] Tag "{tagName}" is removed by both "{existingRemover}" and "{entry.id}". A tag may only be removed once.`
        )
      end
      removedTags[tagName] = entry.id
    end
  end

  -- No migration other than the remover may depend on a removed tag.
  for _, entry in ipairs(entries) do
    for _, dep in ipairs(entry.depends) do
      local remover = removedTags[dep]
      if remover and remover ~= entry.id then
        error(
          `[Strata] Migration "{entry.id}" depends on tag "{dep}" which is removed by migration "{remover}". Cannot depend on removed tags.`
        )
      end
    end
  end
end

-- Builds adjacency edges from both depends and removes for cycle detection.
-- Removes create implicit ordering: the remover must run after the emitter.
local function buildEdges(entries: { MigrationEntry })
  local tagToEmitter: { [string]: string } = {}
  for _, entry in ipairs(entries) do
    for _, tag in ipairs(entry.emits) do
      tagToEmitter[tag] = entry.id
    end
  end

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
    local seenSources: { [string]: boolean } = {}

    -- Edges from explicit depends.
    for _, dep in ipairs(entry.depends) do
      local sourceId = tagToEmitter[dep]
      if sourceId and not seenSources[sourceId] then
        seenSources[sourceId] = true
        inDegree[entry.id] = (inDegree[entry.id] :: number) + 1
        table.insert(dependents[sourceId] :: { string }, entry.id)
      end
    end

    -- Implicit edges from removes: remover runs after emitter.
    local removes = entry.removes
    if removes then
      for _, tagName in ipairs(removes :: { string }) do
        local sourceId = tagToEmitter[tagName]
        if sourceId and not seenSources[sourceId] then
          seenSources[sourceId] = true
          inDegree[entry.id] = (inDegree[entry.id] :: number) + 1
          table.insert(dependents[sourceId] :: { string }, entry.id)
        end
      end
    end
  end

  return inDegree, dependents
end

local function validateNoCycles(entries: { MigrationEntry })
  local inDegree, dependents = buildEdges(entries)

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
  validateRemoves(entries)
  validateNoCycles(entries)
end

return StrataValidation
