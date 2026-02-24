--!strict
-- StrataRunner: DAG resolution and sequential migration execution.

local StrataTypes = require(script.Parent.StrataTypes)
local StrataTags = require(script.Parent.StrataTags)

type MigrationEntry = StrataTypes.MigrationEntry
type StrataConfig = StrataTypes.StrataConfig
type TagRegistry = StrataTags.TagRegistry

local StrataRunner = {}

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
    -- Find the migration ModuleScript.
    local moduleInstance = config.migrations:FindFirstChild(entry.id)
    if moduleInstance == nil then
      error(
        `[Strata] Migration ModuleScript not found: no child named "{entry.id}" in the migrations folder.`
      )
    end

    -- Require and validate the module shape.
    local migrationModule = require(moduleInstance :: ModuleScript) :: { [string]: any }
    if type(migrationModule) ~= "table" or type(migrationModule.up) ~= "function" then
      error(`[Strata] Migration "{entry.id}" module does not return a table with an up() function.`)
    end

    -- Build the context.
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

    -- Execute the migration.
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

    print(`[Strata] Applied: {entry.id} -- {entry.description}`)
  end

  print(`[Strata] All {#orderedEntries} migration(s) applied successfully.`)
end

return StrataRunner
