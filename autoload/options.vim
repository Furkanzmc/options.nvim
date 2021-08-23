function options#complete(arg_lead, L, P)
    return luaeval("require'options'.list_options('" . a:arg_lead . "')")
endfunction

function options#complete_buf_local(arg_lead, L, P)
    return luaeval("require'options'.list_options('" . a:arg_lead . "', true)")
endfunction
