--[[
download.lua -- download the stream that is currently playing.

Ctrl+d (or `script-binding download/download`) saves the CURRENT video with
yt-dlp, at the quality mpv already negotiated for playback.

  * network streams only (http/https/ytdl://) -- local files are ignored
  * format = file-local-options/ytdl-format, then ytdl-format, then bv*+ba/b
  * destination = script-opts/download.conf `download_dir` (default
    ~/Videos/mpv-downloads), template `%(title)s [%(id)s].%(ext)s`
  * never overwrites: an existing file becomes `... [2].mp4`, `... [3].mp4`
  * runs asynchronously, so playback never stalls
  * live progress is read from a yt-dlp log file that a little .cmd wrapper
    writes while yt-dlp runs (stdout is only captured at exit, so it cannot
    be used for live updates)

Logging goes through msg.info/msg.error only.
]]

local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'
local opt = require 'mp.options'

local o = {
    -- Where downloads go. `~` expands to the user profile.
    download_dir = '~/Videos/mpv-downloads',
    -- Extra yt-dlp args, space separated.
    extra_args = '',
}
opt.read_options(o, 'download')

local DEFAULT_FORMAT = 'bv*+ba/b'
local PROGRESS_TAG   = 'DLP|'
local TICK           = 0.2          -- seconds between OSD refreshes
local PROGRESS_TPL   = PROGRESS_TAG ..
    '%(progress.downloaded_bytes)s|%(progress.total_bytes)s|' ..
    '%(progress.total_bytes_estimate)s|%(progress._percent_str)s|' ..
    '%(progress.eta)s|%(progress.speed)s'

-- ------------------------------------------------------------------ state --
local busy  = false
local timer = nil
local cur   = nil     -- state of the running download

local function show(text, dur)
    mp.osd_message(text, dur or 3)
end

local function trim(s)
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- cmd.exe and os.rename want backslashes; utils.join_path() returns '/'.
local function native(p)
    return (p:gsub('/', '\\'))
end

local function split(s, sep)
    local out = {}
    for piece in (s .. sep):gmatch('(.-)' .. sep) do
        out[#out + 1] = piece
    end
    return out
end

local function fmt_bytes(n)
    if n >= 1048576 then return string.format('%.1f MiB', n / 1048576) end
    if n >= 1024 then return string.format('%.0f KiB', n / 1024) end
    return string.format('%d B', n)
end

-- --------------------------------------------------------------- settings --
local function home_dir()
    return os.getenv('USERPROFILE') or os.getenv('HOME') or ''
end

local function expand_path(p)
    p = trim(p or '')
    if p == '' then p = '~/Videos/mpv-downloads' end
    local home = home_dir()
    if home ~= '' then
        p = p:gsub('^~$', function() return home end)
        p = p:gsub('^~[\\/]', function() return home .. '\\' end)
        p = p:gsub('%%USERPROFILE%%', function() return home end)
    end
    p = p:gsub('/', '\\')
    if #p > 3 then p = p:gsub('\\+$', '') end
    return p
end

local function temp_dir()
    local t = os.getenv('TEMP') or os.getenv('TMP') or home_dir()
    if not t or t == '' then t = mp.get_property('config-dir') or '.' end
    if #t > 3 then t = t:gsub('\\+$', '') end
    return t
end

local function ensure_dir(dir)
    local info = utils.file_info(dir)
    if info then return info.is_dir == true end
    local ok = pcall(function()
        mp.command_native({
            name = 'subprocess',
            args = { 'cmd.exe', '/d', '/c', 'mkdir', native(dir) },
            playback_only = false,
            capture_stdout = true,
            capture_stderr = true,
        })
    end)
    info = ok and utils.file_info(dir) or nil
    return info ~= nil and info.is_dir == true
end

local ffmpeg_checked, ffmpeg_path = false, nil
local function ffmpeg_location()
    if ffmpeg_checked then return ffmpeg_path end
    ffmpeg_checked = true
    local ok, dirs = pcall(utils.get_env_list, 'PATH')
    if ok and type(dirs) == 'table' then
        for _, d in ipairs(dirs) do
            if d ~= '' then
                local p = utils.join_path(d, 'ffmpeg.exe')
                if utils.file_info(p) then
                    ffmpeg_path = p
                    break
                end
            end
        end
    end
    return ffmpeg_path
end

-- "a b \"c d\"" -> { "a", "b", "c d" }
local function split_args(s)
    local out, i, n = {}, 1, #s
    while i <= n do
        local c = s:sub(i, i)
        if c == '"' or c == "'" then
            local j = s:find(c, i + 1, true) or (n + 1)
            out[#out + 1] = s:sub(i + 1, j - 1)
            i = j + 1
        elseif c:match('%s') then
            i = i + 1
        else
            local j = i
            while j <= n do
                local d = s:sub(j, j)
                if d:match('%s') or d == '"' or d == "'" then break end
                j = j + 1
            end
            out[#out + 1] = s:sub(i, j - 1)
            i = j
        end
    end
    return out
end

-- ------------------------------------------------------------------- url ---
local function url_from_hook()
    -- ytdl_hook leaves its `yt-dlp -J` output in user-data while a file plays.
    local ok, res = pcall(mp.get_property_native,
                          'user-data/mpv/ytdl/json-subprocess-result')
    if not ok or type(res) ~= 'table' or type(res.stdout) ~= 'string' then
        return nil
    end
    local ok2, j = pcall(utils.parse_json, res.stdout)
    if ok2 and type(j) == 'table' then
        return j.webpage_url or j.original_url
    end
    return nil
end

local function stream_url()
    local p = mp.get_property('path', '')
    if type(p) ~= 'string' or p == '' then return nil end
    local low = p:lower()
    if low:match('^ytdl://') then return p:sub(8) end
    if p:match('^edl://') then return url_from_hook() end
    if low:match('^https?://') then
        -- A resolved direct stream is not a stable download target; prefer
        -- the page URL that ytdl_hook resolved it from.
        if low:match('googlevideo%.com') or low:match('%.m3u8') or low:match('%.mpd') then
            return url_from_hook() or p
        end
        return p
    end
    return nil
end

local function current_format()
    local f = mp.get_property('file-local-options/ytdl-format', '')
    if type(f) ~= 'string' or trim(f) == '' then
        f = mp.get_property('ytdl-format', '')
    end
    if type(f) ~= 'string' or trim(f) == '' then
        f = DEFAULT_FORMAT
    end
    return trim(f)
end

-- ----------------------------------------------------------------- batch ---
-- cmd.exe expands %PAIR%; a literal percent must be doubled in a .cmd file.
local function bat_escape(s)
    s = s:gsub('%%', function() return '%%' end)
    return '"' .. s .. '"'
end

local function write_batch(path, args, logfile)
    local f = io.open(path, 'wb')
    if not f then return false end
    f:write('@echo off\r\n')
    local parts = {}
    for _, a in ipairs(args) do parts[#parts + 1] = bat_escape(a) end
    f:write(table.concat(parts, ' '), ' > ', bat_escape(logfile), ' 2>&1\r\n')
    f:write('echo YTDLP_EXIT=%ERRORLEVEL% >> ', bat_escape(logfile), '\r\n')
    f:close()
    return true
end

-- -------------------------------------------------------------- progress ---
local function apply_progress(st, line)
    local f = split(line:sub(#PROGRESS_TAG + 1), '|')
    local downloaded = tonumber(f[1])
    local total      = tonumber(f[2]) or tonumber(f[3])
    local pct        = tonumber((f[4] or ''):match('([%d%.]+)'))
    local speed      = tonumber(f[6])

    if downloaded and total and total > 0 then
        pct = downloaded / total * 100
    end
    if pct then
        pct = math.floor(math.max(0, math.min(100, pct)) + 0.5)
    end
    st.pct        = pct
    st.downloaded = downloaded
    st.speed      = speed
end

-- Reads everything appended to the log since the last call. Returns the
-- complete lines; a trailing partial line is kept for the next call.
local function consume_log(st)
    if not st or not st.log then return {} end
    local f = io.open(st.log, 'rb')
    if not f then return {} end
    f:seek('set', st.pos)
    local data = f:read('*a') or ''
    st.pos = f:seek()
    f:close()
    if data == '' and (not st.pending or st.pending == '') then return {} end

    local buf = (st.pending or '') .. data
    local lines, start = {}, 1
    while true do
        local a, b = buf:find('[\r\n]', start)
        if not a then break end
        lines[#lines + 1] = buf:sub(start, a - 1)
        if buf:sub(a, b) == '\r' and buf:sub(b + 1, b + 1) == '\n' then
            b = b + 1
        end
        start = b + 1
    end
    st.pending = buf:sub(start)
    return lines
end

local function progress_text()
    local head
    if cur.pct then
        head = string.format('Downloading... %d%%', cur.pct)
    elseif cur.downloaded then
        head = 'Downloading... ' .. fmt_bytes(cur.downloaded)
    else
        head = 'Downloading...'
    end
    if cur.speed and cur.speed > 0 then
        head = head .. '  ' .. fmt_bytes(cur.speed) .. '/s'
    end
    return head
end

local function stop_timer()
    if timer then
        timer:kill()
        timer = nil
    end
end

local function on_tick()
    if not cur then stop_timer(); return end
    for _, line in ipairs(consume_log(cur)) do
        if line:sub(1, #PROGRESS_TAG) == PROGRESS_TAG then
            apply_progress(cur, line)
        end
    end
    local text = progress_text()
    if text ~= cur.last_text then
        cur.last_text = text
    end
    -- Redraw on every tick: the message must stay on screen while yt-dlp
    -- is still extracting (no progress numbers yet).  Stay quiet for a
    -- moment after "Already downloading" so that message stays readable.
    if not cur.mute_until or mp.get_time() >= cur.mute_until then
        mp.osd_message(text, 1)
    end
end

-- --------------------------------------------------------------- results ---
local function read_log_all(path)
    local f = io.open(path, 'rb')
    if not f then return '' end
    local data = f:read('*a') or ''
    f:close()
    return data
end

local function first_error(data)
    for line in data:gmatch('[^\r\n]+') do
        if line:match('^%s*ERROR') or line:match('ERROR:') then
            return trim(line)
        end
    end
    local last
    for line in data:gmatch('[^\r\n]+') do
        if trim(line) ~= '' then last = trim(line) end
    end
    return last or 'unknown error'
end

local function pick_output(dir)
    local names = utils.readdir(dir, 'files') or {}
    local best, best_size = nil, -1
    for _, n in ipairs(names) do
        if not n:match('%.part$') and not n:match('%.ytdl$') and not n:match('%.temp$') then
            local info = utils.file_info(utils.join_path(dir, n))
            if info and not info.is_dir and (info.size or 0) > best_size then
                best, best_size = n, info.size or 0
            end
        end
    end
    return best
end

local function unique_target(dir, name)
    local base, ext = name:match('^(.*)(%.[^%.]+)$')
    if not base or base == '' then base, ext = name, '' end
    local target = native(utils.join_path(dir, name))
    if not utils.file_info(target) then return target end
    for i = 2, 99 do
        target = native(utils.join_path(dir, string.format('%s [%d]%s', base, i, ext)))
        if not utils.file_info(target) then return target end
    end
    return nil
end

local function move_file(src, dst)
    if os.rename(native(src), native(dst)) then return true end
    local ok, r = pcall(function()
        return mp.command_native({
            name = 'subprocess',
            args = { 'cmd.exe', '/d', '/c', 'move', '/y', native(src), native(dst) },
            playback_only = false,
            capture_stdout = true,
            capture_stderr = true,
        })
    end)
    return ok and type(r) == 'table' and r.status == 0
end

local function remove_dir_async(dir)
    mp.command_native_async({
        name = 'subprocess',
        args = { 'cmd.exe', '/d', '/c', 'rmdir', '/s', '/q', native(dir) },
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
    }, function() end)
end

-- ---------------------------------------------------------------- finish ---
local function finish(success, result, error)
    local st = cur
    stop_timer()
    busy = false
    cur = nil

    if not st then return end

    -- drain whatever the last tick did not see
    for _, line in ipairs(consume_log(st)) do
        if line:sub(1, #PROGRESS_TAG) == PROGRESS_TAG then
            apply_progress(st, line)
        end
    end

    local status = (type(result) == 'table' and result.status) or -1
    local logdata = read_log_all(st.log)

    if not success or status ~= 0 then
        local reason = error or first_error(logdata)
        reason = trim(reason or 'unknown error')
        msg.error('download failed (status ' .. tostring(status) .. '): ' .. reason)
        msg.error('yt-dlp log: ' .. st.log)
        if #reason > 100 then reason = reason:sub(1, 100) .. '...' end
        show('Download failed: ' .. reason, 5)
        return
    end

    local name = pick_output(st.staging)
    if not name then
        msg.error('download finished but no output file found in ' .. st.staging)
        show('Download failed: no output file', 5)
        return
    end

    local target = unique_target(st.dest, name)
    if not target or not move_file(utils.join_path(st.staging, name), target) then
        msg.error('could not move ' .. name .. ' to ' .. st.dest)
        show('Download failed: cannot move file', 5)
        return
    end

    local final_name = target:match('[^/\\]+$') or target
    msg.info('saved ' .. target)
    show('Saved: ' .. final_name, 5)

    remove_dir_async(st.staging)
    os.remove(st.log)
    os.remove(st.batch)
end

-- ------------------------------------------------------------------ start --
local function start_download()
    if busy then
        -- Keep the progress redraw from wiping this message out after 0.2s.
        if cur then cur.mute_until = mp.get_time() + 2.2 end
        show('Already downloading', 2)
        msg.info('ignored request: a download is already running')
        return
    end

    local url = stream_url()
    if not url then
        show('Not a stream - nothing to download', 3)
        msg.info('not a stream: ' .. tostring(mp.get_property('path')))
        return
    end

    local dest = expand_path(o.download_dir)
    if not ensure_dir(dest) then
        show('Download failed: cannot create download folder', 5)
        msg.error('cannot create download folder: ' .. dest)
        return
    end

    local stamp = os.date('%Y%m%d-%H%M%S')
    local staging = native(utils.join_path(dest, '.mpv-download-' .. stamp))
    if not ensure_dir(staging) then
        show('Download failed: cannot create temp folder', 5)
        msg.error('cannot create staging folder: ' .. staging)
        return
    end

    local fmt = current_format()
    local exe = 'yt-dlp.exe'
    do
        local cands = {}
        local cd = mp.get_property('config-dir', '')
        if cd ~= '' then cands[#cands + 1] = native(utils.join_path(cd, 'yt-dlp.exe')) end
        local ad = os.getenv('APPDATA')
        if ad and ad ~= '' then
            cands[#cands + 1] = native(utils.join_path(utils.join_path(ad, 'mpv'), 'yt-dlp.exe'))
        end
        for _, p in ipairs(cands) do
            if utils.file_info(p) then exe = p; break end
        end
        if exe == 'yt-dlp.exe' then
            msg.error('yt-dlp.exe not found in the mpv config dir; falling back to PATH')
        end
    end

    local log_path = native(utils.join_path(temp_dir(), 'mpv-download-' .. stamp .. '.log'))
    local batch    = native(utils.join_path(temp_dir(), 'mpv-download-' .. stamp .. '.cmd'))

    local args = {
        exe,
        '--no-playlist',
        '--newline',
        '--progress',
        '--progress-template', PROGRESS_TPL,
    }
    local ff = ffmpeg_location()
    if ff then
        args[#args + 1] = '--ffmpeg-location'
        args[#args + 1] = ff
    end
    args[#args + 1] = '-f'
    args[#args + 1] = fmt
    args[#args + 1] = '-o'
    args[#args + 1] = native(utils.join_path(staging, '%(title)s [%(id)s].%(ext)s'))
    for _, a in ipairs(split_args(o.extra_args)) do
        args[#args + 1] = a
    end
    args[#args + 1] = '--'
    args[#args + 1] = url

    if not write_batch(batch, args, log_path) then
        show('Download failed: cannot write helper script', 5)
        msg.error('cannot write ' .. batch)
        remove_dir_async(staging)
        return
    end

    msg.info('starting download: ' .. table.concat(args, ' '))
    msg.info('download folder: ' .. dest)

    busy = true
    cur = {
        url = url, format = fmt, dest = dest, staging = staging,
        log = log_path, batch = batch, pos = 0, pending = '',
        pct = nil, downloaded = nil, speed = nil, last_text = nil,
    }
    cur.last_text = progress_text()
    mp.osd_message(cur.last_text, 1)

    timer = mp.add_periodic_timer(TICK, on_tick)

    local ok, err = pcall(mp.command_native_async, {
        name = 'subprocess',
        args = { 'cmd.exe', '/d', '/c', batch },
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
    }, finish)

    if not ok then
        stop_timer()
        busy = false
        cur = nil
        show('Download failed: could not start yt-dlp', 5)
        msg.error('could not start yt-dlp: ' .. tostring(err))
    end
end

mp.add_key_binding('Ctrl+d', 'download', start_download)

mp.register_event('shutdown', function()
    stop_timer()
end)
