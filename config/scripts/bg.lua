--[[
bg.lua - idle photo background for mpv / uosc (Liquid Glass)

WHAT IT DOES
  While mpv is idle, shows a full-window photo.  The photo is loaded as the
  current "file" (an image with image-display-duration=inf), which means the
  skin's glass control bar composites over it exactly like it does over video.

  Ctrl+Shift+K  (script-binding bg/next)  downloads the next photo.

  When a real video is loaded the photo is replaced automatically (nothing is
  drawn over it).  When mpv returns to idle the last photo comes back.

PHOTO SOURCES
  Free, no API key.  Tried in the order set by `sources`, and the next source
  is used whenever one fails:
    loremflickr  https://loremflickr.com/<w>/<h>/<keyword>?lock=<seed>
    picsum       https://picsum.photos/<w>/<h>?random=<seed>
    unsplash     https://source.unsplash.com/<w>x<h>/?<keyword>   (best effort)

  Downloads are asynchronous (curl subprocess), so the player never blocks.
  Every download is validated (size > 5 kB + JPEG/PNG/GIF/WebP/BMP magic
  bytes) before it can be shown, so an HTTP error page never ends up on
  screen.  Valid photos are kept in ~~/cache/bg/ and re-used; when the
  network is down an already-cached photo is shown instead.

CONFIG
  ~~/script-opts/bg.conf   (see that file for every option)

  Do not edit: this script only reads uosc's Liquid Glass icon table to draw
  the idle cat.  If that table is missing, the prompt is drawn without the
  cat instead of failing.
]]

local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'
local assdraw = require 'mp.assdraw'
local opts = require 'mp.options'

local o = {
	enabled = true,
	keywords = 'nature,landscape,minimal,city,night',
	sources = 'loremflickr,picsum,unsplash',
	width = 1920,
	height = 1200,
	cache_size = 20,
	initial_delay = 1.5,
	timeout = 20,
	title = 'Background',
	show_prompt = true,
	prompt = "What're ya lookin' at? Drop a file or URL already, will ya?",
	font = 'Geist Medium',
	font_size = 44,
	cat_frac = 0.30,
	cat_max = 340,
	text_gap = 28,
	ink = 'FFFFFF',
}
opts.read_options(o, 'bg')

if not o.enabled then
	msg.verbose('disabled')
	return
end

local UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' ..
	'(KHTML, like Gecko) Chrome/120.0 Safari/537.36'

local CURL = (os.getenv('SystemRoot') or 'C:/Windows'):gsub('\\', '/') ..
	'/System32/curl.exe'

local function fwd(path)
	return path and path:gsub('\\', '/') or path
end

local function expand(path)
	return fwd(mp.command_native({ 'expand-path', path }))
end

local cache_dir = expand('~~/cache/bg')
if cache_dir:sub(-1) ~= '/' then cache_dir = cache_dir .. '/' end

local EXTS = { 'jpg', 'png', 'gif', 'webp', 'bmp' }

local state = {
	busy = false,
	gen = 0,
	bg_path = nil,    -- file currently loaded as the background
	bg_active = false, -- the background *is* the current file
	last_bg = nil,    -- newest good photo on disk (for restores)
	seed = 0,
	counter = 0,
	index = 0,
	prompt_shown = false,
	new_photo = false,
}

-- ============================================================== helpers ==

