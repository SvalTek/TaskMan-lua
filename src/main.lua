local JSON = {}

-- Internal functions.

local function kind_of(obj)
    if type(obj) ~= 'table' then return type(obj) end
    local i = 1
    for _ in pairs(obj) do
        if obj[i] ~= nil then
            i = i + 1
        else
            return 'table'
        end
    end
    if i == 1 then
        return 'table'
    else
        return 'array'
    end
end

local function escape_str(s)
    local in_char = {'\\', '"', '/', '\b', '\f', '\n', '\r', '\t'}
    local out_char = {'\\', '"', '/', 'b', 'f', 'n', 'r', 't'}
    for i, c in ipairs(in_char) do s = s:gsub(c, '\\' .. out_char[i]) end
    return s
end

-- Returns pos, did_find; there are two cases:
-- 1. Delimiter found: pos = pos after leading space + delim; did_find = true.
-- 2. Delimiter not found: pos = pos after leading space;     did_find = false.
-- This throws an error if err_if_missing is true and the delim is not found.
local function skip_delim(str, pos, delim, err_if_missing)
    pos = pos + #str:match('^%s*', pos)
    if str:sub(pos, pos) ~= delim then
        if err_if_missing then error('Expected ' .. delim .. ' near position ' .. pos) end
        return pos, false
    end
    return pos + 1, true
end

