# options.nvim

A small library to create custom options for your plugins or your configuration.
You can use this library to expose the configuration of your plugins using `:help Set` and `:help
Setlocal` commands, or create an option that will set multiple Vim options in return (e.g see the
example below.).

![demo.gif](assets/demo.gif)

# Example

```lua
local options = require "options"

options.register_option({
    name = "indentsize",
    default = 4,
    type_info = "number",
    source = "buffers",
    buffer_local = true
})

options.register_callback("indentsize", function()
    local isize = options.get_option_value('indentsize',
                                           vim.api.nvim_get_current_buf())
    cmd(string.format("setlocal tabstop=%s softtabstop=%s shiftwidth=%s", isize,
                      isize, isize))
end)

options.register_option({
    name = "scratchpad",
    default = false,
    type_info = "boolean",
    source = "options",
    buffer_local = true
})

options.register_callback("scratchpad", function()
    bo[bufnr].buftype = "nofile"
    bo[bufnr].bufhidden = "hide"
    bo[bufnr].swapfile = false
    bo[bufnr].buflisted = true
    cmd("file scratchpad-" .. s_scratch_buffer_count)
end)
```

# Modeline Support

You can use modeline support to set file specific options:

```yaml
# modeline_test.yaml
family-member:
    name: John
    last_name: Doe

# nvim-options: Setlocal indentsize=4
```

You need to manually call `options.set_modeline(bufnr)` for this to work.

```lua
cmd [[autocmd BufReadPost modeline_test.yaml :lua require"options".set_modeline(vim.api.nvim_get_current_buf())]]
```
