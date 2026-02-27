fish.modules = fish.modules or {}
fish.modules.list = fish.modules.list or {}
fish.modules.orderedList = fish.modules.orderedList or {}
fish.modules.hooks = fish.modules.hooks or {}

--- @enum fish.ModuleType
fish.ModuleType = {
    FILE = 0,
    DIRECTORY = 1
}

--- internal: loads the global module tables
--- @param default? table default table to set MODULE to
function fish.modules._Begin(default)
    _G["MODULE"] = default or {}
    _G["HOOKS"] = {}
end

--- internal: gets the global module table
--- @return table module module table
function fish.modules._GetCurrent()
    return _G["MODULE"]
end

--- internal: unloads the global module tables
--- @return table module module table
function fish.modules._End()
    local module = _G["MODULE"]
    _G["MODULE"] = nil

    local hookTable = _G["HOOKS"]
    _G["HOOKS"] = nil

    module.Hooks = module.Hooks or {}
    table.Merge(module.Hooks, hookTable, false)

    return module
end

--- internal: loads a module's metadata by path
--- @param path string
--- @param name? string
--- @return table module
function fish.modules._LoadMetadata(path, name)
    local isDirectory = file.IsDir(path, "LUA")

    local module = {}
    fish.modules._Begin(module)
    fish.Include(isDirectory and path .. "/module.lua" or path, fish.Realm.SHARED)

    module = fish.modules._End()
    if isDirectory then
        module.Id = module.Id or string.GetFileFromFilename(path)
    else
        module.Id = module.Id or string.StripExtension(name or string.GetFileFromFilename(filePath))
    end

    module.Path = path
    module.Type = isDirectory and fish.ModuleType.DIRECTORY or fish.ModuleType.FILE

    return module
end

--- internal: checks if all the dependencies of a module are satisfied
--- @param module table
function fish.modules._CheckModuleDependencies(module)
    if not istable(module.Dependencies) then
        return true, nil
    end

    local moduleNames = {}
    for _, dependencyId in ipairs(module.Dependencies) do
        if istable(fish.modules.list[dependencyId]) then continue end
        table.insert(moduleNames, dependencyId)
    end

    if not table.IsEmpty(moduleNames) then
        error("dependencies for module " .. module.Id .. " not satisfied: " .. table.concat(missingDependencies, ", "))
    end
end

--- @param id string
--- @return table? module
function fish.modules.Get(id)
    return fish.modules.list[id]
end
     
--- internal: loads a module's scripts
--- @param module table
function fish.modules._LoadScripts(module)
    for filePath, fileName in fish.DirectoryIterator(module.Path .. "/libraries", "*.lua", true, true, false) do
        fish.Include(filePath, module.Realm or fish.DetectRealm(fileName, false))
    end

    for filePath, fileName in fish.DirectoryIterator(module.Path .. "/scripts", "*.lua", true, true, false) do
        fish.Include(filePath, module.Realm or fish.DetectRealm(fileName, false))
    end
end

--- internal: (re)loads hooks for a module
--- @param module table
function fish.modules._ReloadHooks(module)
    if istable(module.Hooks) then
        local newHooks = fish.utilities.DefineHooks(module.Hooks, module)
        local oldHooks = fish.modules.hooks[module.Id]
        if istable(oldHooks) then
            for hookName, hookId in pairs(oldHooks) do
                local newHookId = newHooks[hookName]
                if newHookId and newHookId == hookId then continue end

                hook.Remove(hookName, hookId)
            end
        end

        fish.modules.hooks[module.Id] = newHooks
    end
end

