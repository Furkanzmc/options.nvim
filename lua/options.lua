-- TODO
-- [ ] Add support for options.indentsize=4 syntax for init.lua
local vim = vim
local cmd = vim.cmd
local fn = vim.fn
local log = require("options.log")
local typing = require("options.typing")
local M = {}

local s_registered_options = {}
local s_current_options = {}
local s_callbacks = {}
local s_variable_sync_initialized = false
local s_buffer_sync_autocmd_initialized = false

local function init_variable_sync()
    assert(s_variable_sync_initialized == false)

    cmd([[augroup options_nvim_var_watch]])
    cmd([[autocmd!]])
    cmd(
        [[autocmd CmdlineEnter * if v:event.cmdtype == ":" | call luaeval('require"options".check_var_change()') | endif]]
    )
    cmd([[augroup END]])
end

local function set_target_variable(variable, value, bufnr)
    if bufnr == nil then
        vim.g[variable] = value
    else
        vim.api.nvim_buf_set_var(bufnr, variable, value)
    end
end

local function is_target_variable_set(variable, bufnr)
    if bufnr == nil then
        return vim.g[variable] ~= nil
    end

    local exists, _ = pcall(vim.api.nvim_buf_get_var, bufnr, variable)
    return exists
end

local function setup_buffer_var_sync()
    assert(s_buffer_sync_autocmd_initialized == false)

    cmd([[augroup options_nvim_buffer_var_watch]])
    cmd([[autocmd!]])
    cmd([[autocmd BufNew * lua require"options".sync_buffer_vars(vim.api.nvim_get_current_buf())]])
    cmd([[augroup END]])
end

local function get_target_variable_value(variable, bufnr)
    if bufnr ~= nil then
        return vim.g[variable] ~= nil
    end

    local exists, value = pcall(vim.api.nvim_buf_get_var, bufnr, variable)
    assert(exists, "Variable doesn't exist: " .. variable)
    return value
end

local function get_option_info(name)
    if M.is_option_registered(name) == false then
        log.error("options", "This option is not registered: " .. name)
        return nil
    end

    return s_registered_options[name]
end

local function get_buffer_option(name, bufnr)
    assert(bufnr ~= nil, "bufnr has to be valid.")

    local current_option = s_current_options[name]
    if current_option == nil then
        return nil
    end

    local buffers = current_option.buffers
    if buffers == nil then
        return nil
    end

    for _, option in ipairs(buffers) do
        if option.bufnr == bufnr then
            return option
        end
    end

    return nil
end

local function echo_option(name, bufnr)
    local option_info = get_option_info(name)
    local value = M.get_option_value(name, bufnr)
    if type(value) == "table" then
        value = table.concat(value, ",")
    end

    if option_info.buffer_local == true then
        log.info(option_info.source .. "-buflocal", name .. "=" .. tostring(value))
    else
        log.info(option_info.source, name .. "=" .. tostring(value))
    end
end

local function echo_options(bufnr)
    local processed = {}
    local buffer_options = {}
    local global_options = {}

    for key, info in pairs(s_current_options) do
        local value = nil
        local buffer_option = nil
        local option_info = get_option_info(key)
        if bufnr ~= nil and option_info.buffer_local then
            buffer_option = get_buffer_option(key, bufnr)
        end

        if buffer_option ~= nil then
            value = buffer_option.value
        elseif bufnr == nil and option_info.global == true then
            value = info.value
        end

        if value ~= nil then
            local val_str = ""
            if type(value) == "table" then
                val_str = table.concat(value, ",")
            else
                val_str = tostring(value)
            end

            local message = string.rep(" ", 2)
                .. key
                .. "="
                .. val_str
                .. " "
                .. "[source: "
                .. option_info.source
                .. "]"

            table.insert(processed, key)
            if option_info.buffer_local then
                table.insert(buffer_options, message)
            else
                table.insert(global_options, message)
            end
        end
    end

    for key, info in pairs(s_registered_options) do
        local can_echo = false
        if table.index_of(processed, key) == -1 then
            if bufnr ~= nil and info.buffer_local == true then
                can_echo = true
            elseif bufnr == nil and info.global == true then
                can_echo = true
            end

            if can_echo then
                local option_info = get_option_info(key)
                local val_str = ""
                if type(info.default) == "table" then
                    val_str = table.concat(info.default, ",")
                else
                    val_str = tostring(info.default)
                end

                local message = string.rep(" ", 2)
                    .. key
                    .. "="
                    .. val_str
                    .. " "
                    .. "[source: "
                    .. option_info.source
                    .. "]"

                table.insert(processed, key)
                if option_info.buffer_local then
                    table.insert(buffer_options, message)
                else
                    table.insert(global_options, message)
                end
            end
        end
    end

    if #global_options > 0 then
        log.info("global-options", "--\\n" .. table.concat(global_options, "\\n"))
    end

    if #buffer_options > 0 then
        log.info("buffer-options", "--\\n" .. table.concat(buffer_options, "\\n"))
    end
