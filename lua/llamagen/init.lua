local prompts = require("llamagen.prompts")
local M = {}

local api = vim.api
local fn = vim.fn

local globals = {}

local function reset(keep_selection)
    if not keep_selection then
        globals.curr_buffer = nil
        globals.start_pos = nil
        globals.end_pos = nil
    end
    if globals.job_id then
        fn.jobstop(globals.job_id)
        globals.job_id = nil
    end
    globals.result_buffer = nil
    globals.float_win = nil
    globals.result_string = ""
    globals.context = nil
    globals.context_buffer = nil
end

-- retry to check the llama.cpp model names
local function check_server()
    local check = fn.system("curl -s -N http://localhost:1123/v1/models")
    if check and #check > 0 and not check:match("^%s*$") then
        local success, decoded = pcall(fn.json_decode, check)
        if success and decoded and decoded.data and decoded.data[1] then
            return true, decoded.data[1].id
        end
    end
    return false, nil
end

local function wait_for_server_ready()
    while true do
        local is_ready, model_id = check_server()
        if is_ready then
            print("Model loaded successfully: " .. model_id)
            M.update_lualine_status()
            return true
        end
        vim.cmd("sleep 1")
    end
end

-- lualine
local function create_lualine_component()
    local status = "off"

    -- Function to update status that can be called from GenLoadModel
    local function update_status()
        local check = fn.system("curl -s -N http://localhost:1123/v1/models")

        if not check or #check == 0 or check:match("^%s*$") then
            status = "off"
            return
        end

        local success, decoded = pcall(fn.json_decode, check)
        if not success or not decoded or not decoded.data or #decoded.data == 0 then
            status = "off"
            return
        end

        local model_name = decoded.data[1].id
        status = "on:" .. model_name:match("[^/]*$")
    end

    -- Initial status check
    update_status()

    -- Make update_status available globally
    M.update_lualine_status = update_status

    return function()
        return status
    end
end
M.get_lualine_component = create_lualine_component

local status_ok, lualine = pcall(require, "lualine")
if status_ok then
    local current_config = lualine.get_config()
    current_config.sections.lualine_x = vim.list_extend({
        create_lualine_component(),
    }, current_config.sections.lualine_x or {})
    lualine.setup(current_config)
end

local function trim_table(tbl)
    local start, finish = 1, #tbl
    while start <= finish and tbl[start]:match("^%s*$") do
        start = start + 1
    end
    while finish >= start and tbl[finish]:match("^%s*$") do
        finish = finish - 1
    end
    return { unpack(tbl, start, finish) }
end

local default_options = {
    host = "localhost",
    port = "8080",
    file = false,
    debug = false,
    body = { max_tokens = -1, stream = true, temperature = 0.5 },
    show_prompt = false,
    show_model = false,
    quit_map = "q",
    retry_map = "<c-r>",
    hidden = false,
    command = function(options)
        local check = fn.system("curl -s http://" .. options.host .. ":" .. options.port .. "/v1/models")
        if check and #check > 0 then
            local success, decoded = pcall(fn.json_decode, check)
            if success and decoded and decoded.data and #decoded.data > 0 then
                if decoded.data[1].id then
                    options.model = decoded.data[1].id
                end
                return "curl --silent --no-buffer -X POST http://"
                    .. options.host
                    .. ":"
                    .. options.port
                    .. "/v1/chat/completions -H 'Content-Type: application/json' -d $body"
            end
        end
        -- Start llama-server first, then check connection
        fn.system("llama-server")
        return "curl --silent --no-buffer -X POST http://"
            .. options.host
            .. ":"
            .. options.port
            .. "/v1/chat/completions -H 'Content-Type: application/json' -d $body"
    end,
    json_response = true,
    display_mode = "float",
    no_auto_close = false,
    init = function() end,
    -- Update list_models function:
    list_models = function(options)
        -- Check the model names in local directory
        local response = fn.systemlist("find ~/.local/share/AI-Models -name '*.gguf'")

        if response and #response > 0 then
            local models = {}
            local paths = {}
            for _, path in ipairs(response) do
                local model = fn.fnamemodify(path, ":t")
                table.insert(models, model)
                paths[model] = path
            end
            table.sort(models)
            return { display = models, paths = paths }
        end
        print("Could not fetch models. Please verify llama.cpp installation.")
        return {}
    end,
    result_filetype = "markdown",
}
for k, v in pairs(default_options) do
    M[k] = v
