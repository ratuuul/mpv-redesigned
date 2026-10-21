--[[
autosubs.lua - automatic subtitle lookup for LOCAL video files.

On file-loaded, for a local video with no subtitle tracks, wait `delay` seconds
(until playback has actually started) and then:

  auto_load=prompt  open uosc's subtitle downloader, pre-filled with the file
                    name and auto-searched, so results are one click away
  auto_load=single  search the same OpenSubtitles backend uosc uses and load a
                    subtitle silently, but only when exactly one strong match
                    exists
  auto_load=off     never run automatically

Alt+o (script-binding autosubs/fetch) re-runs the lookup on demand, even when
the file already has subtitles.

No new OpenSubtitles client is implemented here: uosc's ziggy binary is used
directly, with uosc's own API key/agent, exactly like uosc's downloader does.
uosc exposes no IPC way to pass a custom query into its picker, so prompt mode
opens that picker (uosc/download-subtitles) which pre-fills the filename.

Never blocks playback, never spams the OSD, never throws on network failure.
--]]

local mp = require('mp')
local utils = require('mp.utils')
local opt = require('mp.options')
local msg = mp.msg

local options = {
	-- off | prompt | single
	auto_load = 'prompt',
	-- seconds to wait after the file starts before looking up subtitles
	delay = 2.5,
	-- semicolon separated list of extensions
	extensions = 'mkv;mp4;avi;mov;m4v;webm;ts',
}
opt.read_options(options, 'autosubs')

local auto_load = tostring(options.auto_load or 'prompt'):lower()
if auto_load ~= 'off' and auto_load ~= 'single' then auto_load = 'prompt' end

local delay = tonumber(options.delay) or 2.5
if delay < 0 then delay = 0 end
if delay > 60 then delay = 60 end

local allowed_ext = {}
for ext in tostring(options.extensions or ''):gmatch('[^;,%s]+') do
	allowed_ext[ext:lower():gsub('^%.', '')] = true
end

-- ---------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------

local function expand(path)
	return mp.command_native({ 'expand-path', path })
end

local function read_file(path)
	local f = io.open(path, 'r')
	if not f then return nil end
	local data = f:read('*a')
	f:close()
	return data
end

local function basename(path)
	return (path:gsub('/', '\\'):match('([^\\]+)$')) or path
end

local function dirname(path)
	local dir = path:gsub('/', '\\'):match('^(.*)\\[^\\]*$')
	return dir or '.'
end

local function is_local_path(path)
	if type(path) ~= 'string' or path == '' then return false end
	if path:match('^file://') then return true end
	return path:match('^%a[%w+.-]*://') == nil
end

local function get_extension(path)
	local ext = basename(path):match('%.([%w]+)$')
	return ext and ext:lower() or nil
end

local function has_subtitle_track()
	local tracks = mp.get_property_native('track-list') or {}
	for _, track in ipairs(tracks) do
		if track.type == 'sub' then return true end
	end
	return false
end

local function has_video()
	local vid = mp.get_property('vid')
	return vid ~= nil and vid ~= 'no' and vid ~= false
end

local function truncate(text, length)
	if type(text) ~= 'string' then return '' end
	if #text <= length then return text end
	return text:sub(1, length - 1) .. '…'
end

-- ---------------------------------------------------------------------------
-- uosc interop: ziggy binary, API key, agent, download directory
-- ---------------------------------------------------------------------------

local uosc_main = expand('~~/scripts/uosc/main.lua')
local uosc_conf = expand('~~/script-opts/uosc.conf')
local uosc = {}

local function uosc_settings()
	if uosc.loaded then return uosc end
	uosc.loaded = true

	local conf = read_file(uosc_conf) or ''
	local src = read_file(uosc_main) or ''

	uosc.api_key = conf:match('open_subtitles_api_key%s*=%s*([^\r\n]+)')
		or src:match("open_subtitles_api_key%s*=%s*'([^']+)'")
		or src:match('open_subtitles_api_key%s*=%s*"([^"]+)"')
	if uosc.api_key then
		uosc.api_key = uosc.api_key:gsub('^%s+', ''):gsub('%s+$', '')
		if #uosc.api_key == 0 then uosc.api_key = nil end
	end

	uosc.agent = conf:match('open_subtitles_agent%s*=%s*([^\r\n]+)')
	if uosc.agent then
		uosc.agent = uosc.agent:gsub('^%s+', ''):gsub('%s+$', '')
		if #uosc.agent == 0 then uosc.agent = nil end
	end
	uosc.agent = uosc.agent or 'autosubs v1.0'

	local dir = conf:match('subtitles_directory%s*=%s*([^\r\n]+)')
	dir = dir and dir:gsub('^%s+', ''):gsub('%s+$', '') or '~~/subtitles'
	if dir:sub(1, 1) == '!' then dir = dir:sub(2) end
	if #dir == 0 then dir = '~~/subtitles' end
	uosc.subtitles_dir = dir

	return uosc
