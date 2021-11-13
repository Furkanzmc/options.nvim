local vim = vim
local cmd = vim.cmd
local M = {}

function M.error(modl, message)
    cmd([[echohl ErrorMsg]])
    cmd('echo "[' .. modl .. "]: " .. message .. '"')
    cmd([[echohl Normal]])
end

function M.warning(modl, message)
    cmd([[echohl WarningMsg]])
    cmd('echo "[' .. modl .. "]: " .. message .. '"')
    cmd([[echohl Normal]])
end

function M.info(modl, message)
    cmd('echo "[' .. modl .. "]: " .. message .. '"')
end

return M
