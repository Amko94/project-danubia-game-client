json = {}

function json.decode(str)
    if not str or str == "" then
        return {}
    end
    str = str:match("^%s*(.-)%s*$")
    if str:sub(1, 1) == "[" and str:sub(-1) == "]" then
        local result = {}
        local items = str:sub(2, -2)
        if items == "" then
            return result
        end
        local objects, current, inString, braceLevel, i = {}, "", false, 0, 1
        while i <= #items do
            local char = items:sub(i, i)
            local prevChar = i > 1 and items:sub(i - 1, i - 1) or ""
            if char == '"' and prevChar ~= "\\" then
                inString = not inString
            end
            if not inString then
                if char == "{" then
                    braceLevel = braceLevel + 1
                elseif char == "}" then
                    braceLevel = braceLevel - 1
                elseif char == "," and braceLevel == 0 then
                    if current ~= "" then
                        table.insert(objects, current)
                    end
                    current, i = "", i + 1
                    goto continue
                end
            end
            current, i = current .. char, i + 1
            :: continue ::
        end
        if current ~= "" then
            table.insert(objects, current)
        end
        for _, obj in ipairs(objects) do
            local task = json.parseObject(obj)
            if task then
                table.insert(result, task)
            end
        end
        return result
    end
    return {}
end

function json.parseObject(str)
    if not str then
        return nil
    end
    str = str:match("^%s*{(.-)}%s*$")
    if not str then
        return nil
    end
    local task, pairs, current, inString, braceLevel, bracketLevel, i = {}, {}, "", false, 0, 0, 1
    while i <= #str do
        local char = str:sub(i, i)
        local prevChar = i > 1 and str:sub(i - 1, i - 1) or ""
        if char == '"' and prevChar ~= "\\" then
            inString = not inString
        end
        if not inString then
            if char == "{" then
                braceLevel = braceLevel + 1
            elseif char == "}" then
                braceLevel = braceLevel - 1
            elseif char == "[" then
                bracketLevel = bracketLevel + 1
            elseif char == "]" then
                bracketLevel = bracketLevel - 1
            elseif char == "," and braceLevel == 0 and bracketLevel == 0 then
                if current ~= "" then
                    table.insert(pairs, current)
                end
                current, i = "", i + 1
                goto continue2
            end
        end
        current, i = current .. char, i + 1
        :: continue2 ::
    end
    if current ~= "" then
        table.insert(pairs, current)
    end
    for _, pair in ipairs(pairs) do
        local key, value = pair:match('^%s*"([^"]+)"%s*:%s*"([^"]*)"')
        if key and value then
            task[key] = value
        else
            key, value = pair:match('^%s*"([^"]+)"%s*:%s*([%d.]+)')
            if key and value then
                task[key] = tonumber(value)
            else
                key, value = pair:match('^%s*"([^"]+)"%s*:%s*(%[.*%])')
                if key and value then
                    local arrayStr = value:sub(2, -2)
                    local arrayResult = {}
                    if arrayStr ~= "" then
                        for num in arrayStr:gmatch('[^,]+') do
                            num = tonumber(num)
                            if num then
                                table.insert(arrayResult, num)
                            end
                        end
                    end
                    task[key] = arrayResult
                end
            end
        end
    end
    return next(task) and task or nil
end

function safeJsonDecode(str)
    local status, result = pcall(function()
        return json.decode(str)
    end)
    return status and result or {}
end