local M = {}

---@class present.Slides
---@field slides present.Slide[]

---@class present.Slide
---@field title string
---@field content string[]

---@class present.Float
---@field win integer
---@field buf integer

---@alias present.Floats {
---     background: present.Float,
---     body: present.Float,
---     header: present.Float,
---     footer: present.Float,
---}

---@param config vim.api.keyset.win_config
---@return { buf: integer, win: integer }
local create_floating_window = function(config)
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, false, config)

    return { buf = buf, win = win }
end

---@param lines string[]
---@return present.Slides
local parse_slides = function(lines)
    local slides = { slides = {} }
    local current_slide = { content = {} }

    for _, line in ipairs(lines) do
        if line:sub(1, 1) == "#" then
            if current_slide.title or #current_slide.content > 0 then
                table.insert(slides.slides, current_slide)
            end
            current_slide = { title = line, content = {} }
        else
            table.insert(current_slide.content, line)
        end
    end
    if current_slide.title or #current_slide.content > 0 then
        table.insert(slides.slides, current_slide)
    end

    return slides
end

---@return { [string]: vim.api.keyset.win_config }
local create_default_window_configs = function()
    local width = vim.o.columns
    local height = vim.o.lines

    return {
        background = {
            relative = "editor",
            width = width,
            height = height,
            style = "minimal",
            col = 0,
            row = 0,
            zindex = 1,
        },
        header = {
            relative = "editor",
            width = width,
            height = 1,
            style = "minimal",
            border = "rounded",
            col = 0,
            row = 0,
            zindex = 4,
        },
        body = {
            relative = "editor",
            width = width - 8,
            height = height - 5,
            style = "minimal",
            col = 8,
            row = 3,
        },
        footer = {
            relative = "editor",
            width = width - 1,
            height = 1,
            style = "minimal",
            col = 1,
            row = height - 2,
            zindex = 2,
        },
    }
end

local state = {
    current_slide = 1,
    restore = {
        cmdheight = {
            original = vim.o.cmdheight,
            present = 0,
        },
        guicursor = {
            original = vim.o.guicursor,
            present = "n:NormalFloat",
        },
        wrap = {
            original = vim.o.wrap,
            present = true,
        },
        breakindent = {
            original = vim.o.breakindent,
            present = true,
        },
        breakindentopt = {
            original = vim.o.breakindentopt,
            present = "list:-1",
        },
    },

    ---@type present.Slides?
    slides = nil,
    ---@type present.Floats
    floats = {},
}

local set_header = function(title)
    local width = vim.o.columns

    local padding = string.rep(" ", (width - #title) / 2)
    local centered = padding .. title

    vim.api.nvim_buf_set_lines(state.floats.header.buf, 0, -1, false, { centered })
end

local set_footer = function(idx)
    local foot = string.format("%u/%u", idx, #state.slides.slides)

    vim.api.nvim_buf_set_lines(state.floats.footer.buf, 0, -1, false, { foot })
end

local set_slide = function(idx)
    local slide = state.slides.slides[idx]

    set_header(slide.title)
    set_footer(idx)
    vim.api.nvim_buf_set_lines(state.floats.body.buf, 0, -1, false, slide.content)
end

M.next_slide = function()
    if not state.slides or state.current_slide == #state.slides.slides then
        return
    end
    state.current_slide = state.current_slide + 1
    set_slide(state.current_slide)
end

M.prev_slide = function()
    if not state.slides or state.current_slide == 1 then
        return
    end
    state.current_slide = state.current_slide - 1
    set_slide(state.current_slide)
end

M.quit_presentation = function()
    if not state.slides then
        return
    end
    pcall(vim.api.nvim_win_close, state.floats.body.win, true)
end

local resize_presentation = function()
    if not state.slides then
        return
    end

    local updated = create_default_window_configs()
    for name, config in pairs(updated) do
        vim.api.nvim_win_set_config(state.floats[name].win, config)
    end
    set_header(state.slides.slides[state.current_slide].title)
    set_footer(state.current_slide)
end

local create_autocmds = function()
    vim.api.nvim_create_autocmd("VimResized", {
        group = vim.api.nvim_create_augroup("present-resized", {}),
        callback = resize_presentation,
    })
end

M.start_presentation = function(opts)
    opts = opts or {}
    opts.bufnr = opts.bufnr or 0

    local windows = create_default_window_configs()

    for name, config in pairs(windows) do
        local win = create_floating_window(config)
        vim.bo[win.buf].filetype = "markdown"
        state.floats[name] = win
    end

    for option, config in pairs(state.restore) do
        vim.opt[option] = config.present
    end

    vim.api.nvim_set_current_win(state.floats.body.win)

    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = state.floats.body.buf,
        callback = function()
            for _, float in pairs(state.floats) do
                pcall(vim.api.nvim_win_close, float.win, true)
            end
            state.slides = nil
            state.current_slide = 1
            for option, config in pairs(state.restore) do
                vim.opt[option] = config.original
            end
        end,
    })

    local keymap_buf = {
        buffer = state.floats.body.buf,
    }

    vim.keymap.set("n", "n", M.next_slide, keymap_buf)
    vim.keymap.set("n", "p", M.prev_slide, keymap_buf)
    vim.keymap.set("n", "q", M.quit_presentation, keymap_buf)

    local lines = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)
    state.slides = parse_slides(lines)

    set_slide(state.current_slide)
end

M.setup = function(opts)
    local _ = opts
    create_autocmds()
    vim.api.nvim_create_user_command("Present", function()
        M.start_presentation({ bufnr = vim.api.nvim_get_current_buf() })
    end, {})
end

return M
