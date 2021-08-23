local cmd = vim.cmd

cmd [[command! -nargs=* -complete=customlist,options#complete Set :lua require'options'.run_set_cmd(<q-args>, nil)]]
cmd [[command! -nargs=* -complete=customlist,options#complete_buf_local Setlocal :lua require'options'.run_set_cmd(<q-args>, vim.api.nvim_get_current_buf())]]
