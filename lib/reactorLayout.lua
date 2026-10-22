local filesystem = require("filesystem")

local layout = {}
layout.bounds = {left = 1, top = 4, right = 100, bottom = 20}
layout.minimum = {width = 24, height = 7}

function layout.defaults()
    local cards = {}
    for slot = 1, 6 do
        cards[slot] = {
            column = 2 + ((slot - 1) % 3) * 33,
            row = 4 + math.floor((slot - 1) / 3) * 9,
            width = 31,
            height = 8,
            layer = slot,
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
            layer = card.layer or slot, names = {card.names and card.names[1] or "", card.names and card.names[2] or ""}
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
        if card.width < layout.minimum.width or card.height < layout.minimum.height then
            return false, "Минимальный размер: 24x7"
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
    card.width = math.max(layout.minimum.width, math.min(layout.bounds.right - layout.bounds.left + 1, math.floor(card.width)))
    card.height = math.max(layout.minimum.height, math.min(layout.bounds.bottom - layout.bounds.top + 1, math.floor(card.height)))
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
    if not file then return layout.defaults() end
    local cards = {}
    local format = file:read("*l")
    if format == "RC-LAYOUT-1" or format == "RC-LAYOUT-2" then
        for slot = 1, 6 do
            local line = file:read("*l") or ""
            local column, row, width, height, layer
            if format == "RC-LAYOUT-2" then
                column, row, width, height, layer = line:match("^(%d+) (%d+) (%d+) (%d+) (%d+)$")
            else
                column, row, width, height = line:match("^(%d+) (%d+) (%d+) (%d+)$")
            end
            local names = {"", ""}
            if format == "RC-LAYOUT-2" then names = {file:read("*l"), file:read("*l")} end
            cards[slot] = {
                column = tonumber(column), row = tonumber(row), width = tonumber(width), height = tonumber(height),
                layer = format == "RC-LAYOUT-2" and tonumber(layer) or slot, names = names
            }
        end
    end
    file:close()
    local valid, reason = layout.validate(cards)
    if valid then return cards, recovered and "Раскладка восстановлена из резервной копии" or nil end
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
        assert(file:write("RC-LAYOUT-2\n"))
        for slot, card in ipairs(cards) do
            assert(file:write(string.format("%d %d %d %d %d\n", card.column, card.row, card.width, card.height, card.layer or slot)))
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

return layout
