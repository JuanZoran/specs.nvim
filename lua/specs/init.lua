local api, fn = vim.api, vim.fn
local M = {}
local opts = {}

local old_cur
function M.on_cursor_moved()
    local cur = fn.winline() + api.nvim_win_get_position(0)[1]
    if old_cur then
        local jump = math.abs(cur - old_cur)
        if jump >= opts.min_jump then
            M.show_specs()
        end
    end
    old_cur = cur
end

function M.should_show_specs(start_win_id)
    if not api.nvim_win_is_valid(start_win_id) or fn.getcmdpos() ~= 0 then
        return false
    end

    if type(opts.ignore_filetypes) ~= 'table' or type(opts.ignore_buftypes) ~= 'table' then
        return true
    end

    local type, ok
    ok, type = pcall(api.nvim_buf_get_option, 0, 'buftype')
    if ok and opts.ignore_buftypes[type] then
        return false
    end

    ok, type = pcall(api.nvim_buf_get_option, 0, 'filetype')
    if ok and opts.ignore_filetypes[type] then
        return false
    end

    return true
end

function M.show_specs(popup)
    local start_win_id = api.nvim_get_current_win()
    if not M.should_show_specs(start_win_id) then
        return
    end

    local _opts = popup and vim.tbl_deep_extend('force', opts, { popup = popup }) or opts

    local bufh = api.nvim_create_buf(false, true)
    local win_id = api.nvim_open_win(bufh, false, {
        relative = 'cursor',
        width = 1,
        height = 1,
        col = 0,
        row = 0,
        style = 'minimal'
    })
    api.nvim_win_set_option(win_id, 'winhl', 'Normal:' .. _opts.popup.winhl)
    api.nvim_win_set_option(win_id, 'winblend', _opts.popup.blend)

    local cnt = 0
    local config = api.nvim_win_get_config(win_id)
    local timer = vim.loop.new_timer()
    local closed = false

    vim.loop.timer_start(timer, _opts.popup.delay_ms, _opts.popup.inc_ms, vim.schedule_wrap(function()
        if closed then return end
        if api.nvim_get_current_win() ~= start_win_id then
            pcall(vim.loop.close, timer)
            pcall(api.nvim_win_close, win_id, true)

            -- Callbacks might stack up before the timer actually gets closed, track that state
            -- internally here instead
            closed = true
            return
        end

        if api.nvim_win_is_valid(win_id) then
            local bl = _opts.popup.fader(_opts.popup.blend, cnt)
            local dm = _opts.popup.resizer(_opts.popup.width, fn.wincol() - 1, cnt)

            if bl ~= nil then
                api.nvim_win_set_option(win_id, 'winblend', bl)
            end
            if dm ~= nil then
                config['col'][false] = dm[2]
                api.nvim_win_set_config(win_id, config)
                api.nvim_win_set_width(win_id, dm[1])
            end
            if bl == nil and dm == nil then -- Done blending and resizing
                vim.loop.close(timer)
                api.nvim_win_close(win_id, true)
            end
            cnt = cnt + 1
        end
    end))
end

--[[ ▁▁▂▂▃▃▄▄▅▅▆▆▇▇██ ]]
--

function M.linear_fader(blend, cnt)
    if blend + cnt <= 100 then
        return cnt
    end
end

--[[ ⌣/⌢\⌣/⌢\⌣/⌢\⌣/⌢\ ]]
--

function M.sinus_fader(blend, cnt)
    if cnt <= 100 then
        return math.ceil((math.sin(cnt * (1 / blend)) * 0.5 + 0.5) * 100)
    end
end

--[[ ▁▁▁▁▂▂▂▃▃▃▄▄▅▆▇ ]]
--

function M.exp_fader(blend, cnt)
    if blend + math.floor(math.exp(cnt / 10)) <= 100 then
        return blend + math.floor(math.exp(cnt / 10))
    end
end

--[[ ▁▂▃▄▅▆▇█▇▆▅▄▃▂▁ ]]
--

function M.pulse_fader(blend, cnt)
    if cnt < (100 - blend) / 2 then
        return cnt
    elseif cnt < 100 - blend then
        return 100 - cnt
    end
end

--[[ ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ]]
--

function M.empty_fader()
end

--[[ ░░▒▒▓█████▓▒▒░░ ]]
--

function M.shrink_resizer(width, ccol, cnt)
    if width - cnt > 0 then
        return { width - cnt, ccol - (width - cnt) / 2 + 1 }
    end
end

--[[ ████▓▓▓▒▒▒▒░░░░ ]]
--

function M.slide_resizer(width, ccol, cnt)
    if width - cnt > 0 then
        return { width - cnt, ccol }
    end
end

--[[ ███████████████ ]]
--

function M.empty_resizer(width, ccol, cnt)
    if cnt < 100 then
        return { width, ccol - width / 2 }
    end
end

local DEFAULT_OPTS = {
    show_jumps       = true,
    min_jump         = 30,
    popup            = {
        delay_ms = 10,
        inc_ms = 5,
        blend = 10,
        width = 20,
        winhl = 'PMenu',
        fader = M.exp_fader,
        resizer = M.shrink_resizer,
    },
    ignore_filetypes = {},
    ignore_buftypes  = { nofile = true },
}


function M.setup(user_opts)
    opts = vim.tbl_deep_extend('force', DEFAULT_OPTS, user_opts)
    M.create_autocmds()
end

local au_toggle
function M.toggle()
    if au_toggle then
        M.clear_autocmds()
    else
        M.create_autocmds()
    end
end

function M.create_autocmds()
    local group = api.nvim_create_augroup('Specs', { clear = true })
    if opts.show_jumps then
        api.nvim_create_autocmd('CursorHold', {
            group = group,
            callback = M.on_cursor_moved,
        })
    end
    au_toggle = true
end

function M.clear_autocmds()
    api.nvim_clear_autocmds { group = 'Specs' }
    au_toggle = false
end

return M
