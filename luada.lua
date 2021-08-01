-- https://gist.github.com/tylerneylon/59f4bcf316be525b30ab
--[[ json.lua

A compact pure-Lua JSON library.
The main functions are: json.stringify, json.parse.

## json.stringify:

This expects the following to be true of any tables being encoded:
 * They only have string or number keys. Number keys must be represented as
   strings in json; this is part of the json spec.
 * They are not recursive. Such a structure cannot be specified in json.

A Lua table is considered to be an array if and only if its set of keys is a
consecutive sequence of positive integers starting at 1. Arrays are encoded like
so: `[2, 3, false, "hi"]`. Any other type of Lua table is encoded as a json
object, encoded like so: `{"key1": 2, "key2": false}`.

Because the Lua nil value cannot be a key, and as a table value is considerd
equivalent to a missing key, there is no way to express the json "null" value in
a Lua table. The only way this will output "null" is if your entire input obj is
nil itself.

An empty Lua table, {}, could be considered either a json object or array -
it's an ambiguous edge case. We choose to treat this as an object as it is the
more general type.

To be clear, none of the above considerations is a limitation of this code.
Rather, it is what we get when we completely observe the json specification for
as arbitrary a Lua object as json is capable of expressing.

## json.parse:

This function parses json, with the exception that it does not pay attention to
\u-escaped unicode code points in strings.

It is difficult for Lua to return null as a value. In order to prevent the loss
of keys with a null value in a json string, this function uses the one-off
table value json.null (which is just an empty table) to indicate null values.
This way you can check if a value is null with the conditional
`val == json.null`.

If you have control over the data and are using Lua, I would recommend just
avoiding null values in your data to begin with.

--]]

local json = {}

-- Internal functions.

local function kind_of(obj)
    if type(obj) ~= "table" then
        return type(obj)
    end
    local i = 1
    for _ in pairs(obj) do
        if obj[i] ~= nil then
            i = i + 1
        else
            return "table"
        end
    end
    if i == 1 then
        return "table"
    else
        return "array"
    end
end

local function escape_str(s)
    local in_char = { "\\", '"', "/", "\b", "\f", "\n", "\r", "\t" }
    local out_char = { "\\", '"', "/", "b", "f", "n", "r", "t" }
    for i, c in ipairs(in_char) do
        s = s:gsub(c, "\\" .. out_char[i])
    end
    return s
end

-- Returns pos, did_find; there are two cases:
-- 1. Delimiter found: pos = pos after leading space + delim; did_find = true.
-- 2. Delimiter not found: pos = pos after leading space;     did_find = false.
-- This throws an error if err_if_missing is true and the delim is not found.
local function skip_delim(str, pos, delim, err_if_missing)
    pos = pos + #str:match("^%s*", pos)
    if str:sub(pos, pos) ~= delim then
        if err_if_missing then
            error("Expected " .. delim .. " near position " .. pos)
        end
        return pos, false
    end
    return pos + 1, true
end

-- Expects the given pos to be the first character after the opening quote.
-- Returns val, pos; the returned pos is after the closing quote character.
local function parse_str_val(str, pos, val)
    val = val or ""
    local early_end_error = "End of input found while parsing string."
    if pos > #str then
        error(early_end_error)
    end
    local c = str:sub(pos, pos)
    if c == '"' then
        return val, pos + 1
    end
    if c ~= "\\" then
        return parse_str_val(str, pos + 1, val .. c)
    end
    -- We must have a \ character.
    local esc_map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
    local nextc = str:sub(pos + 1, pos + 1)
    if not nextc then
        error(early_end_error)
    end
    return parse_str_val(str, pos + 2, val .. (esc_map[nextc] or nextc))
end

-- Returns val, pos; the returned pos is after the number's final character.
local function parse_num_val(str, pos)
    local num_str = str:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
    local val = tonumber(num_str)
    if not val then
        error("Error parsing number at position " .. pos .. ".")
    end
    return val, pos + #num_str
end

-- Public values and functions.

