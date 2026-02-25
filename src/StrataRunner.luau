--!strict
-- StrataRunner: DAG resolution and sequential migration execution.

local StrataTypes = require(script.Parent.StrataTypes)
local StrataTags = require(script.Parent.StrataTags)

type MigrationEntry = StrataTypes.MigrationEntry
type StrataConfig = StrataTypes.StrataConfig
type TagRegistry = StrataTags.TagRegistry

local StrataRunner = {}

-- Destroy Instance references found in tag data.
local function destroyTagContent(tagData: any)
  if typeof(tagData) == "Instance" then
    tagData:Destroy()
  elseif type(tagData) == "table" then
    for _, value in pairs(tagData :: { [any]: any }) do
      if typeof(value) == "Instance" then
        value:Destroy()
      end
    end
  end
end

-- Process removes for a migration: destroy content and remove tags from registry.
local function processRemovals(registry: TagRegistry, entry: MigrationEntry)
  local removes = entry.removes
  if removes == nil then
    return
  end
  for _, tagName in ipairs(removes :: { string }) do
    local tagData = StrataTags.remove(registry, tagName)
    destroyTagContent(tagData)
    print(`[Strata]   Removed tag: {tagName}`)
  end
end

local function executeScript(config: StrataConfig, registry: TagRegistry, entry: MigrationEntry)
  local moduleInstance = config.migrations:FindFirstChild(entry.id)
  if moduleInstance == nil then
    error(
      `[Strata] Migration ModuleScript not found: no child named "{entry.id}" in the migrations folder.`
    )
  end

  local migrationModule = require(moduleInstance :: ModuleScript) :: { [string]: any }
  if type(migrationModule) ~= "table" or type(migrationModule.up) ~= "function" then
    error(`[Strata] Migration "{entry.id}" module does not return a table with an up() function.`)
  end

  -- Process removes before running the script.
  processRemovals(registry, entry)

  local resolvedTags = StrataTags.resolve(registry, entry.depends)
  local declaredEmits: { [string]: boolean } = {}
  for _, tag in ipairs(entry.emits) do
    declaredEmits[tag] = true
  end

  local context: StrataTypes.MigrationContext = {
    target = config.target,
    tags = resolvedTags,
    emit = function(tagName: string, data: any?)
      if not declaredEmits[tagName] then
        error(
          `[Strata] Migration "{entry.id}" attempted to emit undeclared tag "{tagName}". Declared emits: {table.concat(
            entry.emits,
            ", "
          )}.`
        )
      end
      StrataTags.emit(registry, tagName, data)
    end,
  }

  local upFn = migrationModule.up :: (StrataTypes.MigrationContext) -> ()
  upFn(context)

  -- Verify all declared emits were actually emitted.
  for _, declaredTag in ipairs(entry.emits) do
    if not StrataTags.has(registry, declaredTag) then
      error(
        `[Strata] Migration "{entry.id}" declared emit "{declaredTag}" but never called context.emit("{declaredTag}").`
      )
    end
  end
end

local function executeAsset(config: StrataConfig, registry: TagRegistry, entry: MigrationEntry)
  local assetInstance = config.migrations:FindFirstChild(entry.id)
  if assetInstance == nil then
    error(
      `[Strata] Asset migration not found: no child named "{entry.id}" in the migrations folder.`
    )
  end

  if assetInstance:IsA("ModuleScript") then
    error(
      `[Strata] Asset migration "{entry.id}" resolved to a ModuleScript. Asset migrations expect a Model or Folder (from .rbxmx).`
    )
  end

  -- Process removes before inserting new content.
  processRemovals(registry, entry)

  -- Clone children of the asset container into the target.
  local clonedInstances: { Instance } = {}
  for _, child in ipairs(assetInstance:GetChildren()) do
    local clone = child:Clone()
    clone.Parent = config.target
    table.insert(clonedInstances, clone)
  end

  if #clonedInstances == 0 then
    error(
      `[Strata] Asset migration "{entry.id}" has no children to clone. The .rbxmx Instance must contain at least one child.`
    )
  end

  -- Auto-emit tags with cloned instances as data.
  local tagData: any
  if #clonedInstances == 1 then
    tagData = clonedInstances[1]
  else
    tagData = clonedInstances
  end

  for _, tag in ipairs(entry.emits) do
    StrataTags.emit(registry, tag, tagData)
  end
end

local function executeRemove(registry: TagRegistry, entry: MigrationEntry)
  processRemovals(registry, entry)

  -- Emit any optional tags.
  for _, tag in ipairs(entry.emits) do
    StrataTags.emit(registry, tag, true)
  end
end

function StrataRunner.buildOrder(entries: { MigrationEntry }): { MigrationEntry }
  -- Build tag-to-emitter map.
  local tagToEmitter: { [string]: string } = {}
  for _, entry in ipairs(entries) do
    for _, tag in ipairs(entry.emits) do
      tagToEmitter[tag] = entry.id
    end
  end

  -- Build lookup and adjacency.
  local idToEntry: { [string]: MigrationEntry } = {}
  local inDegree: { [string]: number } = {}
  local dependents: { [string]: { string } } = {}

  for _, entry in ipairs(entries) do
    idToEntry[entry.id] = entry
    inDegree[entry.id] = 0
    dependents[entry.id] = {}
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

  -- Kahn's algorithm.
  local queue: { string } = {}
  for _, entry in ipairs(entries) do
    if (inDegree[entry.id] :: number) == 0 then
      table.insert(queue, entry.id)
    end
  end

  local ordered: { MigrationEntry } = {}
  local head = 1
  while head <= #queue do
    local current = queue[head]
    head += 1
    table.insert(ordered, idToEntry[current] :: MigrationEntry)

    for _, dependentId in ipairs(dependents[current] :: { string }) do
      local newDegree = (inDegree[dependentId] :: number) - 1
      inDegree[dependentId] = newDegree
      if newDegree == 0 then
        table.insert(queue, dependentId)
      end
    end
  end

  -- Defensive: validation should have caught cycles, but assert anyway.
  assert(
    #ordered == #entries,
    "[Strata] Internal error: topological sort did not consume all entries."
  )

  return ordered
end

function StrataRunner.execute(config: StrataConfig, orderedEntries: { MigrationEntry })
  local registry = StrataTags.new()

  for _, entry in ipairs(orderedEntries) do
    if entry.type == "script" then
      executeScript(config, registry, entry)
    elseif entry.type == "asset" then
      executeAsset(config, registry, entry)
    elseif entry.type == "remove" then
      executeRemove(registry, entry)
    end

    print(`[Strata] Applied: {entry.id} -- {entry.description}`)
  end

  print(`[Strata] All {#orderedEntries} migration(s) applied successfully.`)
end

return StrataRunner
