local M = {}
local log = require("options.log")

local s_true_map = {
    ["1"] = true,
    ["t"] = true,
    ["T"] = true,
    ["true"] = true,
    ["TRUE"] = true,
    ["True"] = true,
    ["YES"] = true,
    ["Y"] = true,
    ["y"] = true,
}

local s_false_map = {
    ["0"] = false,
    ["f"] = false,
    ["F"] = false,
    ["false"] = false,
    ["FALSE"] = false,
    ["False"] = false,
    ["NO"] = false,
    ["no"] = false,
    ["n"] = false,
}

local s_type_map = {
    boolean = function(val)
        if s_true_map[val] == true then
            return true
        elseif s_false_map[val] == false then
            return false
        end

        return nil
    end,
    number = function(val)
        return tonumber(val)
    end,
    string = function(val)
        return tostring(val)
    end,
    string_list = function(val)
        assert(type(val) == "string")
        return tostring(val)
    end,
    number_list = function(val)
        assert(type(val) == "string")
        return tostring(val)
    end,
}

function M.convert(value, type_name)
    local converter = s_type_map[type_name]
    if converter == nil then
        log.error("typing", "Cannot find a converter for `" .. value .. "` to " .. type_name .. ".")
    end

    local converted_value = converter(value)

    if converted_value == nil then
        log.error("typing", "Cannot convert `" .. value .. "` to " .. type_name .. ".")
    end

    return converted_value
end

function M.toboolean(str)
    assert(type(str) == "string", "str must be string")

    if s_true_map[str] == true then
        return true
    elseif s_false_map[str] == false then
        return false
    end

    return nil
end

return M