--- internal: runs the enabling logic for a module
--- @param module table
--- @param prePost boolean false for pre, true for post
--- @param reloading boolean if the module is enabling or reloading
function fish.modules._DoEnable(module, prePost, reloading)
    if (module.Realm == fish.Realm.CLIENT and not CLIENT) 
        or (module.Realm == fish.Realm.SERVER and not SERVER) then
        return
    end

    if not prePost then
        if reloading and isfunction(module.PreReload) then
            module:PreReload()
        elseif not reloading and isfunction(module.PreEnable) then
            module:PreEnable()
        end
    else
        fish.modules._ReloadHooks(module)

        if reloading and isfunction(module.PostReload) then
            module:PostReload()
        elseif not reloading and isfunction(module.PostEnable) then
            module:PostEnable()
        end
    end
end

--- internal: runs the disabling logic for a module
--- @param module table
--- @param prePost boolean false for pre, true for post
function fish.modules._DoDisable(module, prePost)
    if (module.Realm == fish.Realm.CLIENT and not CLIENT) 
        or (module.Realm == fish.Realm.SERVER and not SERVER) then
        return
    end

    if not prePost then
        for hookName, hookId in pairs(fish.modules.hooks[module.Id]) do
            hook.Remove(hookName, hookId)
        end

        if isfunction(module.PreDisable) then
            module:PreDisable()
        end
    else
        if isfunction(module.PostDisable) then
            module:PostDisable()
        end

        fish.modules.hooks[module.Id] = nil
        fish.modules.list[module.Id] = nil
    end
end


--- internal: loads a file module by path without inserting its data into the list
--- @param filePath string
--- @param fileName? string
--- @return table module
--- @return boolean exists whether or not the module already existed before loading
function fish.modules._LoadFile(filePath, fileName)
    fish.modules._Begin()
    fish.Include(filePath, fish.Realm.SHARED)
    local module, hookTable = fish.modules._End()

    module.Id = module.Id or string.StripExtension(fileName or string.GetFileFromFilename(filePath))
    local exists = istable(fish.modules.list[module.Id])

    if exists then
        module = fish.utilities.Merge(fish.modules.list[module.Id], module)
    end

    module.Path = filePath
    module.Type = fish.ModuleType.FILE
    module.Hooks = hookTable

    return module, exists
end

--- loads a file module by path
--- @param filePath string
--- @param fileName? string
--- @return table module
function fish.modules.LoadFile(filePath, fileName)
    local module, exists = fish.modules._LoadFile(filePath, fileName)

    fish.modules._CheckModuleDependencies(module)
    fish.modules._DoEnable(module, false, exists)

    fish.modules.list[module.Id] = module
    table.insert(fish.modules.orderedList, module.Id)

    fish.modules._DoEnable(module, true, exists)

    return module
end

--- loads a directory module by path
--- @param directoryPath string
--- @param directoryName? string
--- @return table module
function fish.modules.LoadDirectory(directoryPath, directoryName)
    local moduleMetaPath = directoryPath .. "/module.lua"

    fish.modules._Begin()
    fish.Include(moduleMetaPath, fish.Realm.SHARED)

    local module = fish.modules._GetCurrent()
    module.Id = module.Id or directoryName or string.GetFileFromFilename(directoryPath)
    module.Path = directoryPath
    module.Type = fish.ModuleType.DIRECTORY

    local exists = istable(fish.modules.list[module.Id])
    if exists then
        module = fish.utilities.inherit(fish.modules.list[module.Id], module)
    end
    fish.modules._CheckModuleDependencies(module)

    fish.modules._DoEnable(module, false, exists)
    fish.modules._LoadScripts(module)
    module = fish.modules._End()

    fish.modules.list[module.Id] = module
    table.insert(fish.modules.orderedList, module.Id)

    fish.modules._DoEnable(module, true, exists)

    local submodulePath = directoryPath .. "/modules"
    if file.Exists(submodulePath, "LUA") then
        local paths = {}
        for path, _ in fish.DirectoryIterator(submodulePath, "*", false, true, true) do
            table.insert(paths, path)
        end

        fish.modules.LoadAll(paths)
    end
    return module
end

