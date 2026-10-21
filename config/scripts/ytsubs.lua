-- =============================================================================
--  ytsubs - pick and load YouTube subtitles inside mpv
--
--  Lets you choose any subtitle track of a YouTube video: the manual ones
--  uploaded by the creator, plus the auto-generated captions, in every
--  language YouTube offers.
--
--  Where the list comes from:
--    mpv's bundled ytdl_hook already runs yt-dlp for every YouTube URL and
--    caches the full info dict in
--        user-data/mpv/ytdl/json-subprocess-result
--    That dict contains `subtitles` (manual) and `automatic_captions` (ASR),
--    so building the list costs no extra network traffic.
--
--  The chosen track is downloaded once into ~~/cache/ytsubs and then handed
--  to mpv with `sub-add`, which puts it into the normal track list. After
--  that it shows up in `v`, in uosc's Subtitles menu and in mpv's own
--  `script-binding select/select-sid`.
--
--  Menus: the uosc (Liquid Glass) menu is used when that skin is active,
--  otherwise mpv's native input.select list is used.
-- =============================================================================

local utils   = require 'mp.utils'
local msg     = require 'mp.msg'
local options = require 'mp.options'
local input   = require 'mp.input'

local o = {
    cache_dir     = '~~/cache/ytsubs',
    sub_format    = 'srt',     -- 'srt' or 'vtt' - YouTube serves both natively
    offer_manual  = true,
    offer_auto    = true,
    auto_select   = false,    -- automatically load a subtitle when a video loads
    auto_langs    = 'en,ja',  -- tried in order when auto_select is on
    max_auto      = 60,       -- cap the number of auto-caption entries listed
    timeout       = 20,
}
options.read_options(o, 'ytsubs')

local SCRIPT = mp.get_script_name()
local MENU_TYPE = 'ytsubs'

-- Remember the original YouTube URL: after ytdl_hook runs, mpv's `path`
-- points at the resolved googlevideo stream, not at the watch page.
local original_url = nil

local function is_youtube(url)
    return url and (url:find('youtube%.com') or url:find('youtu%.be')) ~= nil
end

mp.observe_property('path', 'native', function(_, p)
    if is_youtube(p) then
        original_url = p
        -- Tell the skin that a YouTube subtitle picker is available, so it
        -- can offer the entry in its menu.
        mp.set_property_native('user-data/ytsubs/available', true)
    end
end)

local function osd(t) mp.osd_message('ytsubs: ' .. t, 3) end

-- =============================================================================
--  Getting the info dict
-- =============================================================================

local info_cache = nil
local info_url = nil

local function parse_info(raw)
    if type(raw) ~= 'string' or raw == '' then return nil end
    local ok, j = pcall(utils.parse_json, raw)
    if ok and type(j) == 'table' then return j end
    return nil
end

local function info_from_hook()
    local res = mp.get_property_native('user-data/mpv/ytdl/json-subprocess-result')
    if not res then return nil end
    local j = parse_info(res.stdout)
    if j and (j.subtitles or j.automatic_captions) then return j end
    return nil
end

local function info_from_ytdlp(url)
    local exe = mp.get_property_native('user-data/mpv/ytdl/path')
    if not exe or exe == '' then
        exe = utils.join_path(mp.get_property('config-dir') or '', 'yt-dlp.exe')
    end
    if not utils.file_info(exe) then return nil end
    local r = mp.command_native({
        name = 'subprocess',
        args = { exe, '--no-warnings', '-J', '--no-playlist', '--', url },
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
    })
    if r.status ~= 0 or not r.stdout then return nil end
    return parse_info(r.stdout)
end

-- Returns the info dict plus the page URL to download subtitles from.
local function get_info()
    if info_cache and info_url == original_url then
        return info_cache, info_url
    end

    local j = info_from_hook()
    if not j and original_url then
        j = info_from_ytdlp(original_url)
    end

    if not j then return nil, nil end

    -- webpage_url is the canonical watch page; fall back to what we saw.
    local url = j.webpage_url or original_url
    info_cache = j
    info_url = url
    return j, url
end

-- =============================================================================
--  Building the list
-- =============================================================================

