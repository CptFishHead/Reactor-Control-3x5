local filesystem = require("filesystem")

local layout = {}
layout.bounds = {left = 1, top = 4, right = 100, bottom = 20}
layout.minimum = {width = 24, height = 7}
layout.screen = {width = 100, height = 30}

function layout.setScreen(width, height)
    if not ((width == 100 and height == 30) or (width == 80 and height == 25)) then
        return false, "Допустимые разрешения: 100x30 и 80x25"
    end
    layout.screen = {width = width, height = height}
    layout.bounds = {left = 1, top = width == 80 and 3 or 4, right = width, bottom = width == 80 and 17 or 20}
    return true
end

function layout.defaults()
    local cards = {}
    for slot = 1, 6 do
        cards[slot] = {
            column = 2 + ((slot - 1) % 3) * (layout.screen.width == 80 and 26 or 33),
            row = layout.bounds.top + math.floor((slot - 1) / 3) * (layout.screen.width == 80 and 8 or 9),
            width = layout.screen.width == 80 and 25 or 31,
            height = layout.screen.width == 80 and 7 or 8,
            layer = slot, fontScale = 1,
            names = {"", ""}
        }
    end
    return cards
end

function layout.clone(cards)
    local copy = {}
    for slot, card in ipairs(cards) do
        copy[slot] = {
            column = card.column, row = card.row, width = card.width, height = card.height,
            layer = card.layer or slot, fontScale = card.fontScale or 1, names = {card.names and card.names[1] or "", card.names and card.names[2] or ""}
        }
    end
    return copy
end

function layout.overlap(first, second)
    return first.column < second.column + second.width and second.column < first.column + first.width
        and first.row < second.row + second.height and second.row < first.row + first.height
end

function layout.validate(cards)
    if type(cards) ~= "table" or #cards ~= 6 then return false, "Нужно шесть карточек" end
    for slot, card in ipairs(cards) do
        if type(card) ~= "table" then return false, "Повреждена карточка" end
        for _, field in ipairs({"column", "row", "width", "height"}) do
            local value = card[field]
            if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge or value ~= math.floor(value) then
                return false, "Координаты должны быть целыми числами"
            end
        end
        local scale = card.fontScale or 1
        if scale ~= 1 and scale ~= 2 then return false, "Масштаб шрифта: 1 или 2" end
        if card.width < layout.minimum.width * scale or card.height < 6 * scale + 1 then
            return false, "Минимальный размер: " .. (24 * scale) .. "x" .. (6 * scale + 1)
        end
        if card.column < layout.bounds.left or card.row < layout.bounds.top
            or card.column + card.width - 1 > layout.bounds.right or card.row + card.height - 1 > layout.bounds.bottom then
            return false, "Карточка выходит за рабочую область"
        end
        local layer = card.layer or slot
        if type(layer) ~= "number" or layer < 1 or layer > 6 or layer ~= math.floor(layer) then
            return false, "Повреждён порядок карточек"
        end
        if card.names ~= nil then
            if type(card.names) ~= "table" then return false, "Повреждены названия карточек" end
            for page = 1, 2 do
                local name = card.names[page]
                if type(name) ~= "string" or #name > 128 or name:find("[%z\1-\31\127]") then
                    return false, "Недопустимое название карточки"
                end
            end
        end
    end
    return true
end

function layout.clamp(card)
    local scale = card.fontScale or 1
    card.width = math.max(layout.minimum.width * scale, math.min(layout.bounds.right - layout.bounds.left + 1, math.floor(card.width)))
    card.height = math.max(6 * scale + 1, math.min(layout.bounds.bottom - layout.bounds.top + 1, math.floor(card.height)))
    card.column = math.max(layout.bounds.left, math.min(layout.bounds.right - card.width + 1, math.floor(card.column)))
    card.row = math.max(layout.bounds.top, math.min(layout.bounds.bottom - card.height + 1, math.floor(card.row)))
    return card
