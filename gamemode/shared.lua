DeriveGamemode("sandbox")
fish = fish or {}

--- @enum fish.Realm
fish.Realm = {
    CLIENT = 0,
    SERVER = 1,
    SHARED = 2
}

--- @param filePath string file name if detectName is false
--- @param detectName? boolean defaults to true
--- @nodiscard
--- @return fish.Realm
function fish.DetectRealm(filePath, detectName)
    local fileName = filePath

    if detectName ~= false then
        fileName = string.GetFileFromFilename(filePath)
    end

    local prefix = string.sub(fileName, 1, 3):lower()
    if prefix == "cl_" then
        return fish.Realm.CLIENT
    elseif prefix == "sv_" then
        return fish.Realm.SERVER
    elseif prefix == "sh_" then
        return fish.Realm.SHARED
    end

    error("could not detect realm")
end

--- @param filePath string
--- @param realm? fish.Realm
function fish.Include(filePath, realm)
    if realm == nil then
        realm = fish.DetectRealm(filePath)
    else
        assert(realm >= 0 and realm <= 2, "invalid realm value")
    end

    if realm == fish.Realm.CLIENT then
        AddCSLuaFile(filePath)
        if CLIENT then
            include(filePath)
        end
    elseif realm == fish.Realm.SERVER and SERVER then
        include(filePath)
    elseif realm == fish.Realm.SHARED then
        AddCSLuaFile(filePath)
        include(filePath)
    end
end

--- creates an iterator for looping through a directory
--- @param directoryPath string
--- @param filter? string
--- @param recursive? boolean
--- @param includeFiles? boolean
--- @param includeDirectories? boolean
--- @return function iterator
--- @return table<string, string> contents directory contents
function fish.DirectoryIterator(directoryPath, filter, recursive, includeFiles, includeDirectories)
    filter = filter or "*"

    local contents = {}
    local files, directories = file.Find(directoryPath .. "/" .. filter, "LUA")

    if includeFiles ~= false then
        for _, fileName in ipairs(files) do
            contents[directoryPath .. "/" .. fileName] = fileName
        end
    end

    if includeDirectories then
        for _, directoryName in ipairs(directories) do
            contents[directoryPath .. "/" .. directoryName] = directoryName
        end
    end

    if recursive then
        local function iterateDirectory(directoryPath)
            local _, directories = file.Find(directoryPath .. "/*", "LUA")
            for _, directoryName in ipairs(directories) do
                iterateDirectory(directoryPath .. "/" .. directoryName)
                if includeDirectories ~= false then
                    contents[directoryPath .. "/" .. directoryName] = directoryName
                end
            end

            local files, _ = file.Find(directoryPath .. "/" .. filter, "LUA")
            if includeFiles ~= false then
                for _, fileName in ipairs(files) do
                    contents[directoryPath .. "/" .. fileName] = fileName
                end
            end
        end

        iterateDirectory(directoryPath)
    end

    return pairs(contents)
end

--- includes lua files in a directory
--- @param directoryPath string
--- @param realm? fish.Realm
function fish.IncludeDirectory(directoryPath, realm)
    for filePath, fileName in fish.DirectoryIterator(directoryPath, "*.lua", false, true, false) do
        fish.Include(filePath, realm or fish.DetectRealm(fileName, false))
    end
end

fish.IncludeDirectory("fish/libraries", fish.Realm.SHARED)

--- initializes the fish library & modules
function fish.Init()
    fish.modules.LoadAllFromDirectory("fish/modules")

    local activeGamemode = engine.ActiveGamemode()
    local gamemodeDirectory = activeGamemode .. "/fish"

    fish.IncludeDirectory(gamemodeDirectory .. "/libraries", fish.Realm.SHARED)
    fish.modules.LoadAllFromDirectory(gamemodeDirectory .. "/modules")
end