local function pick_format(formats)
    local best
    for _, f in ipairs(formats or {}) do
        -- Written without `goto continue` so the file parses under Lua 5.1 as
        -- well as LuaJIT / 5.2+, which is what CI checks.
        if f.url then
            if f.ext == o.sub_format then
                best = f
                break
            end
            if not best and (f.ext == 'srt' or f.ext == 'vtt' or f.ext == 'ass') then
                best = f
            end
            if not best then best = f end
        end
    end
    return best
end

-- Prefer plain language codes (en) over regional ones (en-US) and put
-- "-orig" right after the plain code.
local function lang_rank(lang)
    if lang == 'en-orig' then return 1 end
    if not lang:find('-') then return 0 end
    return 2
end

local function collect(info)
    local out = {}
    local seen = {}
    local manual_langs = {}

    local function add(dict, is_auto)
        if not dict then return end
        local langs = {}
        for lang in pairs(dict) do langs[#langs + 1] = lang end
        table.sort(langs, function(a, b)
            local ra, rb = lang_rank(a), lang_rank(b)
            if ra ~= rb then return ra < rb end
            return a < b
        end)

        for _, lang in ipairs(langs) do
            -- YouTube lists the original captions in BOTH dictionaries; the
            -- manually uploaded ones are always better, so skip the dupe.
            -- (No `goto continue`: this file has to parse under Lua 5.1 too.)
            local f = pick_format(dict[lang])
            if is_auto and manual_langs[lang] then f = nil end
            if f and f.url then
                -- Auto captions come in many regional variants that all share
                -- one display name; collapse them so the menu stays readable.
                local key = (is_auto and 'auto|' or 'manual|') .. (f.name or lang)
                if not seen[key] then
                    seen[key] = true
                    out[#out + 1] = {
                        lang = lang,
                        name = f.name or lang,
                        auto = is_auto,
                        url = f.url,
                        ext = f.ext or o.sub_format,
                        -- A "tlang" parameter means YouTube is translating
                        -- the captions on the fly. Those live behind a much
                        -- stricter rate limit than the original track.
                        translated = f.url:find('tlang=') ~= nil,
                    }
                end
            end
        end
    end

    -- Manual subtitles first; remember their languages so the auto-caption
    -- list does not repeat them.
    if o.offer_manual then
        for lang in pairs(info.subtitles or {}) do manual_langs[lang] = true end
        add(info.subtitles, false)
    end

    if o.offer_auto then
        local before = #out
        add(info.automatic_captions, true)
        if #out - before > o.max_auto then
            -- keep the manual ones plus the first N auto ones
            local trimmed = {}
            for i = 1, math.min(#out, before + o.max_auto) do
                trimmed[i] = out[i]
            end
            out = trimmed
        end
    end

    return out
end

-- ---------------------------------------------------------------------------
--  Downloading
-- ---------------------------------------------------------------------------

local function cache_dir()
    local dir = mp.command_native({ 'expand-path', o.cache_dir })
    if not dir or dir == '' then
        dir = utils.join_path(mp.get_property('config-dir') or '', 'cache', 'ytsubs')
    end
    if not utils.file_info(dir) then
        pcall(os.execute, 'mkdir "' .. dir:gsub('/', '\\') .. '" 2>nul')
    end
    return dir
end

-- YouTube answers a throttled request with an HTML "Sorry..." page instead
-- of the subtitle, so a downloaded file has to be sanity checked.
local function valid_sub_file(path)
    local f = io.open(path, 'rb')
    if not f then return false end
    local head = f:read(200) or ''
    f:close()
    local st = utils.file_info(path)
    if not st or not st.size or st.size < 32 then return false end
    if head:find('<!DOCTYPE', 1, true) or head:find('<html', 1, true) then
        return false
    end
    return true
end

local function video_id(info)
    local vid = (info and info.id) or 'video'
    return vid:gsub('[^%w%-_]', '')
end

-- Preferred path: let yt-dlp fetch the subtitle.
--
-- Going straight to the timedtext URL with curl works, but YouTube
-- rate-limits that endpoint hard - a burst of requests returns an HTML
-- "Sorry, automated queries" page instead of the subtitle. yt-dlp fetches
-- fresh signed URLs and retries, so it is far more reliable.
local function download_via_ytdlp(info, entry, url)
    local exe = mp.get_property_native('user-data/mpv/ytdl/path')
    if not exe or exe == '' then
        exe = utils.join_path(mp.get_property('config-dir') or '', 'yt-dlp.exe')
    end
    if not utils.file_info(exe) then return nil end

    local dir = cache_dir()
    local vid = video_id(info)
    local outtmpl = utils.join_path(dir, vid)

    mp.command_native({
        name = 'subprocess',
        args = {
            exe, '--no-warnings', '--skip-download',
            '--write-subs', '--write-auto-subs',
            '--sub-langs', entry.lang,
            '--sub-format', o.sub_format,
            '-o', outtmpl, '--', url,
        },
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
    })

    -- yt-dlp names it <id>.<lang>.<ext>
    local prefix = vid .. '.' .. entry.lang:gsub('[^%w%-_]', '')
    local files = utils.readdir(dir) or {}
    for _, name in ipairs(files) do
        if name:sub(1, #prefix) == prefix and name:find('%.(srt|vtt|ass)$') then
            local p = utils.join_path(dir, name)
            local st = utils.file_info(p)
            if st and st.is_file and valid_sub_file(p) then return p end
        end
    end
    return nil
end

-- Fallback: fetch the signed URL straight from the yt-dlp metadata.
local function download_via_curl(info, entry)
    local dir = cache_dir()
    local dest = utils.join_path(dir, string.format('%s-%s.%s',
        video_id(info), entry.lang:gsub('[^%w%-_]', ''), entry.ext))

    local st = utils.file_info(dest)
    if st and st.size and st.size > 0 and valid_sub_file(dest) then return dest end

    local curl = 'C:/Windows/System32/curl.exe'
    if not utils.file_info(curl) then curl = 'curl.exe' end

    local ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' ..
        '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'

    mp.command_native({
        name = 'subprocess',
        args = { curl, '-sL', '--max-time', tostring(o.timeout),
                 '-A', ua, '-o', dest, entry.url },
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
    })

    if valid_sub_file(dest) then return dest end
    return nil
end

-- =============================================================================
--  Adding the track
-- =============================================================================

local pending_add = nil

local function do_add_track(source, entry, secondary)
    local title = entry.name .. (entry.auto and ' (auto)' or '')

    if secondary then
        mp.commandv('sub-add', source, 'auto', title, entry.lang)
        -- pick the track we just added as the secondary (top of screen) one
        local list = mp.get_property_native('track-list') or {}
        for i = #list, 1, -1 do
            if list[i].type == 'sub' then
                mp.set_property('secondary-sid', list[i].id)
                mp.set_property('secondary-sub-visibility', 'yes')
                break
            end
        end
        osd('secondary: ' .. title)
    else
        mp.commandv('sub-add', source, 'select', title, entry.lang)
        -- a fresh primary track must not stay in the secondary slot
        pcall(mp.set_property, 'secondary-sid', 'no')
        osd('loaded: ' .. title)
    end
end

local function add_track(source, entry, secondary)
    -- If nothing is loaded yet, mpv drops the track when the file arrives.
    -- Remember it and apply it once the video is up.
    if mp.get_property_native('idle-active') then
        pending_add = { source = source, entry = entry, secondary = secondary }
        msg.info('ytsubs: no file loaded, deferring sub-add')
        return
    end
    do_add_track(source, entry, secondary)
end

-- Note: YouTube rate-limits the timedtext endpoint hard (HTTP 429) for
-- AUTO-TRANSLATED captions, so a translated track can fail even though the
-- creator-uploaded ones work. We retry a couple of times, then report it
-- instead of failing silently.
--
-- Everything here is non-blocking: the retries use mp.add_timeout so the
-- player keeps running.
local function load_attempt(info, entry, url, secondary, attempt)
    local file = download_via_ytdlp(info, entry, url)
        or download_via_curl(info, entry)

    if file then
        add_track(file, entry, secondary)
        return
    end

    if attempt < 2 then
        msg.warn(string.format('ytsubs: download attempt %d failed, retrying',
            attempt))
        mp.add_timeout(2, function()
            load_attempt(info, entry, url, secondary, attempt + 1)
        end)
        return
    end

    msg.error('ytsubs: YouTube refused the subtitle request (HTTP 429)')
    osd('YouTube refused the request (429) - try again in a moment')
    -- last resort: let mpv fetch the subtitle URL itself
    add_track(entry.url, entry, secondary)
end

local function load(lang, kind, secondary)
    local info, url = get_info()
    if not info then
        osd('no YouTube metadata for this file')
        return
    end

    local entries = collect(info)
    local entry
    for _, e in ipairs(entries) do
        if e.lang == lang and ((kind == 'auto') == e.auto) then
            entry = e
            break
        end
    end
    if not entry then
        osd('subtitle not found')
        return
    end

    load_attempt(info, entry, entry.url, secondary, 1)
end

-- =============================================================================
--  Menus
-- =============================================================================

local function uosc_present()
    return mp.get_property_native('user-data/skin/liquidglass') == true
end

local function open_uosc(entries)
    local manual, auto = {}, {}

    for _, e in ipairs(entries) do
        local item = {
            title = e.name,
            hint = e.translated and (e.lang .. ' - translated') or e.lang,
            value = { 'script-message-to', SCRIPT, 'load', e.lang,
                      e.auto and 'auto' or 'manual' },
        }
        if e.auto then auto[#auto + 1] = item else manual[#manual + 1] = item end
    end

    local items = {}
    if #manual > 0 then
        items[#items + 1] = { title = 'Uploaded subtitles', separator = true }
        for _, it in ipairs(manual) do items[#items + 1] = it end
    end
    if #auto > 0 then
        items[#items + 1] = { title = 'Auto-generated captions', separator = true }
        for _, it in ipairs(auto) do items[#items + 1] = it end
    end

    mp.commandv('script-message-to', 'uosc', 'open-menu', utils.format_json({
        type = MENU_TYPE,
        title = 'YouTube subtitles',
        items = items,
        search_style = 'on_demand',
    }))
end

local function open_native(entries)
    local labels = {}
    for i, e in ipairs(entries) do
        labels[i] = string.format('%-28s [%s]%s', e.name, e.lang, e.auto and '  (auto)' or '')
    end
    input.select({
        prompt = 'YouTube subtitles:',
        items = labels,
        submit = function(idx) load(entries[idx].lang, entries[idx].auto and 'auto' or 'manual', false) end,
    })
end

local function open_menu(secondary)
    local info = get_info()
    if not info then
        osd('not a YouTube video')
        return
    end

    local entries = collect(info)
    if #entries == 0 then
        osd('this video has no subtitles')
        return
    end

    if uosc_present() then
        open_uosc(entries)
    else
        open_native(entries)
    end
end

-- =============================================================================
--  Bindings and messages
-- =============================================================================

mp.add_key_binding('alt+s', 'menu', function() open_menu(false) end)
mp.add_key_binding('alt+shift+s', 'menu-secondary', function() open_menu(true) end)

mp.register_script_message('load', function(lang, kind)
    load(lang, kind, false)
end)

mp.register_script_message('load-secondary', function(lang, kind)
    load(lang, kind, true)
end)

-- Automatically grab a subtitle for freshly loaded YouTube videos.
mp.register_event('file-loaded', function()
    info_cache = nil
    info_url = nil
    if not is_youtube(original_url or '') then
        mp.set_property_native('user-data/ytsubs/available', false)
    end

    -- Apply a subtitle that was picked while the video was still loading.
    if pending_add then
        local p = pending_add
        pending_add = nil
        do_add_track(p.source, p.entry, p.secondary)
    end

    if not o.auto_select then return end

    mp.add_timeout(1.5, function()
        local info = get_info()
        if not info then return end
        local entries = collect(info)

        local wanted
        for _, want in ipairs(o.auto_langs:split(',')) do
            want = want:match('^%s*(.-)%s*$')
            if want ~= '' then
                for _, e in ipairs(entries) do
                    if e.lang == want or e.lang:sub(1, #want) == want then
                        wanted = e
                        break
                    end
                end
            end
            if wanted then break end
        end

        if wanted then
            load(wanted.lang, wanted.auto and 'auto' or 'manual', false)
        end
    end)
end)

msg.info('ytsubs loaded')
