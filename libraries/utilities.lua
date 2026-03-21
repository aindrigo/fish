fish.utilities = fish.utilities or {}

--- merges 2 tables
--- @param source table
--- @param target table
--- @return table
function fish.utilities.Merge(source, target)
    local function visit(treeSource, treeTarget)

        for key, value in pairs(treeTarget) do
            if istable( value ) then
                visit( treeTarget, value )
            else
                treeSource[key] = value
            end
        end

    end

    visit(source, target)
    return source
end

--- merges 2 tables, similar to table.Inherit but recursive & does not set BaseClass
--- @param source table
--- @param dest table
--- @return table
function fish.utilities.Inherit(source, dest)
    for key, value in pairs(source) do
        if dest[key] == nil then
            dest[key] = value
        end

        if istable(value) and istable(dest[key]) then
            dest[key] = fish.utilities.Inherit( value, dest[key] )
        end
    end

    return dest
end

--- defines members of the table as hooks
--- @param tbl table
--- @param parent? table passed as self to hook
--- @return table<table<string, string>> registered hooks
function fish.utilities.DefineHooks(tbl, parent)
    local hooks = {}
    parent = parent or tbl
    for key, value in pairs(tbl) do
        if not isfunction(value) then continue end

        local debugInfo = debug.getinfo(value, "S")
        local name = debugInfo.short_src .. "_" .. key
        hook.Add(key, name, function(...) return tbl[key](parent, ...) end)

        hooks[key] = name
    end

    return hooks
end