-- Expects the given pos to be the first character after the opening quote.
-- Returns val, pos; the returned pos is after the closing quote character.
local function parse_str_val(str, pos, val)
    val = val or ''
    local early_end_error = 'End of input found while parsing string.'
    if pos > #str then error(early_end_error) end
    local c = str:sub(pos, pos)
    if c == '"' then return val, pos + 1 end
    if c ~= '\\' then return parse_str_val(str, pos + 1, val .. c) end
    -- We must have a \ character.
    local esc_map = {b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'}
    local nextc = str:sub(pos + 1, pos + 1)
    if not nextc then error(early_end_error) end
    return parse_str_val(str, pos + 2, val .. (esc_map[nextc] or nextc))
end

-- Returns val, pos; the returned pos is after the number's final character.
local function parse_num_val(str, pos)
    local num_str = str:match('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
    local val = tonumber(num_str)
    if not val then error('Error parsing number at position ' .. pos .. '.') end
    return val, pos + #num_str
end

-- Public values and functions.

function JSON.stringify(obj, as_key)
    local s = {} -- We'll build the string as an array of strings to be concatenated.
    local kind = kind_of(obj) -- This is 'array' if it's an array or type(obj) otherwise.
    if kind == 'array' then
        if as_key then error('Can\'t encode array as key.') end
        s[#s + 1] = '['
        for i, val in ipairs(obj) do
            if i > 1 then s[#s + 1] = ', ' end
            s[#s + 1] = JSON.stringify(val)
        end
        s[#s + 1] = ']'
    elseif kind == 'table' then
        if as_key then error('Can\'t encode table as key.') end
        s[#s + 1] = '{'
        for k, v in pairs(obj) do
            if #s > 1 then s[#s + 1] = ', ' end
            s[#s + 1] = JSON.stringify(k, true)
            s[#s + 1] = ':'
            s[#s + 1] = JSON.stringify(v)
        end
        s[#s + 1] = '}'
    elseif kind == 'string' then
        return '"' .. escape_str(obj) .. '"'
    elseif kind == 'number' then
        if as_key then return '"' .. tostring(obj) .. '"' end
        return tostring(obj)
    elseif kind == 'boolean' then
        return tostring(obj)
    elseif kind == 'nil' then
        return 'null'
    else
        error('Unjsonifiable type: ' .. kind .. '.')
    end
    return table.concat(s)
end

JSON.null = {} -- This is a one-off table to represent the null value.

function JSON.parse(str, pos, end_delim)
    pos = pos or 1
    if pos > #str then error('Reached unexpected end of input.') end
    local pos = pos + #str:match('^%s*', pos) -- Skip whitespace.
    local first = str:sub(pos, pos)
    if first == '{' then -- Parse an object.
        local obj, key, delim_found = {}, true, true
        pos = pos + 1
        while true do
            key, pos = JSON.parse(str, pos, '}')
            if key == nil then return obj, pos end
            if not delim_found then error('Comma missing between object items.') end
            pos = skip_delim(str, pos, ':', true) -- true -> error if missing.
            obj[key], pos = JSON.parse(str, pos)
            pos, delim_found = skip_delim(str, pos, ',')
        end
    elseif first == '[' then -- Parse an array.
        local arr, val, delim_found = {}, true, true
        pos = pos + 1
        while true do
            val, pos = JSON.parse(str, pos, ']')
            if val == nil then return arr, pos end
            if not delim_found then error('Comma missing between array items.') end
            arr[#arr + 1] = val
            pos, delim_found = skip_delim(str, pos, ',')
        end
    elseif first == '"' then -- Parse a string.
        return parse_str_val(str, pos + 1)
    elseif first == '-' or first:match('%d') then -- Parse a number.
        return parse_num_val(str, pos)
    elseif first == end_delim then -- End of an object or array.
        return nil, pos + 1
    else -- Parse true, false, or null.
        local literals = {['true'] = true, ['false'] = false, ['null'] = JSON.null}
        for lit_str, lit_val in pairs(literals) do
            local lit_end = pos + #lit_str - 1
            if str:sub(pos, lit_end) == lit_str then return lit_val, lit_end + 1 end
        end
        local pos_info_str = 'position ' .. pos .. ': ' .. str:sub(pos, pos + 10)
        error('Invalid json syntax starting at ' .. pos_info_str)
    end
end

--- given the string date from os.date() check if the date has passed
local function hasDatePassed(date)
    if not date then
        return false
    end
    local year, month, day = date:match("(%d+)-(%d+)-(%d+)")
    local date = os.time({year = year, month = month, day = day})
    local now = os.time()
    --- allow today
    return date < now - 86400
end

--- given the string date from os.date() check if the date is today
local function isDateToday(date)
    if not date then
        return false
    end
    local now = os.date("%Y-%m-%d")
    return date == now
end

--- given the string date from os.date() check if the date is tomorrow
local function isDateTomorrow(date)
    if not date then
        return false
    end
    local year, month, day = date:match("(%d+)-(%d+)-(%d+)")
    local now = os.date("%Y-%m-%d")
    local nowYear, nowMonth, nowDay = now:match("(%d+)-(%d+)-(%d+)")
    local the_date = os.time({year = year, month = month, day = day})
    local tomorrow = os.time({year = nowYear, month = nowMonth, day = nowDay + 1})
    return the_date == tomorrow
end

--- print a small ascii cat
local function PrintCat()
    print("\n\n\n\n\n")
    print("  /\\_/\\")
    print(" ( o.o )")
    print("  > ^ <")
    print(" /     \\")
    print("/       \\")
    print("\\ /\\_/\\ /")
    print(" ( o.o )")
    print("  > ^ <")
    print(" /     \\")
    print("/       \\")
    print("|       |")
    print(" \\_____/")
    print("\n")
end



local tasks = {}

local function SaveTasks()
    local file = io.open("tasks.json", "w")
    if not file then
        error("Failed to open tasks.json")
    end
    file:write(JSON.stringify(tasks))
    file:close()
end

local function LoadTasks()
    local file = io.open("tasks.json", "r")
    if not file then
        error("Failed to open tasks.json")
    end
    local data = file:read("*a")
    file:close()
---@diagnostic disable-next-line: cast-local-type
    tasks = JSON.parse(data)
end

local function isFile(path)
    local file = io.open(path, "r")
    if file then
        file:close()
    end
    return file ~= nil
end

-- ─── Main Script ─────────────────────────────────────────────────────────────

local taskCounter = 0;

local function AddTask(taskDescription, taskRequiredBy, taskName)
    if not type(taskDescription) == "string" then
        print("Invalid Task Description. (must be a string)")
        return
    else
      local descLen = string.len(taskDescription)
      if descLen <= 5 then
        print("Task Description must be at least 5 chars")
        return
      end
    end
    local DateNow = os.date("%Y-%m-%d")
    local TasksForDay = tasks[DateNow] or {};
    local TaskID = taskCounter + 1
    if taskName == "" then
        taskName = "UnNamed"
    end
    table.insert(TasksForDay, {
        TaskID = TaskID,
        TaskName = taskName,
        TaskDescription = taskDescription,
        TaskRequiredBy = taskRequiredBy,
    })
    tasks[DateNow] = TasksForDay
    taskCounter = taskCounter + 1
end

local function RemoveTask(taskID)
    if not type(taskID) == "number" then
        error("Invalid Task ID. (must be a number)")
    end
    --- iterate through all dates and tasks and remove the task with the matching ID
    for date, tasks in pairs(tasks) do
        for i, task in ipairs(tasks) do
            if task.TaskID == taskID then
                table.remove(tasks, i)
                return
            end
        end
    end
    error("Task ID not found")
end


--- get tasks that are required by a given date
local function GetTasksRequiredByDate(date)
    if not type(date) == "string" then
        error("Invalid Date. (must be a string)")
    end
    local TasksForDay = {}
    for the_date, the_task in pairs(tasks) do
        for i, task in ipairs(the_task) do
            if task.TaskRequiredBy == the_date then
                table.insert(TasksForDay, task)
            end
        end
    end
    return TasksForDay
end


--- print formatted tasks created on a given date or today if no date is given
local function GetTasksForDate(date)
    if not date then
        date = os.date("%Y-%m-%d")
    end
    local TasksForDay = tasks[date] or {}
    return TasksForDay
end


--- print formatted tasks
local function PrintTasks(task_list)
    for i, task in ipairs(task_list) do
        local line = string.format("%s. Name: %s \n\t %s", task.TaskID, task.TaskName, task.TaskDescription)
        if task.TaskRequiredBy then
            if isDateToday(task.TaskRequiredBy) then
                line = line .. " [Required by: Today]"
            elseif isDateTomorrow(task.TaskRequiredBy) then
                line = line .. " [Required by: Tomorrow]"
            else
                line = line .. " [Required by: " .. task.TaskRequiredBy .. "]"
            end
        end
        print(line)
        print("\n")
    end
end


--- print all tasks by date
local function PrintAllTasks()
    for date, task_list in pairs(tasks) do
        print(date)
        PrintTasks(task_list)
    end
end


--- simple cli for task management

if isFile("tasks.json") then
    LoadTasks()
end

while true do
    print [[
    ===========================================
        Enter Command
            add - add a task
            remove - remove a task
            today - print tasks for today
            tomorrow - print tasks for tomorrow
            all - print all tasks
            clear - clear all tasks
            save - save tasks to file
            exit - exit the program
    ===========================================
    ]]

    local input = io.read()
    local command, args = input:match("(%S+)%s*(.*)")
    if command == "add" then
        print("Enter Task Description")
        local taskDescription = io.read("*l")
        print("Enter Task Required By or just press enter to skip [optional. default: whenever]")
        print("Date format: YYYY-MM-DD")
        local taskRequiredBy = io.read("*l")
        if taskRequiredBy == "" or not taskRequiredBy then
          print("no date entered")
          taskRequiredBy = nil
        else
          --- if the date has passed throw an error
          if hasDatePassed(taskRequiredBy) then
              print("Cannot set a task to be required by a date that has passed")
              print("using: today")
              taskRequiredBy = os.date("%Y-%m-%d")
          end
        end
        print("Enter Task Name or just press enter to skip [optional. default: UnaNamed]")
        local taskName = io.read("*l")
        AddTask(taskDescription, taskRequiredBy, taskName)
    elseif command == "remove" then
        print("Enter Task ID to remove:")
        local taskID = args:match("(%S+)")
        RemoveTask(taskID)
    elseif command == "today" then
        local task_list = GetTasksRequiredByDate(os.date("%Y-%m-%d"))
        PrintTasks(task_list)
    elseif command == "tomorrow" then
        local task_list = GetTasksRequiredByDate(os.date("%Y-%m-%d", os.time() + 86400))
        PrintTasks(task_list)
    elseif command == "all" then
        PrintAllTasks()
    elseif command == "clear" then
        tasks = {}
    elseif command == "save" then
        SaveTasks()
    elseif command == "exit" then
        SaveTasks()
        break
    elseif command == "cat" then
        PrintCat()
    elseif command == "dump" then
        for k,v in pairs(tasks) do
            print(k,v)
        end
    else
        print("Invalid Command")
    end
end