end

function layout.read(path)
    local file = io.open(path, "r")
    local recovered = false
    if not file then
        file = io.open(path .. ".bak", "r")
        recovered = file ~= nil
    end
    if not file then layout.setScreen(100, 30); return layout.defaults() end
    local cards = {}
    local format = file:read("*l")
    layout.setScreen(100, 30)
    local screenValid = true
    if format == "RC-LAYOUT-4" then
        local width, height = (file:read("*l") or ""):match("^(%d+) (%d+)$")
        screenValid = layout.setScreen(tonumber(width), tonumber(height))
    end
    if format == "RC-LAYOUT-1" or format == "RC-LAYOUT-2" or format == "RC-LAYOUT-3" or format == "RC-LAYOUT-4" then
        for slot = 1, 6 do
            local line = file:read("*l") or ""
            local column, row, width, height, layer, fontScale
            if format == "RC-LAYOUT-3" or format == "RC-LAYOUT-4" then
                column, row, width, height, layer, fontScale = line:match("^(%d+) (%d+) (%d+) (%d+) (%d+) (%d+)$")
            elseif format == "RC-LAYOUT-2" then
                column, row, width, height, layer = line:match("^(%d+) (%d+) (%d+) (%d+) (%d+)$")
            else
                column, row, width, height = line:match("^(%d+) (%d+) (%d+) (%d+)$")
            end
            local names = {"", ""}
            if format ~= "RC-LAYOUT-1" then names = {file:read("*l"), file:read("*l")} end
            cards[slot] = {
                column = tonumber(column), row = tonumber(row), width = tonumber(width), height = tonumber(height),
                layer = format ~= "RC-LAYOUT-1" and tonumber(layer) or slot, names = names,
                fontScale = (format == "RC-LAYOUT-3" or format == "RC-LAYOUT-4") and tonumber(fontScale) or 1
            }
        end
    end
    file:close()
    local valid, reason = layout.validate(cards)
    if valid and screenValid then return cards, recovered and "Раскладка восстановлена из резервной копии" or nil end
    if not screenValid then reason = "Недопустимое разрешение" end
    layout.setScreen(100, 30)
    return layout.defaults(), "Раскладка сброшена: " .. reason
end

function layout.write(path, cards)
    local valid, reason = layout.validate(cards)
    if not valid then return false, reason end
    local temporary = path .. ".new"
    local backup = path .. ".bak"
    local file, errorMessage = io.open(temporary, "w")
    if not file then return false, tostring(errorMessage or "Не удалось открыть файл раскладки") end
    local written, writeError = pcall(function()
        assert(file:write("RC-LAYOUT-4\n" .. layout.screen.width .. " " .. layout.screen.height .. "\n"))
        for slot, card in ipairs(cards) do
            assert(file:write(string.format("%d %d %d %d %d %d\n", card.column, card.row, card.width, card.height, card.layer or slot, card.fontScale or 1)))
            assert(file:write((card.names and card.names[1] or "") .. "\n" .. (card.names and card.names[2] or "") .. "\n"))
        end
        assert(file:flush())
        local closed, closeError = file:close()
        if closed == false or closeError then error(closeError or "Не удалось закрыть файл раскладки") end
    end)
    if not written then
        pcall(file.close, file)
        filesystem.remove(temporary)
        return false, tostring(writeError)
    end
    local hadPrevious = filesystem.exists(path)
    if hadPrevious then
        if filesystem.exists(backup) and not filesystem.remove(backup) then return false, "Не удалось обновить резервную копию" end
        if not filesystem.rename(path, backup) then return false, "Не удалось сохранить старую раскладку" end
    end
    local moved, moveError = filesystem.rename(temporary, path)
    if not moved then
        if hadPrevious and not filesystem.rename(backup, path) then
            return false, "Предыдущая раскладка сохранена в " .. backup
        end
        return false, tostring(moveError or "Не удалось сохранить раскладку")
    end
    return true