end

M.setup = function(opts)
    for k, v in pairs(opts) do
        M[k] = v
    end
end

local function close_window(opts)
    local lines = {}
    if opts.extract then
        local extracted = globals.result_string:match(opts.extract)
        if not extracted then
            if not opts.no_auto_close then
                api.nvim_win_hide(globals.float_win)
                if globals.result_buffer ~= nil then
                    api.nvim_buf_delete(globals.result_buffer, { force = true })
                end
                reset()
            end
            return
        end
        lines = vim.split(extracted, "\n", { trimempty = true })
    else
        lines = vim.split(globals.result_string, "\n", { trimempty = true })
    end
    lines = trim_table(lines)
    api.nvim_buf_set_text(
        globals.curr_buffer,
        globals.start_pos[2] - 1,
        globals.start_pos[3] - 1,
        globals.end_pos[2] - 1,
        globals.end_pos[3] > globals.start_pos[3] and globals.end_pos[3] or globals.end_pos[3] - 1,
        lines
    )
    -- in case another replacement happens
    globals.end_pos[2] = globals.start_pos[2] + #lines - 1
    globals.end_pos[3] = string.len(lines[#lines])
    if not opts.no_auto_close then
        if globals.float_win ~= nil then
            api.nvim_win_hide(globals.float_win)
        end
        if globals.result_buffer ~= nil then
            api.nvim_buf_delete(globals.result_buffer, { force = true })
        end
        reset()
    end
end

local function get_window_options(opts)
    local width = vim.o.columns
    local height = math.floor(vim.o.lines / 2)

    local result = {
        relative = "editor",
        width = width,
        height = height,
        row = 1,
        col = 0,
        style = "minimal",
        border = "rounded",
        zindex = 50,
    }

    if vim.version().minor >= 10 then
        result.hide = opts.hidden
    end

    return result
end

local function write_to_buffer(lines)
    if not (globals.result_buffer and api.nvim_buf_is_valid(globals.result_buffer)) then
        return
    end

    local all_lines = api.nvim_buf_get_lines(globals.result_buffer, 0, -1, false)
    local last_row = #all_lines
    local last_col = #all_lines[last_row]
    local text = table.concat(lines or {}, "\n")

    api.nvim_buf_set_option(globals.result_buffer, "modifiable", true)
    api.nvim_buf_set_text(globals.result_buffer, last_row - 1, last_col, last_row - 1, last_col, vim.split(text, "\n"))

    if globals.float_win and api.nvim_win_is_valid(globals.float_win) then
        local cursor_pos = api.nvim_win_get_cursor(globals.float_win)
        if cursor_pos[1] == last_row then
            api.nvim_win_set_cursor(globals.float_win, { last_row + #lines - 1, 0 })
        end
    end
end

local function create_window(cmd, opts)
    -- Clear context when creating new window
    globals.context = nil
    globals.context_buffer = nil
    -- Create buffer and show "Thinking..." immediately
    globals.result_buffer = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(globals.result_buffer, 0, -1, false, { "Thinking...", "" })

    local function setup_window()
        globals.result_buffer = fn.bufnr("%")
        globals.float_win = fn.win_getid()
        api.nvim_set_option_value("filetype", opts.result_filetype, { buf = globals.result_buffer })
        api.nvim_set_option_value("buftype", "nofile", { buf = globals.result_buffer })
        api.nvim_set_option_value("wrap", true, { win = globals.float_win })
        api.nvim_set_option_value("linebreak", true, { win = globals.float_win })
        api.nvim_set_option_value("modifiable", true, { buf = globals.result_buffer })

        -- Add Ctrl+Enter mapping for submitting new prompts
        vim.keymap.set({ "i", "n" }, "<C-CR>", function()
            local current_line = api.nvim_get_current_line()
            M.exec({ prompt = current_line })
        end, { buffer = globals.result_buffer })
    end

    local display_mode = opts.display_mode or M.display_mode
    if display_mode == "float" then
        if globals.result_buffer then
            api.nvim_buf_delete(globals.result_buffer, { force = true })
        end
        local win_opts = vim.tbl_deep_extend("force", get_window_options(opts), opts.win_config)
        globals.result_buffer = api.nvim_create_buf(false, true)
        globals.float_win = api.nvim_open_win(globals.result_buffer, true, win_opts)
        setup_window()
    elseif display_mode == "horizontal-split" then
        vim.cmd("split llamagen.nvim")
        setup_window()
    else
        vim.cmd("vnew llamagen.nvim")
        setup_window()
    end
    vim.keymap.set("n", "<esc>", function()
        if globals.job_id then
            fn.jobstop(globals.job_id)
        end
    end, { buffer = globals.result_buffer })
    vim.keymap.set("n", M.quit_map, "<cmd>quit<cr>", { buffer = globals.result_buffer })
    vim.keymap.set("n", M.retry_map, function()
        local buf = 0 -- Current buffer
        if globals.job_id then
            fn.jobstop(globals.job_id)
            globals.job_id = nil
        end
        api.nvim_buf_set_option(buf, "modifiable", true)
        api.nvim_buf_set_lines(buf, 0, -1, false, {})
        api.nvim_buf_set_option(buf, "modifiable", false)
        -- api.nvim_win_close(0, true)
        M.run_command(cmd, opts)
    end, { buffer = globals.result_buffer })
end

M.exec = function(options)
    local opts = vim.tbl_deep_extend("force", M, options)
    if opts.hidden then
        -- the only reasonable thing to do if no output can be seen
        opts.display_mode = "float" -- uses the `hide` option
        opts.replace = true
    end

    if type(opts.init) == "function" then
        opts.init(opts)
    end

    if globals.result_buffer ~= fn.winbufnr(0) then
        globals.curr_buffer = fn.winbufnr(0)
        local mode = opts.mode or fn.mode()
        if mode == "v" or mode == "V" then
            globals.start_pos = fn.getpos("'<")
            globals.end_pos = fn.getpos("'>")
            local max_col = api.nvim_win_get_width(0)
            if globals.end_pos[3] > max_col then
                globals.end_pos[3] = fn.col("'>") - 1
            end -- in case of `V`, it would be maxcol instead
        else
            local cursor = fn.getpos(".")
            globals.start_pos = cursor
            globals.end_pos = globals.start_pos
        end
    end

    local content
    if globals.start_pos == globals.end_pos then
        -- get text from whole buffer
        content = table.concat(api.nvim_buf_get_lines(globals.curr_buffer, 0, -1, false), "\n")
    else
        content = table.concat(
            api.nvim_buf_get_text(
                globals.curr_buffer,
                globals.start_pos[2] - 1,
                globals.start_pos[3] - 1,
                globals.end_pos[2] - 1,
                globals.end_pos[3],
                {}
            ),
            "\n"
        )
    end
    local function substitute_placeholders(input)
        if not input then
            return input
        end
        local text = input
        if string.find(text, "%$input") then
            local answer = fn.input("Prompt: ")
            text = string.gsub(text, "%$input", answer)
        end

        text = string.gsub(text, '%$register_([%w*+:/"])', function(r_name)
            local register = fn.getreg(r_name)
            if not register or register:match("^%s*$") then
                error("Prompt uses $register_" .. rname .. " but register " .. rname .. " is empty")
            end
            return register
        end)

        if string.find(text, "%$register") then
            local register = fn.getreg('"')
            if not register or register:match("^%s*$") then
                error("Prompt uses $register but yank register is empty")
            end

            text = string.gsub(text, "%$register", register)
        end

        content = string.gsub(content, "%%", "%%%%")
        text = string.gsub(text, "%$text", content)
        text = string.gsub(text, "%$filetype", vim.bo.filetype)
        return text
    end

    local prompt = opts.prompt

    if type(prompt) == "function" then
        prompt = prompt({ content = content, filetype = vim.bo.filetype })
        if type(prompt) ~= "string" or string.len(prompt) == 0 then
            return
        end
    end

    prompt = substitute_placeholders(prompt)
    opts.extract = substitute_placeholders(opts.extract)
    prompt = string.gsub(prompt, "%%", "%%%%")

    globals.result_string = ""

    local cmd

    opts.json = function(body, shellescape)
        local json = fn.json_encode(body)
        if shellescape then
            json = fn.shellescape(json)
            if vim.o.shell == "cmd.exe" then
                json = string.gsub(json, '\\""', '\\\\\\"')
            end
        end
        return json
    end

    opts.prompt = prompt

    if type(opts.command) == "function" then
        cmd = opts.command(opts)
    else
        cmd = M.command
    end

    if string.find(cmd, "%$prompt") then
        local prompt_escaped = fn.shellescape(prompt)
        cmd = string.gsub(cmd, "%$prompt", prompt_escaped)
    end
    cmd = string.gsub(cmd, "%$model", opts.model)
    if string.find(cmd, "%$body") then
        local body = vim.tbl_extend("force", { model = opts.model, stream = true }, opts.body)
        local messages = {}
        if globals.context then
            messages = globals.context
        end
        -- Add new prompt to the context
        table.insert(messages, { role = "user", content = prompt })
        body.messages = messages

        if opts.file ~= nil then
            local json = opts.json(body, false)
            globals.temp_filename = os.tmpname()
            local fhandle = io.open(globals.temp_filename, "w")
            fhandle:write(json)
            fhandle:close()
            cmd = string.gsub(cmd, "%$body", "@" .. globals.temp_filename)
        else
            local json = opts.json(body, true)
            cmd = string.gsub(cmd, "%$body", json)
        end
    end

    if globals.context ~= nil then
        write_to_buffer({ "", "", "---", "" })
    end

    M.run_command(cmd, opts)
end

M.run_command = function(cmd, opts)
    -- vim.print('run_command', cmd, opts)
    if globals.result_buffer == nil or globals.float_win == nil or not api.nvim_win_is_valid(globals.float_win) then
        create_window(cmd, opts)
        if opts.show_model then
            write_to_buffer({ "# Chat with " .. opts.model, "" })
        end
    end
    local partial_data = ""
    if opts.debug then
        print(cmd)
    end

    globals.job_id = fn.jobstart(cmd, {
        -- stderr_buffered = opts.debug,
        on_stdout = function(_, data, _)
            -- window was closed, so cancel the job
            if not globals.float_win or not api.nvim_win_is_valid(globals.float_win) then
                if globals.job_id then
                    fn.jobstop(globals.job_id)
                end
                if globals.result_buffer then
                    api.nvim_buf_delete(globals.result_buffer, { force = true })
                end
                reset()
                return
            end
            if opts.debug then
                vim.print("Response data: ", data)
            end
            for _, line in ipairs(data) do
                partial_data = partial_data .. line
                if line:sub(-1) == "}" then
                    partial_data = partial_data .. "\n"
                end
            end

            local lines = vim.split(partial_data, "\n", { trimempty = true })

            partial_data = table.remove(lines) or ""

            for _, line in ipairs(lines) do
                Process_response(line, opts.json_response)
            end

            if partial_data:sub(-1) == "}" then
                Process_response(partial_data, opts.json_response)
                partial_data = ""
            end
        end,
        on_stderr = function(_, data, _)
            if opts.debug then
                -- window was closed, so cancel the job
                if not globals.float_win or not api.nvim_win_is_valid(globals.float_win) then
                    if globals.job_id then
                        fn.jobstop(globals.job_id)
                    end
                    return
                end

                if data == nil or #data == 0 then
                    return
                end

                globals.result_string = globals.result_string .. table.concat(data, "\n")
                local lines = vim.split(globals.result_string, "\n")
                write_to_buffer(lines)
            end
        end,
        on_exit = function(_, b)
            if b == 0 and opts.replace and globals.result_buffer then
                close_window(opts)
            end
        end,
    })

    local group = api.nvim_create_augroup("llamagen", { clear = true })
    api.nvim_create_autocmd("WinClosed", {
        buffer = globals.result_buffer,
        group = group,
        callback = function()
            if globals.job_id then
                fn.jobstop(globals.job_id)
            end
            if globals.result_buffer then
                api.nvim_buf_delete(globals.result_buffer, { force = true })
            end
            reset(true) -- keep selection in case of subsequent retries
        end,
    })

    if opts.show_prompt then
        local lines = vim.split(opts.prompt, "\n")
        local short_prompt = {}
        for i = 1, #lines do
            lines[i] = "> " .. lines[i]
            table.insert(short_prompt, lines[i])
            if i >= 3 and opts.show_prompt ~= "full" then
                if #lines > i then
                    table.insert(short_prompt, "...")
                end
                break
            end
        end
        local heading = "#"
        if M.show_model then
            heading = "##"
        end
        write_to_buffer({
            heading .. " Prompt:",
            "",
            table.concat(short_prompt, "\n"),
            "",
            "---",
            "",
        })
    end

    api.nvim_buf_attach(globals.result_buffer, false, {
        on_detach = function()
            globals.result_buffer = nil
        end,
    })
end

M.win_config = {}

M.prompts = prompts
local function select_prompt(cb)
    local promptKeys = {}
    for key, _ in pairs(M.prompts) do
        table.insert(promptKeys, key)
    end
    table.sort(promptKeys)
    vim.ui.select(promptKeys, {
        prompt = "Prompt:",
        format_item = function(item)
            return table.concat(vim.split(item, "_"), " ")
        end,
    }, function(item)
        cb(item)
    end)
end

api.nvim_create_user_command("llamagen", function(arg)
    local mode
    if arg.range == 0 then
        mode = "n"
    else
        mode = "v"
    end
    if arg.args ~= "" then
        local prompt = M.prompts[arg.args]
        if not prompt then
            print("Invalid prompt '" .. arg.args .. "'")
            return
        end
        local p = vim.tbl_deep_extend("force", { mode = mode }, prompt)
        return M.exec(p)
    end

    select_prompt(function(item)
        if not item then
            return
        end
        local p = vim.tbl_deep_extend("force", { mode = mode }, M.prompts[item])
        M.exec(p)
    end)
end, {
    range = true,
    nargs = "?",
    complete = function(ArgLead)
        local promptKeys = {}
        for key, _ in pairs(M.prompts) do
            if key:lower():match("^" .. ArgLead:lower()) then
                table.insert(promptKeys, key)
            end
        end
        table.sort(promptKeys)
        return promptKeys
    end,
})

function Process_response(str, json_response)
    if #str == 0 then return end
    
    if json_response then
        if str:sub(1, 6) == "data: " then
            str = str:sub(7)
        end

        local ok, result = pcall(vim.fn.json_decode, str)
        if ok and result and result.choices then
            local choice = result.choices[1]
            local delta = choice.delta
            if delta and delta.content then
                local text = delta.content
                globals.context = globals.context or {}
                globals.context_buffer = (globals.context_buffer or "") .. text

                if delta.content == "" then
                    table.insert(globals.context, {
                        role = "assistant",
                        content = globals.context_buffer,
                    })
                    globals.context_buffer = ""
                    write_to_buffer({"\n", "---", "# Prompt: \n"})

                    if globals.float_win and api.nvim_win_is_valid(globals.float_win) then
                        local line_count = api.nvim_buf_line_count(globals.result_buffer)
                        api.nvim_win_set_cursor(globals.float_win, {line_count, 1})
                        vim.cmd("startinsert")
                    end
                end
                
                globals.result_string = globals.result_string .. text
                write_to_buffer(vim.split(text, "\n"))
            end
        end
    end
end

api.nvim_create_user_command("GenUnloadModel", function()
    local response = fn.system("curl -s http://" .. M.host .. ":" .. M.port .. "/v1/models")
    local success, decoded = pcall(fn.json_decode, response)
    if success and decoded and decoded.data and #decoded.data > 0 then
        local model_id = decoded.data[1].id
        -- Kill llama-server process
        fn.system("pkill llama-server")
        print("Stopped llama-server with model: " .. model_id)
        M.update_lualine_status()
    end
end, {})

api.nvim_create_user_command("GenLoadModel", function()
    fn.system("pkill llama-server")
    local models = M.list_models(M)

    vim.ui.select(models.display, { prompt = "Select model to load:" }, function(item)
        if item ~= nil then
            print("Starting server with model: " .. item)
            fn.system(
                "nohup llama-server -ngl 35 --keep -1 --port 1123 -m " .. models.paths[item] .. " > /dev/null 2>&1 &"
            )
            wait_for_server_ready(3000) -- 30 second timeout
        end
    end)
end, {})

return M