end

local function execute_callbacks(option_name)
    if s_callbacks[option_name] == nil then
        return
    end

    for _, func in ipairs(s_callbacks[option_name]) do
        func()
    end
end

local function split_option_str(option_str)
    local cmps = string.split(option_str, "=")
    local name = cmps[1]
    local value = nil
    if #cmps == 2 then
        value = cmps[2]
    end

    return { name = name, value = value }
end

local function convert_value(value, option_info)
    local converted_value = nil
    if option_info.type_info == "boolean" then
        converted_value = typing.toboolean(value)
    elseif option_info.type_info == "number" then
        converted_value = tonumber(value)
    elseif option_info.type_info == "string" then
        converted_value = tostring(value)
    elseif option_info.type_info == "table" then
        converted_value = string.split(tostring(value), ",")
    elseif option_info.parser ~= nil then
        converted_value = option_info.parser(converted_value)
    end

    return converted_value
end

local function pre_process_set_option(name, value, bufnr)
    if name == "" then
        echo_options(bufnr)
        return true
    end

    if M.is_option_registered(name) == false then
        log.error("options", "This option is not registered: " .. name)
        return true
    end

    if value == nil then
        echo_option(name, bufnr)
        return true
    end

    local option_info = get_option_info(name)
    if option_info.buffer_local == true and bufnr == nil then
        log.warning(
            "options",
            "This is only a local option. Use `:Setlocal " .. name .. "` instead."
        )
        return true
    end

    if option_info.buffer_local ~= true and bufnr ~= nil then
        log.warning("options", "This is only a global option. Use `:Set " .. name .. "` instead.")
        return true
    end

    return false
end

local function set_option(name, value, bufnr)
    if bufnr == 0 then
        bufnr = vim.api.nvim_get_current_buf()
    end

    if pre_process_set_option(name, value, bufnr) then
        return
    end

    local option_info = get_option_info(name)
    local converted_value = convert_value(value, option_info)
    if converted_value == nil then
        log.error("options", "Cannot convert `" .. value .. "` to " .. option_info.type_info .. ".")
        return
    end

    local current_option = s_current_options[name]
    if current_option == nil then
        if bufnr ~= nil then
            s_current_options[name] = {
                value = nil,
                buffers = { { bufnr = bufnr, value = converted_value } },
            }
        else
            s_current_options[name] = { value = converted_value, buffers = {} }
        end

        current_option = s_current_options[name]
        execute_callbacks(name)
    elseif bufnr == nil and current_option.value ~= converted_value then
        current_option.value = converted_value
        execute_callbacks(name)
    elseif bufnr ~= nil then
        local buffer_option = get_buffer_option(name, bufnr)
        if buffer_option ~= nil then
            if buffer_option.value == converted_value then
                return
            end

            buffer_option.value = converted_value
        elseif buffer_option == nil then
            table.insert(
                s_current_options[name].buffers,
                { bufnr = bufnr, value = converted_value }
            )
        end

        execute_callbacks(name)
    end

    if option_info.target_variable ~= nil then
        set_target_variable(option_info.target_variable, converted_value, bufnr)
    end
end

local function check_for_global_var_change()
    local cmd_line = fn.getreg(":")
    if string.match(cmd_line, "let g:") == nil then
        return
    end

    local var_name = string.match(cmd_line, "g:[^%s.=]+")
    var_name = string.gsub(var_name, "g:", "")
    for name, info in pairs(s_registered_options) do
        if info.target_variable == var_name then
            set_option(name, get_target_variable_value(var_name))
            break
        end
    end
end

local function check_for_buffer_var_change()
    local cmd_line = fn.getreg(":")
    if string.match(cmd_line, "let b:") == nil then
        return
    end

    local var_name = string.match(cmd_line, "b:[^%s.=]+")
    var_name = string.gsub(var_name, "b:", "")
    local bufnr = vim.api.nvim_get_current_buf()
    for name, info in pairs(s_registered_options) do
        if info.target_variable == var_name then
            set_option(name, get_target_variable_value(var_name), bufnr)
            break
        end
    end
end

function M.is_option_registered(name)
    return s_registered_options[name] ~= nil
end

function M.get_option_value(name, bufnr)
    if M.is_option_registered(name) == false then
        log.error("options", "This option is not registered: " .. name)
        return nil
    end

    local buffer_option = nil
    if bufnr ~= nil then
        buffer_option = get_buffer_option(name, bufnr)
    end

    if buffer_option ~= nil then
        return buffer_option.value
    elseif s_current_options[name] ~= nil and s_current_options[name].value ~= nil then
        return s_current_options[name].value
    end

    return s_registered_options[name].default