end

local function ziggy_path()
	local env = os.getenv('MPV_UOSC_ZIGGY')
	if env and env ~= '' then return env end
	return expand('~~/scripts/uosc/bin/ziggy-windows.exe')
end

local function preferred_languages()
	local langs = {}
	local seen = {}
	local source = tostring(mp.get_property('slang') or '')
	if source == '' then source = tostring(mp.get_property('alang') or '') end
	for lang in source:gmatch('[^,;%s]+') do
		lang = lang:lower()
		-- OpenSubtitles wants ISO 639-1; keep two letter codes.
		if #lang == 2 and not seen[lang] then
			seen[lang] = true
			langs[#langs + 1] = lang
		end
	end
	if #langs == 0 then langs[1] = 'en' end
	return langs
end

local function open_uosc_picker()
	msg.info('opening uosc subtitle picker')
	mp.commandv('script-binding', 'uosc/download-subtitles')
	return true
end

-- ---------------------------------------------------------------------------
-- filename -> search query
-- ---------------------------------------------------------------------------

-- Release/technical noise that ends the title part of a scene name.
local JUNK = {
	'1080p', '1081p', '720p', '2160p', '480p', '540p', '4k', '8k', 'uhd', 'hd', 'sd',
	'x264', 'x265', 'h264', 'h265', 'hevc', 'avc', 'av1', 'xvid', 'divx', '10bit', '8bit',
	'bluray', 'bdrip', 'brrip', 'bdremux', 'remux', 'web', 'webdl', 'webrip',
	'hdtv', 'dvdrip', 'dvd', 'hddvd', 'dvd5', 'dvd9',
	'hdr', 'hdr10', 'dv', 'dolby', 'vision', 'sdr',
	'ddp5', 'dd5', 'ac3', 'eac3', 'dts', 'dtshd', 'truehd', 'atmos', 'aac', 'flac',
	'proper', 'repack', 'internal', 'extended', 'remastered', 'uncut', 'unrated', 'complete', 'limited',
	'multi', 'multisub', 'subbed', 'dubbed', 'dual', 'audio', 'sub', 'subs',
	'sample', 'trailer',
}
local JUNK_SET = {}
for _, word in ipairs(JUNK) do JUNK_SET[word] = true end

local TECH_RES = { '2160p', '1080p', '720p', '480p', '4k' }
local TECH_SOURCE = { 'bluray', 'remux', 'bdrip', 'brrip', 'webdl', 'webrip', 'hdtv', 'dvdrip' }
local TECH_CODEC = { 'x264', 'x265', 'h264', 'h265', 'hevc', 'av1' }

local function normalize(text)
	return (tostring(text or ''):lower():gsub('[^%w]+', ' '):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function is_junk(word)
	return JUNK_SET[normalize(word)] == true
end

-- `Movie.Name-GROUP` -> `Movie.Name`. Word-internal hyphens (Spider-Man) and
-- hyphenated titles without a scene suffix are left alone.
local function strip_group(text)
	return (text:gsub('%-([%w]+)%s*$', function(group)
		local prefix = text:sub(1, #text - #group - 1)
		if #group >= 2 and (prefix:find(' ') or prefix:find('%d')) then
			return ''
		end
		return '-' .. group
	end))
end

-- Returns { query, title, year, tech, base } or nil when nothing sensible
-- can be searched for.
local function build_query(path)
	local base = basename(path):gsub('%.[^.]+$', '')
	base = base:gsub('[%[%](){}]', ' ')
	base = base:gsub('[._]+', ' ')
	base = strip_group(base)

	local tokens = {}
	for token in base:gmatch('%S+') do
		token = token:gsub('^[%p]+', ''):gsub('[%p]+$', '')
		if #token > 0 then tokens[#tokens + 1] = token end
	end

	-- The last plausible four digit number is the release year. If it is the
	-- very first token, it is the title itself (e.g. "1917").
	local year, year_index
	for i = #tokens, 2, -1 do
		local token = tokens[i]
		if token:match('^%d%d%d%d$') then
			local n = tonumber(token)
			if n and n >= 1900 and n <= 2099 then
				year, year_index = token, i
				break
			end
		end
	end

	local title_tokens = {}
	local cut = false
	for i, token in ipairs(tokens) do
		if not cut then
			-- Split hyphenated tokens so `Movie-x264` and `x264-GROUP` end the
			-- title, while `Spider-Man` survives intact.
			local keep = {}
			for part in (token .. '-'):gmatch('([^%-]*)%-') do
				if #part > 0 then
					if is_junk(part) then
						cut = true
						break
					end
					keep[#keep + 1] = part
				end
			end

			if not cut and #keep > 0 then
				local kept = table.concat(keep, '-')
				-- Drop a trailing ALLCAPS scene group attached by a dash.
				local prefix = kept:match('^(.-)%-[A-Z][A-Z0-9]+$')
				if prefix and #prefix > 0 then kept = prefix end

				if i ~= year_index then
					if kept:match('^%d+$') then
						-- Keep short numbers (1917, 2049); 5+ digit ids are noise.
						if #kept > 4 then
							cut = true
						else
							title_tokens[#title_tokens + 1] = kept
						end
					elseif #kept >= 2 then
						title_tokens[#title_tokens + 1] = kept
					end
				end
			end
		end
	end

	local title = table.concat(title_tokens, ' ')
		:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
	if title == '' then return nil end

	-- Reject names that cannot produce a meaningful search ("lg", "sample").
	-- Numeric-only titles are legitimate when long enough ("1917").
	local compact = title:gsub('%s+', '')
	if #compact < 3 then return nil end
	local letters = 0
	for _ in title:gmatch('[%a]') do letters = letters + 1 end
	if letters == 0 and not compact:match('^%d%d%d%d$') then return nil end

	local query = title
	if year and not title:match('%f[%d]' .. year .. '%f[%D]') then
		query = title .. ' ' .. year
	end

	-- Technical tokens from the original name, used to judge match strength.
	-- Compact form so `WEB-DL` -> `webdl` and `H.264` -> `h264` still match.
	local raw = base:lower():gsub('[^%w]', '')
	local tech = {}
	local function add_tech(list)
		for _, candidate in ipairs(list) do
			if raw:find(candidate, 1, true) then
				tech[#tech + 1] = candidate
				return
			end
		end
	end
	add_tech(TECH_RES)
	add_tech(TECH_SOURCE)
	add_tech(TECH_CODEC)

	return { query = query, title = title, year = year, tech = tech, base = base }
end

-- ---------------------------------------------------------------------------
-- ziggy search / download (the same backend and flags uosc uses)
-- ---------------------------------------------------------------------------

local warned = false

local function run_ziggy(args, callback)
	local ziggy = ziggy_path()
	if not ziggy or ziggy == '' then
		callback('ziggy path unavailable')
		return
	end
	local f = io.open(ziggy, 'rb')
	if not f then
		callback('ziggy binary not found')
		return
	end
	f:close()

	local cfg = uosc_settings()
	if not cfg.api_key then
		callback('OpenSubtitles API key unavailable')
		return
	end

	local argv = { ziggy }
	for _, arg in ipairs(args) do argv[#argv + 1] = arg end
	argv[#argv + 1] = '--api-key'
	argv[#argv + 1] = cfg.api_key
	argv[#argv + 1] = '--agent'
	argv[#argv + 1] = cfg.agent

	mp.command_native_async({
		name = 'subprocess',
		args = argv,
		capture_stdout = true,
		capture_stderr = true,
		playback_only = false,
	}, function(success, result, error)
		if not success or not result or result.status ~= 0 then
			local detail = error or (result and (result.stderr or result.stdout)) or 'ziggy failed'
			callback(truncate(tostring(detail):gsub('%s+', ' '), 200))
			return
		end
		local data = utils.parse_json(result.stdout or '')
		if type(data) ~= 'table' then
			callback('invalid response from ziggy')
			return
		end
		if data.error then
			callback('ziggy: ' .. tostring(data.message or data.error))
			return
		end
		callback(nil, data)
	end)
end

local function release_core(release)
	return normalize(tostring(release or ''):gsub('%-[^%-%s]+_?%w*$', ''))
end

local function candidate_matches(candidate, parsed, langs)
	local attrs = candidate.attributes
	if type(attrs) ~= 'table' then return false end
	if type(attrs.files) ~= 'table' or not attrs.files[1] or not attrs.files[1].file_id then
		return false
	end

	local lang = tostring(attrs.language or ''):lower()
	local lang_ok = false
	for _, wanted in ipairs(langs) do
		if lang == wanted or (wanted == 'en' and lang == 'eng') then
			lang_ok = true
			break
		end
	end
	if not lang_ok then return false end

	local feature = attrs.feature_details or {}
	local feature_title = normalize(feature.title or '')
	if feature_title == '' or feature_title ~= normalize(parsed.title) then return false end
	if parsed.year and feature.year and tonumber(feature.year) ~= tonumber(parsed.year) then
		return false
	end

	-- A hash match is definitive; otherwise require the release name to carry
	-- the file's resolution/source/codec tags.
	if attrs.moviehash_match == true then return true end
	local release_norm = normalize(attrs.release or '')
	for _, tech in ipairs(parsed.tech or {}) do
		if not release_norm:find(tech, 1, true) then return false end
	end
	return true
end

-- Returns candidate, count_of_strong. Only a unique strong match is returned.
local function pick_strong(candidates, parsed, langs)
	local strong = {}
	for _, candidate in ipairs(candidates) do
		if candidate_matches(candidate, parsed, langs) then
			strong[#strong + 1] = candidate
		end
	end
	if #strong == 0 then return nil, 0 end

	-- Prefer non hearing-impaired releases when both exist.
	local plain = {}
	for _, candidate in ipairs(strong) do
		if not candidate.attributes.hearing_impaired then plain[#plain + 1] = candidate end
	end
	if #plain > 0 then strong = plain end

	if #strong == 1 then return strong[1], 1 end

	-- Several release groups can match the same film. If exactly one release
	-- core equals the file's core, that is still a single confident match.
	local wanted = release_core(parsed.base)
	local exact = {}
	for _, candidate in ipairs(strong) do
		if release_core(candidate.attributes.release) == wanted then
			exact[#exact + 1] = candidate
		end
	end
	if #exact == 1 then return exact[1], #strong end
	return nil, #strong
end

local function subtitles_dir()
	local cfg = uosc_settings()
	local dir = expand(cfg.subtitles_dir)
	local probe_path = dir .. '/.autosubs_write_test'
	local probe = io.open(probe_path, 'w')
	if probe then
		probe:close()
		os.remove(probe_path)
		return dir
	end
	-- Fall back to the video's own folder when uosc's dir is not writable.
	return dirname(mp.get_property('path') or '')
end

local function load_subtitle(file, label)
	mp.commandv('sub-add', file, 'select', label)
	mp.osd_message('Subtitle: ' .. truncate(label, 60), 3)
	msg.info('loaded subtitle: ' .. tostring(file))
end

local function report_failure(text, manual)
	if warned then return end
	warned = true
	msg.warn(text)
	if manual or auto_load == 'single' then
		mp.osd_message('Subtitles: lookup failed.', 4)
	end
end

local function download_candidate(candidate, manual)
	local attrs = candidate.attributes
	local file_id = attrs.files[1].file_id
	local label = tostring(attrs.release or attrs.files[1].file_name or 'subtitle')

	run_ziggy({
		'download-subtitles',
		'--file-id', tostring(file_id),
		'--destination', subtitles_dir(),
	}, function(err, data)
		if err or type(data) ~= 'table' or type(data.file) ~= 'string' then
			report_failure('subtitle download failed: ' .. tostring(err or 'invalid response'), manual)
			return
		end
		load_subtitle(data.file, label)
	end)
end

local function search_and_maybe_load(path, parsed, manual)
	if not parsed then
		msg.info('skipping lookup: no usable query for ' .. tostring(path))
		if manual then mp.osd_message('Auto-subs: filename has no usable title.', 3) end
		return
	end

	local langs = preferred_languages()
	msg.info('searching subtitles for "' .. parsed.query .. '"')
	run_ziggy({
		'search-subtitles',
		'--languages', table.concat(langs, ','),
		'--page', '1',
		'--query', parsed.query,
		'--hash', path,
	}, function(err, data)
		if err then
			report_failure('subtitle search failed: ' .. tostring(err), manual)
			return
		end

		local subs = type(data.data) == 'table' and data.data or {}
		local candidate, count = pick_strong(subs, parsed, langs)
		if candidate then
			download_candidate(candidate, manual)
			return
		end

		msg.info(string.format('no confident match for "%s" (%d strong)', parsed.query, count))
		if manual then
			-- The user explicitly asked; always leave a way forward.
			open_uosc_picker()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- auto flow
-- ---------------------------------------------------------------------------

local attempted = {}
local generation = 0
local pending_timer

local function cancel_pending()
	if pending_timer then
		pending_timer:kill()
		pending_timer = nil
	end
end

local function current_path()
	return mp.get_property('path')
end

local function open_picker_for_prompt()
	open_uosc_picker()
end

local function run_lookup(path, manual)
	if not path then return end

	if not manual and auto_load == 'off' then return end

	if not is_local_path(path) then
		if manual then open_uosc_picker() end
		return
	end

	if not manual then
		local ext = get_extension(path)
		if not ext or not allowed_ext[ext] then return end
		if not has_video() then return end
		if has_subtitle_track() then
			msg.info('skipping ' .. tostring(path) .. ': already has subtitles')
			return
		end
		if attempted[path] then return end
		attempted[path] = true
	end

	local parsed = build_query(path)

	if auto_load == 'prompt' then
		if not manual and not parsed then
			msg.info('skipping lookup: no usable query for ' .. tostring(path))
			return
		end
		open_picker_for_prompt()
		return
	end

	search_and_maybe_load(path, parsed, manual)
end

local function wait_then_run(path, gen)
	if gen ~= generation or current_path() ~= path then return end

	local waited = 0
	local function poll()
		if gen ~= generation or current_path() ~= path then return end
		local pos = mp.get_property_number('time-pos')
		if pos and pos > 0 then
			pending_timer = nil
			run_lookup(path, false)
			return
		end
		waited = waited + 0.25
		if waited >= 12 then
			pending_timer = nil
			msg.info('gave up waiting for playback to start: ' .. tostring(path))
			return
		end
		pending_timer = mp.add_timeout(0.25, poll)
	end
	poll()
end

mp.register_event('file-loaded', function()
	generation = generation + 1
	local gen = generation
	cancel_pending()
	warned = false

	local path = current_path()
	msg.info('file-loaded: ' .. tostring(path))

	if auto_load == 'off' then return end
	if not is_local_path(path) then return end
	local ext = get_extension(path)
	if not ext or not allowed_ext[ext] then return end
	if not has_video() then return end
	if has_subtitle_track() then return end

	msg.info('scheduling subtitle lookup in ' .. tostring(delay) .. 's')
	pending_timer = mp.add_timeout(delay, function()
		pending_timer = nil
		wait_then_run(path, gen)
	end)
end)

-- Manual re-fetch: ignores the "already has subtitles" condition.
mp.add_key_binding('Alt+o', 'fetch', function()
	local path = current_path()
	if not path then
		mp.osd_message('Auto-subs: no file loaded.', 2)
		return
	end
	attempted[path] = true
	warned = false
	run_lookup(path, true)
end)

-- Debug helper: `script-message-to autosubs debug-query` prints the parsed query.
mp.register_script_message('debug-query', function()
	local path = current_path()
	local parsed = path and build_query(path)
	if not parsed then
		mp.osd_message('Auto-subs: no usable query for this file.', 4)
		msg.info('autosubs debug: no usable query for ' .. tostring(path))
		return
	end
	local tech = table.concat(parsed.tech or {}, ',')
	mp.osd_message('query: ' .. parsed.query .. '  | year: ' .. tostring(parsed.year)
		.. '  | tech: ' .. tech, 6)
	msg.info('autosubs debug: query="' .. parsed.query .. '" year=' .. tostring(parsed.year)
		.. ' title="' .. parsed.title .. '" tech=' .. tech)
end)