function json.stringify(obj, as_key)
    local s = {} -- We'll build the string as an array of strings to be concatenated.
    local kind = kind_of(obj) -- This is 'array' if it's an array or type(obj) otherwise.
    if kind == "array" then
        if as_key then
            error("Can't encode array as key.")
        end
        s[#s + 1] = "["
        for i, val in ipairs(obj) do
            if i > 1 then
                s[#s + 1] = ", "
            end
            s[#s + 1] = json.stringify(val)
        end
        s[#s + 1] = "]"
    elseif kind == "table" then
        if as_key then
            error("Can't encode table as key.")
        end
        s[#s + 1] = "{"
        for k, v in pairs(obj) do
            if #s > 1 then
                s[#s + 1] = ", "
            end
            s[#s + 1] = json.stringify(k, true)
            s[#s + 1] = ":"
            s[#s + 1] = json.stringify(v)
        end
        s[#s + 1] = "}"
    elseif kind == "string" then
        return '"' .. escape_str(obj) .. '"'
    elseif kind == "number" then
        if as_key then
            return '"' .. tostring(obj) .. '"'
        end
        return tostring(obj)
    elseif kind == "boolean" then
        return tostring(obj)
    elseif kind == "nil" then
        return "null"
    else
        error("Unjsonifiable type: " .. kind .. ".")
    end
    return table.concat(s)
end

json.null = {} -- This is a one-off table to represent the null value.

function json.parse(str, pos, end_delim)
    pos = pos or 1
    if pos > #str then
        error("Reached unexpected end of input.")
    end
    local pos = pos + #str:match("^%s*", pos) -- Skip whitespace.
    local first = str:sub(pos, pos)
    if first == "{" then -- Parse an object.
        local obj, key, delim_found = {}, true, true
        pos = pos + 1
        while true do
            key, pos = json.parse(str, pos, "}")
            if key == nil then
                return obj, pos
            end
            if not delim_found then
                error("Comma missing between object items.")
            end
            pos = skip_delim(str, pos, ":", true) -- true -> error if missing.
            obj[key], pos = json.parse(str, pos)
            pos, delim_found = skip_delim(str, pos, ",")
        end
    elseif first == "[" then -- Parse an array.
        local arr, val, delim_found = {}, true, true
        pos = pos + 1
        while true do
            val, pos = json.parse(str, pos, "]")
            if val == nil then
                return arr, pos
            end
            if not delim_found then
                error("Comma missing between array items.")
            end
            arr[#arr + 1] = val
            pos, delim_found = skip_delim(str, pos, ",")
        end
    elseif first == '"' then -- Parse a string.
        return parse_str_val(str, pos + 1)
    elseif first == "-" or first:match("%d") then -- Parse a number.
        return parse_num_val(str, pos)
    elseif first == end_delim then -- End of an object or array.
        return nil, pos + 1
    else -- Parse true, false, or null.
        local literals = { ["true"] = true, ["false"] = false, ["null"] = json.null }
        for lit_str, lit_val in pairs(literals) do
            local lit_end = pos + #lit_str - 1
            if str:sub(pos, lit_end) == lit_str then
                return lit_val, lit_end + 1
            end
        end
        local pos_info_str = "position " .. pos .. ": " .. str:sub(pos, pos + 10)
        error("Invalid json syntax starting at " .. pos_info_str)
    end
end

------------------------------------------------------------------------------
--
-- lua Debug Adapter
--
-- https://microsoft.github.io/debug-adapter-protocol/specification
--
-- # message format(JSON-RPC)
-- Content-Length: length\r\n
-- \r\n
-- byte[length]
------------------------------------------------------------------------------
local args = { ... }
local W
local function logger(...)
    if W then
        W:write(string.format(...))
        W:write("\n")
    end
end
for i, arg in ipairs(args) do
    if arg == "--DEBUG" then
        W = io.open("luada.log", "ab")
    end
end

---@class Breakpoint
---@field id number
---@field source any
---@field line number
---@field verified boolean
local Breakpoint = {
    __tostring = function(self)
        return string.format("<BreakPoint %d: %s:%d, %s>", self.id, self.source.path, self.line, self.verified)
    end,
}
Breakpoint.new = function(id, source, line, verified)
    local instance = {
        id = id,
        source = {
            path = source,
        },
        line = line,
        verified = verified,
    }
    Breakpoint.__index = Breakpoint
    setmetatable(instance, Breakpoint)
    return instance
end

---@class DA
---@field input file*
---@field output file*
---@field next_seq number
---@field queue any[]
---@field running_stack boolean[]
---@field breakpoints Breakpoint[]
---@field next_breakpoint_id number
local DA = {
    enqueue = function(self, action)
        table.insert(self.queue, action)
    end,

    add_breakpoint = function(self, source, line)
        local match = self:match_breakpoint(source, line)
        if match then
            return Breakpoint.new(match.id, match.source.path, match.line, false)
        end

        local bp = Breakpoint.new(self.next_breakpoint_id, source, line, true)
        self.next_breakpoint_id = self.next_breakpoint_id + 1
        table.insert(self.breakpoints, bp)
        return bp
    end,

    match_breakpoint = function(self, source, line)
        for i, b in ipairs(self.breakpoints) do
            self:send_message("output", {
                category = "console",
                output = string.format("#%s:%d <=> %s:%d#", b.source.path, b.line, source, line),
            })
            if b.line == line then
                if b.source.path == source then
                    -- match
                    return b
                end
            end
        end
    end,

    new_message = function(self, msg_type)
        local msg = {
            seq = self.next_seq,
            type = msg_type,
        }
        self.next_seq = self.next_seq + 1
        return msg
    end,

    new_response = function(self, seq, command, body)
        local response = self:new_message("response")
        response["success"] = true
        response["request_seq"] = seq
        response["command"] = command
        if body then
            response["body"] = body
        end
        return response
    end,

    new_event = function(self, event_name, body)
        local event = {
            type = "event",
            event = event_name,
        }
        if body then
            event.body = body
        end
        return event
    end,

    send_event = function(self, event_name, body)
        local event = self:new_event(event_name, body)
        self:send_message(event)
    end,

    push_frame = function(self, stack_level, frame, variables)
        local stackframe = {
            id = stack_level,
            name = frame.name,
            line = frame.currentline,
            column = 1,
        }
        if type(frame.source) == "string" and frame.source:sub(1, 1) == "@" then
            stackframe.source = {
                path = frame.source:sub(2),
            }
        end
        table.insert(self.stackframes, stackframe)

        local scopes = {}
        -- local
        table.insert(scopes, {
            name = "Locals",
            presentationHint = "locals",
            variablesReference = #self.variables + 1,
            expensive = false,
        })
        table.insert(self.variables, variables)
        -- upvalues
        -- globals
        self.scope = {
            [stack_level] = scopes,
        }
    end,

    --
    -- debug.xxx 関数はこの関数内で呼ぶべし。他の関数に入ると stack_level を足す必要がある。
    --
    on_hook = function(self, stack_level, line)
        -- hook_frame
        local hook_frame = debug.getinfo(stack_level, "nSluf")
        if hook_frame.source:sub(-#self.name) == self.name then
            -- skip debugger code
            return
        end

        local source = hook_frame.source
        if source:sub(1, 1) ~= "@" then
            return
        end
        source = source:sub(2)

        local match
        if self.next then
            self:send_event("output", {
                category = "console",
                output = "next!\n",
            })
            self.next = false
        else
            match = self:match_breakpoint(source, line)
            if not match then
                -- not break
                return
            end
            -- hit breakpoint
            self:send_event("output", {
                category = "console",
                output = "break!\n",
            })
        end

        -- clear
        self.stackframes = {}
        self.scope = {}
        self.variables = {}

        -- top
        do
            local variables = {}
            local i = 1
            while true do
                local k, v = debug.getlocal(stack_level, i)
                if not k then
                    break
                end
                -- io.stderr:write(string.format("(%q)[%q = %q]", stack_level, k, v))
                i = i + 1
                if k ~= "(*temporary)" then
                    table.insert(variables, {
                        variablesReference = 0,
                        name = k,
                        value = v,
                        type = type(v),
                    })
                end
            end
            self:push_frame(stack_level, hook_frame, variables)
            stack_level = stack_level + 1
        end

        -- frames
        while true do
            local frame = debug.getinfo(stack_level, "nSluf")
            if not frame then
                break
            end
            if frame.source:sub(-#self.name) == self.name then
                -- skip debugger code
                break
            end

            local variables = {}
            local i = 1
            while true do
                local k, v = debug.getlocal(stack_level, i)
                if not k then
                    break
                end
                -- io.stderr:write(string.format("(%q)[%q = %q]", stack_level, k, v))
                i = i + 1
                table.insert(variables, {
                    name = k,
                    value = v,
                })
            end
            self:push_frame(stack_level, frame, variables)
            stack_level = stack_level + 1
        end

        -- stacktrace & scpopes
        if match then
            self:send_event("stopped", {
                reason = "breakpoint",
                threadId = 0,
                hitBreakpointIds = { match.id },
            })
        else
            self:send_event("stopped", {
                reason = "step",
                threadId = 0,
            })
        end

        -- start nested loop
        io.stderr:write("[!yield!]\n")
        table.insert(self.running_stack, true)
        self:loop()
    end,

    launch = function(self)
        local chunk = loadfile(self.debugee.program)

        setfenv(chunk, {
            print = function(...)
                local msg = ""
                for i, x in ipairs({ ... }) do
                    if i > 1 then
                        msg = msg .. ", "
                    end
                    msg = msg .. string.format("%q", x)
                end

                self:send_event("output", {
                    category = "stdout",
                    output = msg,
                })
            end,
        })

        debug.sethook(function(_, line)
            -- 3 hook
            -- 2 this
            -- 1 on_hook
            self:on_hook(3, line)
        end, "l")

        -- run
        self:send_event("output", {
            category = "console",
            output = string.format("[luada]LAUNCH: %s...\n", self.debugee.program)
        })

        local rc
        local success, err = xpcall(function()
            rc = chunk(unpack(self.debugee.args))
        end, function(err) end)
        if success then
            self:send_event("output", {
                category = "console",
                output = "[luada]EXIT\n",
            })

            -- exit
            self.running_stack[#self.running_stack] = false
            self:send_event("exited", {
                exitCode = rc or 0,
            })
        else
            self:send_event("output", {
                category = "console",
                output = string.format("[luada]%q\n", err),
            })
        end
    end,

    ------------------------------------------------------------------------------
    -- https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Initialize
    -- https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Launch
    -- https://microsoft.github.io/debug-adapter-protocol/specification#Requests_SetBreakpoints
    ------------------------------------------------------------------------------
    on_request = function(self, parsed)
        if parsed.command == "initialize" then
            self:enqueue(function()
                self:send_event("initialized")
            end)
            return self:new_response(parsed.seq, parsed.command, {
                supportsConfigurationDoneRequest = true,
            })
        elseif parsed.command == "launch" then
            self.debugee = {
                program = parsed.arguments.program,
                args = parsed.arguments.args,
            }
            return self:new_response(parsed.seq, parsed.command)
        elseif parsed.command == "setBreakpoints" then
            local breakpoints = {}
            for i, b in ipairs(parsed.arguments.breakpoints) do
                local created = self:add_breakpoint(parsed.arguments.source.path, b.line)
                self:send_event("output", {
                    category = "console",
                    output = string.format("created: %s\n", created),
                })
                if created then
                    setmetatable(created, nil)
                    table.insert(breakpoints, created)
                end
            end
            return self:new_response(parsed.seq, parsed.command, {
                breakpoints = breakpoints,
            })
        elseif parsed.command == "configurationDone" then
            self:enqueue(function()
                self:launch()
            end)
            return self:new_response(parsed.seq, parsed.command)
        elseif parsed.command == "threads" then
            return self:new_response(parsed.seq, parsed.command, {
                threads = {
                    {
                        id = 0,
                        name = "main",
                    },
                },
            })
        elseif parsed.command == "stackTrace" then
            return self:new_response(parsed.seq, parsed.command, {
                stackFrames = self.stackframes,
            })
        elseif parsed.command == "scopes" then
            return self:new_response(parsed.seq, parsed.command, {
                scopes = self.scope[parsed.arguments.frameId],
            })
        elseif parsed.command == "variables" then
            return self:new_response(parsed.seq, parsed.command, {
                variables = self.variables[parsed.arguments.variablesReference],
            })
        elseif parsed.command == "continue" then
            self.running_stack[#self.running_stack] = false
            return self:new_response(parsed.seq, parsed.command)
        elseif parsed.command == "next" then
            self.next = true
            self.running_stack[#self.running_stack] = false
            return self:new_response(parsed.seq, parsed.command)
        else
            error(string.format("unknown command: %q", parsed))
        end
    end,

    on_message = function(self, parsed)
        if parsed.type == "request" then
            return self:on_request(parsed)
        else
            error(string.format("unknown type: %q", parsed))
        end
    end,

    send_message = function(self, message)
        local encoded = json.stringify(message)
        logger("<= %q", encoded)

        if encoded:find("\n") then
            error("contain LF")
        end
        local encoded_length = string.len(encoded)
        local msg = string.format("Content-Length: %d", encoded_length)
        if package.config:sub(1, 1) == "\\" then
            -- windows
            msg = msg .. "\n\n"
        else
            msg = msg .. "\r\n\r\n"
        end
        msg = msg .. encoded
        self.output:write(msg)
        self.output:flush()
    end,

    process_message = function(self)
        -- dequeue
        while #self.queue > 0 do
            local action = table.remove(self.queue, 1)
            action()
        end

        -- read
        local l = self.input:read("*l")

        local m = string.match(l, "Content%-Length: (%d+)")
        local length = tonumber(m)
        self.input:read("*l") -- skip empty line
        local body = self.input:read(length)

        logger("=> %q", body)

        local parsed = json.parse(body)
        local response = self:on_message(parsed)
        if response then
            self:send_message(response)
        end
    end,

    loop = function(self)
        while self.running_stack[#self.running_stack] do
            self:process_message()
        end
        table.remove(self.running_stack)
    end,
}
DA.new = function()
    local instance = {
        name = "luada.lua",
        input = io.stdin,
        output = io.stdout,
        next_seq = 0,
        queue = {},
        running_stack = { true },
        breakpoints = {},
        next_breakpoint_id = 1,
    }
    DA.__index = DA
    setmetatable(instance, DA)
    return instance
end

io.stdout:setvbuf("no", 0)
io.stderr:setvbuf("no", 0)

local da = DA.new()

da:loop()

if W then
    io.close(W)
end