end

function M.register_option(opts)
    if M.is_option_registered(opts.name) then
        log.error("options", "This option is already registered: " .. opts.name)
        return
    end

    assert(not (opts.type_info == nil or opts.type_info == ""), "type_info is a required field.")

    assert(
        type(opts.default) == opts.type_info,
        "Type of the default value does not match type_info: "
            .. type(opts.default)
            .. " != "
            .. opts.type_info
    )

    opts.buffer_local = opts.buffer_local or false
    opts.global = opts.global or not opts.buffer_local
    opts.source = opts.source or ""

    if
        opts.buffer_local
        and opts.target_variable ~= nil
        and not s_buffer_sync_autocmd_initialized
    then
        setup_buffer_var_sync()
        s_buffer_sync_autocmd_initialized = true
    end

    s_registered_options[opts.name] = {
        default = opts.default,
        type_info = opts.type_info,
        source = opts.source,
        buffer_local = opts.buffer_local,
        global = opts.global,
        parser = opts.parser,
        target_variable = opts.target_variable,
    }

    if opts.target_variable ~= nil and s_variable_sync_initialized == false then
        init_variable_sync()
    end

    if
        opts.target_variable ~= nil
        and opts.global
        and is_target_variable_set(opts.target_variable)
    then
        set_option(opts.name, get_target_variable_value(opts.target_variable))
    elseif
        opts.target_variable ~= nil
        and opts.global
        and not is_target_variable_set(opts.target_variable)
    then
        set_target_variable(opts.target_variable, opts.default)
    end
end

function M.run_set_cmd(option_str, bufnr)
    local opt = split_option_str(option_str)
    set_option(opt.name, opt.value, bufnr)
end

function M.set(name, value)
    set_option(name, value)
end

function M.set_local(name, value, bufnr)
    if bufnr == nil then
        log.error("options", "bufnr is required for local options.")
    end

    set_option(name, value, bufnr)
end

function M.list_options(arg_lead, buffer_local)
    local options = {}

    for key, info in pairs(s_registered_options) do
        if buffer_local == true and info.buffer_local == true then
            if string.match(key, "^" .. arg_lead) then
                table.insert(options, key)
            end
        elseif buffer_local ~= true and info.global == true then
            if string.match(key, "^" .. arg_lead) then
                table.insert(options, key)
            end
        end
    end

    return options
end

function M.register_callback(name, func)
    if M.is_option_registered(name) == false then
        log.error("options", "Cannot register callback for unregistered option: " .. name)
        return
    end

    if s_callbacks[name] == nil then
        s_callbacks[name] = { func }
    else
        table.insert(s_callbacks[name], func)
    end
end

function M.set_modeline(bufnr)
    local max_lines = vim.api.nvim_get_option("modelines")

    local last_linenr = fn.line("$")
    if last_linenr == 1 then
        return
    end

    if last_linenr < 2*max_lines then
        -- first and last `max_lines` lines overlap, scan the whole buffer
        for i = 1, last_linenr, 1 do
            local line = vim.api.nvim_buf_get_lines(bufnr, i-1, i, true)[1]
            M.set_modeline_from_string(bufnr, line)
        end
        return
    end

    for i = 1, max_lines, 1 do
        local line = vim.api.nvim_buf_get_lines(bufnr, i-1, i, true)[1]
        M.set_modeline_from_string(bufnr, line)
    end
    for i = last_linenr-max_lines, last_linenr, 1 do
        local line = vim.api.nvim_buf_get_lines(bufnr, i-1, i, true)[1]
        M.set_modeline_from_string(bufnr, line)
    end
end

function M.set_modeline_from_string(bufnr, line)
    if string.match(line, "nvim%-options:") == nil then
        return
    end

    local start_index = string.find(line, "Setlocal")
    if start_index == nil then
        log.error("options", "Only Setlocal is supported.")
        return
    end

    local modeline = string.sub(line, start_index, #line)
    modeline = string.split(string.gsub(modeline, "Setlocal ", ""), " ")
    for _, opt in ipairs(modeline) do
        M.run_set_cmd(opt, bufnr)
    end
end

function M.check_var_change()
    check_for_global_var_change()
    check_for_buffer_var_change()
end

function M.sync_buffer_vars(bufnr)
    for key, info in pairs(s_registered_options) do
        if info.buffer_local == true and info.target_variable ~= nil then
            if is_target_variable_set(key, bufnr) then
                set_option(key, get_target_variable_value(info.target_variable, bufnr), bufnr)
            else
                set_target_variable(info.target_variable, M.get_option_value(key, bufnr), bufnr)
            end
        end
    end
end

return M