local made_dir = false
local function ensure_dir()
	if made_dir then return end
	made_dir = true
	-- os.execute() goes through cmd.exe directly, so quoting is reliable here
	-- (mpv's subprocess argument encoder mangles quotes inside a single argv).
	local win = cache_dir:gsub('/', '\\'):gsub('\\$', '')
	os.execute('mkdir "' .. win .. '" >nul 2>nul')
end

-- Returns the detected image type, or false.  Guards against error pages.
local function validate(path)
	local f = io.open(path, 'rb')
	if not f then return false end
	local size = f:seek('end') or 0
	f:seek('set', 0)
	local head = f:read(16) or ''
	f:close()
	if size < 5000 then return false end
	if head:sub(1, 3) == '\255\216\255' then return 'jpg' end
	if head:sub(1, 8) == '\137PNG\r\n\26\n' then return 'png' end
	if head:sub(1, 4) == 'GIF8' then return 'gif' end
	if head:sub(1, 4) == 'RIFF' and head:sub(9, 12) == 'WEBP' then return 'webp' end
	if head:sub(1, 2) == 'BM' then return 'bmp' end
	return false
end

local function same_file(a, b)
	if not a or not b then return false end
	return fwd(a):lower() == fwd(b):lower()
end

local function cache_key(src, seed)
	return string.format('%s_%dx%d_%d', src, o.width, o.height, seed)
end

local function find_cached(key)
	for _, ext in ipairs(EXTS) do
		local path = cache_dir .. 'bg_' .. key .. '.' .. ext
		local f = io.open(path, 'rb')
		if f then
			f:close()
			return path
		end
	end
	return nil
end

-- Newest cached photo (largest seed), used when every source fails.
local function newest_cached()
	local files = utils.readdir(cache_dir, 'files')
	if not files then return nil end
	local best, best_seed = nil, -1
	for _, name in ipairs(files) do
		local seed = name:match('_(%d+)%.[%a]+$')
		if name:match('^bg_') and seed then
			seed = tonumber(seed)
			if seed and seed > best_seed then
				best, best_seed = cache_dir .. name, seed
			end
		end
	end
	return best
end

local function prune_cache()
	local files = utils.readdir(cache_dir, 'files')
	if not files then return end
	local entries = {}
	for _, name in ipairs(files) do
		local seed = name:match('_(%d+)%.[%a]+$')
		if name:match('^bg_') and seed then
			entries[#entries + 1] = { name = name, seed = tonumber(seed) or 0 }
		end
	end
	if #entries <= tonumber(o.cache_size) then return end
	table.sort(entries, function(a, b) return a.seed > b.seed end)
	for i = tonumber(o.cache_size) + 1, #entries do
		os.remove(cache_dir .. entries[i].name)
	end
end

-- ========================================================= idle overlay ==

local overlay
local icons

local function get_icons()
	if icons ~= nil then return icons end
	local path = expand('~~/scripts/uosc/lib/liquid/icons.lua')
	local ok, mod = pcall(dofile, path)
	icons = (ok and type(mod) == 'table') and mod or false
	return icons
end

local function hide_prompt()
	if overlay and state.prompt_shown then
		overlay.hidden = true
		overlay:update()
		state.prompt_shown = false
	end
end

local function draw_prompt()
	if not o.show_prompt then return end
	local dim = mp.get_property_native('osd-dimensions')
	if not dim or not dim.w or not dim.h or dim.w < 2 or dim.h < 2 then return end

	local w, h = dim.w, dim.h
	local cx, cy = w / 2, h / 2
	local cat_size = math.min(h * o.cat_frac, o.cat_max)
	local cat_cy = cy - o.text_gap / 2 - o.font_size / 2
	local text_y = math.floor(cat_cy + cat_size / 2 + o.text_gap + 0.5)

	local ass = assdraw.ass_new()
	local cat = get_icons()
	if cat then
		pcall(cat.draw_at, ass, 'idle_cat', cx, cat_cy, cat_size, o.ink, '&H00&', nil, true)
	else
		text_y = math.floor(cy + 0.5)
	end

	local ink_bgr = o.ink:sub(5, 6) .. o.ink:sub(3, 4) .. o.ink:sub(1, 2)
	ass:new_event()
	ass:append(string.format(
		'{\\an5\\pos(%d,%d)\\fn%s\\fs%d\\bord2\\3c&H000000&\\3a&H20&' ..
		'\\shad2\\4c&H000000&\\4a&H40&\\1c&H%s&}%s',
		math.floor(cx + 0.5), text_y, o.font, o.font_size, ink_bgr, o.prompt
	))

	overlay = overlay or mp.create_osd_overlay('ass-events')
	-- 0 = under uosc's own overlay (z=2000), so the skin keeps drawing on top.
	overlay.z = 0
	overlay.res_x = w
	overlay.res_y = h
	overlay.data = (ass.text:gsub('^[\r\n]+', ''))
	overlay.hidden = false
	overlay:update()
	state.prompt_shown = true
end

-- ============================================================== loading ==

local function load_bg(path, is_new)
	state.new_photo = is_new and true or false
	state.bg_path = path
	if is_new then state.index = state.index + 1 end
	-- force-media-title keeps the filename out of the window title.
	-- save-position-on-quit / autocreate-playlist are disabled per file so
	-- the cache does not leak into watch-later or the playlist.
	mp.commandv('loadfile', path, 'replace', -1,
		'image-display-duration=inf' ..
		',force-media-title=' .. (o.title:gsub(',', ' ')) ..
		',save-position-on-quit=no,autocreate-playlist=no')
end

-- =========================================================== networking ==

local function source_list()
	local list = {}
	for src in tostring(o.sources):gmatch('[^,]+') do
		src = src:match('^%s*(.-)%s*$'):lower()
		if src ~= '' then list[#list + 1] = src end
	end
	if #list == 0 then list = { 'picsum' } end
	return list
end

local function keyword()
	local list = {}
	for kw in tostring(o.keywords):gmatch('[^,]+') do
		kw = kw:match('^%s*(.-)%s*$')
		if kw ~= '' then list[#list + 1] = kw end
	end
	if #list == 0 then return 'nature' end
	return list[math.random(#list)]
end

local function build_url(src, seed)
	local w, h = o.width, o.height
	if src == 'loremflickr' then
		return string.format('https://loremflickr.com/%d/%d/%s?lock=%d', w, h, keyword(), seed)
	elseif src == 'picsum' then
		return string.format('https://picsum.photos/%d/%d?random=%d', w, h, seed)
	elseif src == 'unsplash' then
		return string.format('https://source.unsplash.com/%dx%d/?%s', w, h, keyword())
	end
	return nil
end

local function next_seed()
	state.counter = state.counter + 1
	local seed = os.time() * 1000 + (state.counter % 1000)
	if seed <= state.seed then seed = state.seed + 1 end
	state.seed = seed
	return seed
end

-- ============================================================ fallbacks ==

local function give_up()
	state.busy = false
	local cached = newest_cached()
	if cached then
		msg.info('no download available, using cached ' .. cached)
		state.last_bg = cached
		load_bg(cached, false)
	else
		msg.warn('no photo available (offline and cache is empty)')
		mp.osd_message('Background: no photo available', 3)
	end
end

local function try_source(list, i, seed, gen, quiet)
	if gen ~= state.gen then return end
	local src = list[i]
	if not src then return give_up() end

	local url = build_url(src, seed)
	if not url then return try_source(list, i + 1, seed, gen, quiet) end

	local key = cache_key(src, seed)
	local cached = find_cached(key)
	if cached then
		-- Same seed already on disk: no download.
		state.busy = false
		state.last_bg = cached
		msg.verbose('cache hit ' .. cached)
		load_bg(cached, true)
		return
	end

	ensure_dir()
	local tmp = cache_dir .. 'dl_' .. key .. '.part'
	os.remove(tmp)

	local args = {
		CURL, '-L', '--silent', '--show-error', '--fail',
		'--max-time', tostring(o.timeout), '--connect-timeout', '8',
		'-A', UA, '-o', tmp, url,
	}

	mp.command_native_async({
		name = 'subprocess',
		args = args,
		playback_only = false,
		capture_stdout = false,
		capture_stderr = true,
	}, function(success, res)
		if gen ~= state.gen then return end
		local status = res and res.status or -1
		local ext = success and status == 0 and validate(tmp)
		if ext then
			local final = cache_dir .. 'bg_' .. key .. '.' .. ext
			os.remove(final)
			if not os.rename(tmp, final) then final = tmp end
			state.busy = false
			state.last_bg = final
			prune_cache()
			msg.info(('downloaded %s (%s)'):format(src, ext))
			load_bg(final, true)
		else
			os.remove(tmp)
			msg.verbose(('source %s failed (curl status %s)'):format(src, tostring(status)))
			try_source(list, i + 1, seed, gen, quiet)
		end
	end)
end

local function fetch(quiet)
	if state.busy then return end
	local idle = mp.get_property_bool('idle-active')
	if not idle and not state.bg_active then
		-- A real video is playing.  Never steal the file from it.
		if not quiet then mp.osd_message('Background: idle only', 2) end
		return
	end

	state.busy = true
	state.gen = state.gen + 1
	local gen = state.gen
	math.randomseed(os.time() + state.counter)
	try_source(source_list(), 1, next_seed(), gen, quiet)
end

-- ============================================================== events ==

mp.register_event('file-loaded', function()
	local path = mp.get_property('path')
	if state.bg_path and same_file(path, state.bg_path) then
		state.bg_active = true
		state.last_bg = state.bg_path
		if state.new_photo then
			mp.osd_message('Background ' .. state.index, 1.5)
			state.new_photo = false
		end
		draw_prompt()
	else
		state.bg_active = false
		hide_prompt()
	end
end)

-- Real playback finished / stopped -> bring the photo back.
mp.observe_property('idle-active', 'bool', function(_, idle)
	if idle and o.enabled and state.last_bg and not state.busy then
		mp.add_timeout(0.2, function()
			if mp.get_property_bool('idle-active') and not state.bg_active then
				load_bg(state.last_bg, false)
			end
		end)
	end
end)

-- Re-fit the prompt after a window resize (the photo itself scales by itself).
local resize_timer
mp.observe_property('osd-dimensions', 'native', function()
	if not state.bg_active then return end
	if resize_timer then resize_timer:kill() end
	resize_timer = mp.add_timeout(0.15, function()
		resize_timer = nil
		if state.bg_active and state.prompt_shown then draw_prompt() end
	end)
end)

mp.add_key_binding(nil, 'next', function()
	fetch(false)
end)

-- Startup: only take over if mpv is genuinely idle (no file was passed).
mp.add_timeout(tonumber(o.initial_delay) or 1.5, function()
	if mp.get_property_bool('idle-active') then fetch(true) end
end)

msg.verbose('loaded')