--- loads a module by path
--- @param path string
--- @param name string
--- @return table module
function fish.modules.Load(path, name)
    if file.IsDir(path, "LUA") then
        return fish.modules.LoadDirectory(path, name)
    else
        return fish.modules.LoadFile(path, name)
    end
end

--- internal: sorts modules by their dependencies
--- @param modules table<string, table> 
--- @return table<table> sortedModules
function fish.modules.SortModules(modules)
    local sortedModules = {}

    -- depth-first topological sort
    local permanentMarks = {}
    local temporaryMarks = {}

    local function visit(module)
        if permanentMarks[module.Id] then
            return false
        end

        if temporaryMarks[module.Id] then
            error("dependency cycle with module " .. module.Id)
        end

        temporaryMarks[module.Id] = true

        if istable(module.Dependencies) then
            for _, dependencyId in ipairs(module.Dependencies) do
                visit(modules[dependencyId])
            end
        end

        temporaryMarks[module.Id] = nil
        permanentMarks[module.Id] = true

        table.insert(sortedModules, module)
    end

    local moduleCount = table.Count(modules)
    while table.Count(permanentMarks) < moduleCount do
        for id, module in pairs(modules) do
            if not temporaryMarks[id] and not permanentMarks[id] then
                visit(module)
                break
            end
        end
    end

    return sortedModules
end

--- loads multiple modules by paths
--- @param paths table<string> module paths
function fish.modules.LoadAll(paths)
    if paths[1] == nil then return end

    local unsortedModules = fish.modules.list
    local newModules = {}
    local reloadingModules = {}

    local function visitPath(path, name)
        local module = nil
        if file.IsDir(path, "LUA") then
            module = fish.modules._LoadMetadata(path, name)
        else
            module = fish.modules._LoadFile(path, name)
        end

        newModules[module.Id] = true

        local oldModule = fish.modules.list[module.Id]
        if istable(oldModule) then
            reloadingModules[module.Id] = true
            module = fish.utilities.Merge(oldModule, module)
        end

        unsortedModules[module.Id] = module

        local submodulePath = path .. "/modules"
        if file.IsDir(submodulePath, "LUA") then
            for subPath, subName in fish.DirectoryIterator(submodulePath, "*", false, true, true) do
                visitPath(subPath, subName)
            end
        end
    end

    for _, path in ipairs(paths) do
        visitPath(path)
    end

    local sortedModules = fish.modules.SortModules(unsortedModules)

    fish.modules.orderedList = {}

    for index, module in ipairs(sortedModules) do
        module.Index = index

        if not newModules[module.Id] then
            fish.modules.orderedList[index] = module.Id
            fish.modules.list[module.Id] = module
            continue
        end
        
        local reloading = reloadingModules[module.Id]
        fish.modules._Begin(module)
        fish.modules._DoEnable(module, false, reloading)
        fish.modules._LoadScripts(module)

        module = fish.modules._End()
        fish.modules.orderedList[index] = module.Id
        fish.modules.list[module.Id] = module

        fish.modules._DoEnable(module, true, reloading)
    end
end

--- loads all modules from a specified directory
--- @param directoryPath string
function fish.modules.LoadAllFromDirectory(directoryPath)
    local paths = {}
    for filePath, _ in fish.DirectoryIterator(directoryPath, "*", false, true, true) do
        table.insert(paths, filePath)
    end

    return fish.modules.LoadAll(paths)
end

hook.Add("ShutDown", "fish_ShutDown", function()
    local moduleCount = #fish.modules.orderedList
    for i = 1, moduleCount do
        local module = fish.modules.list[fish.modules.orderedList[#fish.modules.orderedList + 1 - i]]
        fish.modules._DoDisable(module, false)
    end

    for i = 1, moduleCount do
        local module = fish.modules.list[fish.modules.orderedList[#fish.modules.orderedList + 1 - i]]
        fish.modules._DoDisable(module, true)
    end
end)