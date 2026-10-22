local filesystem = require("filesystem")
local shell = require("shell")
local computer = require("computer")
local component = require("component")

local repository = "https://raw.githubusercontent.com/CptFishHead/Reactor-Control-3x5/main/"
local staging = "/home/.reactor-install"
local files = {
    {source = "lib/advancedLua.lua", target = "/lib/advancedLua.lua"},
    {source = "lib/color.lua", target = "/lib/color.lua"},
    {source = "lib/OCIF.lua", target = "/lib/FormatModules/OCIF.lua"},
    {source = "lib/image.lua", target = "/lib/image.lua"},
    {source = "lib/doubleBuffering.lua", target = "/lib/doubleBuffering.lua"},
    {source = "lib/event.lua", target = "/lib/event.lua"},
    {source = "lib/reactorLayout.lua", target = "/lib/reactorLayout.lua"},
    {source = "home/nr_v1.1.lua", target = "/home/main.lua"},
    {source = "LICENSE", target = "/home/reactor-LICENSE.txt"}
}

local function read(path)
    local file = io.open(path, "r")
    if not file then return "" end
    local content = file:read("*a")
    file:close()
    return content or ""
end

local function write(path, content)
    local file = assert(io.open(path, "w"))
    assert(file:write(content))
    assert(file:close())
end

local function directory(path)
    if not filesystem.exists(path) then assert(filesystem.makeDirectory(path)) end
end

local function install()
    assert(component.isAvailable("internet"), "Нужна интернет-карта")
    local width, height = component.gpu.maxResolution()
    assert(width >= 100 and height >= 30, "Нужны монитор и видеокарта третьего уровня (100x30)")
    assert(not rawget(_G, "__NR_ON_INTERRUPT__"), "Сначала останови реакторы и выйди из Reactor Control")
    print("Reactor Control 3x5: загрузка и проверка файлов...")
    directory(staging)
    for index, file in ipairs(files) do
        file.staged = staging .. "/" .. index
        print(string.format("[%d/%d] %s", index, #files, file.target))
        assert(shell.execute("wget -fq " .. repository .. file.source .. " " .. file.staged), "Ошибка загрузки: " .. file.source)
        assert(filesystem.exists(file.staged) and filesystem.size(file.staged) > 0, "Файл не записан: " .. file.source .. ". Проверь свободное место на диске.")
        if file.source:match("%.lua$") then
            local chunk, errorMessage = loadfile(file.staged)
            assert(chunk, "Повреждён Lua-файл: " .. file.source .. ": " .. tostring(errorMessage))
        end
    end

    local startup = read("/home/.shrc")
    local hasAutostart = false
    for line in startup:gmatch("[^\n]+") do
        local command = line:gsub("^%s+", ""):gsub("%s+$", "")
        if command == "main.lua" or command == "/home/main.lua" then hasAutostart = true end
    end
    if not hasAutostart then
        if startup ~= "" and startup:sub(-1) ~= "\n" then startup = startup .. "\n" end
        startup = startup .. "/home/main.lua\n"
    end
    write(staging .. "/startup", startup)
    table.insert(files, {target = "/home/.shrc", staged = staging .. "/startup"})

    local installed = {}
    local backupFolder = "/home/reactor-backup/" .. tostring(math.floor(computer.uptime() * 1000))
    while filesystem.exists(backupFolder) do backupFolder = backupFolder .. "-new" end
    directory(backupFolder)
    local success, failure = pcall(function()
        for index, file in ipairs(files) do
            local entry = {target = file.target, existed = filesystem.exists(file.target), backup = backupFolder .. file.target}
            directory(filesystem.path(file.target))
            if entry.existed then
                directory(filesystem.path(entry.backup))
                assert(filesystem.copy(file.target, entry.backup))
            end
            table.insert(installed, entry)
            if entry.existed then assert(filesystem.remove(file.target)) end
            assert(filesystem.copy(file.staged, file.target))
        end
        directory("/home/data")
    end)
    if not success then
        local restored = true
        for index = #installed, 1, -1 do
            local entry = installed[index]
            if filesystem.exists(entry.target) and not filesystem.remove(entry.target) then restored = false end
            if entry.existed and not filesystem.copy(entry.backup, entry.target) then restored = false end
        end
        error((restored and "Прежние файлы восстановлены: " or ("Нужно восстановление из " .. backupFolder .. ": ")) .. tostring(failure))
    end
    for _, file in ipairs(files) do filesystem.remove(file.staged) end
    filesystem.remove(staging)
    print("Установлено. Конфигурация и раскладка сохранены.")
    print("Резервная копия заменённых файлов: " .. backupFolder)
    print("После перезапуска откроется программа. При первом запуске добавь свой ник в настройках.")
    os.sleep(2)
    computer.shutdown(true)
end

local success, errorMessage = pcall(install)
if not success then
    io.stderr:write("Установка не выполнена: " .. tostring(errorMessage) .. "\n")
    return false
end
return true
