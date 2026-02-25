--!strict
-- StrataTags: Tag registry for migration data exchange.

local StrataTags = {}

export type TagRegistry = {
  _store: { [string]: any },
}

function StrataTags.new(): TagRegistry
  return {
    _store = {},
  }
end

function StrataTags.emit(registry: TagRegistry, tagName: string, data: any?)
  if registry._store[tagName] ~= nil then
    error(`[Strata] Tag "{tagName}" has already been emitted. Each tag may only be emitted once.`)
  end
  -- Default to true when nil so tags are always truthy.
  if data == nil then
    registry._store[tagName] = true
  else
    registry._store[tagName] = data
  end
end

function StrataTags.resolve(registry: TagRegistry, tagNames: { string }): { [string]: any }
  local snapshot: { [string]: any } = {}
  for _, tagName in ipairs(tagNames) do
    local value = registry._store[tagName]
    if value == nil then
      error(`[Strata] Cannot resolve tag "{tagName}". It has not been emitted yet.`)
    end
    snapshot[tagName] = value
  end
  return table.freeze(snapshot)
end

function StrataTags.has(registry: TagRegistry, tagName: string): boolean
  return registry._store[tagName] ~= nil
end

function StrataTags.remove(registry: TagRegistry, tagName: string): any
  local value = registry._store[tagName]
  if value == nil then
    error(`[Strata] Cannot remove tag "{tagName}". It has not been emitted.`)
  end
  registry._store[tagName] = nil
  return value
end

return StrataTags