end

local glyphs = {
    ["0"]="6999996", ["1"]="2622227", ["2"]="691248F", ["3"]="E161196", ["4"]="99F1111",
    ["5"]="F88E196", ["6"]="688E996", ["7"]="F112244", ["8"]="6996996", ["9"]="6997116",
    A="699F999", B="E99E99E", C="6988896", D="E99999E", E="F88E88F", F="F88E888",
    G="698B996", H="999F999", I="7222227", J="1111196", K="99ACA99", L="888888F",
    M="9FF9999", N="9DDBB99", O="6999996", P="E99E888", Q="69999B7", R="E99EA99",
    S="788619E", T="F222222", U="9999996", V="9999966", W="9999FF9", X="9966699",
    Y="9996222", Z="F11248F", [" "]="0000000", ["-"]="000F000", ["—"]="000F000",
    ["."]="0000022", [":"]="0220220", ["/"]="1122448", ["|"]="2222222", ["%"]="9912489",
    ["#"]="5F55F50", ["°"]="6960000", ["+"]="0027200", ["_"]="000000F", ["!"]="2222202",
    ["?"]="6912202", ["("]="1244421", [")"]="8422248", ["["]="6444446", ["]"]="6222226",
    ["Б"]="F88E99E", ["Г"]="F888888", ["Д"]="366666F", ["Ж"]="99F6F99", ["З"]="E11611E",
    ["И"]="99BBD99", ["Й"]="699BBD9", ["Л"]="3666669", ["П"]="F999999", ["У"]="999711E",
    ["Ф"]="2FFFF22", ["Ц"]="AAAAF11", ["Ч"]="9997111", ["Ш"]="999999F", ["Щ"]="9999F11",
    ["Ъ"]="CC4E55E", ["Ы"]="999DDDF", ["Ь"]="888E99E", ["Э"]="6917196", ["Ю"]="BDAEADB",
    ["Я"]="7997599", ["Ё"]="90FE88F"
}

function layout.scaledText(buffer, unicode, column, row, width, text, color)
    if not layout.font then
        layout.font = {}
        local upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
        local lower = "abcdefghijklmnopqrstuvwxyzабвгдеёжзийклмнопрстуфхцчшщъыьэюя"
        local aliases = {["А"]="A", ["В"]="B", ["Е"]="E", ["К"]="K", ["М"]="M", ["Н"]="H", ["О"]="O", ["Р"]="P", ["С"]="C", ["Т"]="T", ["Х"]="X"}
        for symbol, pattern in pairs(glyphs) do layout.font[symbol] = pattern end
        for index = 1, unicode.len(upper) do
            local symbol = unicode.sub(upper, index, index)
            local pattern = glyphs[aliases[symbol] or symbol]
            layout.font[symbol] = pattern
            layout.font[unicode.sub(lower, index, index)] = pattern
        end
    end
    local weights = {{1, 2, 4, 64}, {8, 16, 32, 128}}
    for index = 1, math.min(unicode.len(text), math.floor(width / 2)) do
        local pattern = layout.font[unicode.sub(text, index, index)] or glyphs["?"]
        for cellRow = 0, 1 do
            local line = ""
            for cellColumn = 0, 1 do
                local mask = 0
                for dotRow = 1, 4 do
                    local pixelRow = cellRow * 4 + dotRow
                    local bits = tonumber(pattern:sub(pixelRow, pixelRow), 16) or 0
                    for dotColumn = 1, 2 do
                        local power = 2 ^ (4 - cellColumn * 2 - dotColumn)
                        if math.floor(bits / power) % 2 == 1 then mask = mask + weights[dotColumn][dotRow] end
                    end
                end
                line = line .. unicode.char(0x2800 + mask)
            end
            buffer.drawText(column + (index - 1) * 2, row + cellRow, color, line)
        end
    end
end

return layout
