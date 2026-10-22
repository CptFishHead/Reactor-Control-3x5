local shell = require("shell")
local target = "/tmp/reactor-setup.lua"
assert(shell.execute("wget -fq https://raw.githubusercontent.com/CptFishHead/Reactor-Control-3x5/main/install.lua " .. target), "Не удалось загрузить установщик")
return assert(loadfile(target))()
