--[[
autosubs.lua - automatic subtitle lookup for LOCAL video files.

Pipeline
  Layer 0  OpenSubtitles moviehash first (via uosc's ziggy binary, --hash only)
  Layer 1  structured filename parser -> {title, year, season, episode, group}
  Layer 2  query ladder (up to query_ladder rungs, stop at the first that hits)
  Layer 3  candidate scoring (title Jaccard, year, season, episode, hash)
  Layer 4  uosc results menu, its search palette is the editable query box
  Layer 5  learned corrections in ~~/cache/autosubs/learned.json

Scoring rule (Layer 3)
  A candidate survives only if its release name OR the feature it is filed
  under shares a significant token with the title. Zero overlap on both is
  an outright reject, so a nonsense filename can never attract a
  confidently-wrong subtitle.

auto_load policy
  off     never run automatically
  prompt  show the scored result menu (default)
  single  silently load only when exactly one candidate passes min_score

Alt+o (script-binding autosubs/fetch) always re-runs the lookup, even when the
file already has subtitles. Nothing here blocks playback or throws on network
failure; the OpenSubtitles backend is uosc's ziggy binary, not a new client.
--]]

local mp = require('mp')
local utils = require('mp.utils')
local opt = require('mp.options')
local msg = mp.msg

local options = {
	-- off | prompt | single
	auto_load = 'prompt',
	-- seconds to wait after playback starts before looking up subtitles
	delay = 2.5,
	-- semicolon separated list of video extensions
	extensions = 'mkv;mp4;avi;mov;m4v;webm;ts',
	-- how many query variants to try before giving up (1-8)
	query_ladder = 5,
	-- minimum candidate similarity 0.0-1.0
	min_score = 0.45,
	-- try an exact file-hash match before any text search
	hash_first = true,
}
opt.read_options(options, 'autosubs')

local auto_load = tostring(options.auto_load or 'prompt'):lower()
if auto_load ~= 'off' and auto_load ~= 'single' then auto_load = 'prompt' end

local delay = tonumber(options.delay) or 2.5
if delay < 0 then delay = 0 end
if delay > 60 then delay = 60 end

local query_ladder_max = math.floor(tonumber(options.query_ladder) or 5)
if query_ladder_max < 1 then query_ladder_max = 1 end
if query_ladder_max > 8 then query_ladder_max = 8 end

local min_score = tonumber(options.min_score) or 0.45
if min_score < 0 then min_score = 0 end
if min_score > 1 then min_score = 1 end

local hash_first = options.hash_first
if hash_first == nil then hash_first = true end

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

local function trim(text)
	return (tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function clamp01(n)
	if n < 0 then return 0 end
	if n > 1 then return 1 end
	return n
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
		uosc.api_key = trim(uosc.api_key)
		if #uosc.api_key == 0 then uosc.api_key = nil end
	end

	uosc.agent = conf:match('open_subtitles_agent%s*=%s*([^\r\n]+)')
	if uosc.agent then
		uosc.agent = trim(uosc.agent)
		if #uosc.agent == 0 then uosc.agent = nil end
	end
	uosc.agent = uosc.agent or 'autosubs v1.0'

	local dir = conf:match('subtitles_directory%s*=%s*([^\r\n]+)')
	dir = dir and trim(dir) or '~~/subtitles'
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
	local langs, seen = {}, {}
	local source = tostring(mp.get_property('slang') or '')
	if source == '' then source = tostring(mp.get_property('alang') or '') end
	for lang in source:gmatch('[^,;%s]+') do
		lang = lang:lower()
		if #lang == 2 and not seen[lang] then
			seen[lang] = true
			langs[#langs + 1] = lang
		end
	end
	if #langs == 0 then langs[1] = 'en' end
	return langs
end

local function open_uosc_picker()
	msg.info('opening uosc downloader (fallback)')
	mp.commandv('script-binding', 'uosc/download-subtitles')
end

-- ---------------------------------------------------------------------------
-- Layer 1: filename parser
-- ---------------------------------------------------------------------------

local CURRENT_YEAR = tonumber(os.date('%Y')) or 2026

local META_WORDS = [[
2160p 1080p 1081p 720p 480p 540p 4k 8k uhd hd sd
bluray blu-ray brrip bdrip webrip web-dl webdl web hdtv dvdrip dvd hddvd bdremux remux
x264 x265 h264 h265 hevc avc av1 xvid divx 10bit 8bit
hdr hdr10 sdr dv dolby vision atmos truehd dts dtshd ac3 eac3 aac dd5 ddp5 dd flac opus
5.1 7.1 2.0 60fps hfr
proper repack extended unrated imax remastered directors cut
multi dual audio subs sub dubbed
]]
local META = {}
for word in META_WORDS:gmatch('%S+') do META[word] = true end

-- Ambiguous language codes only: full words such as "English" can be part of
-- a real title (The English Patient), so they are not treated as boundaries.
for _, word in ipairs({ 'eng', 'hin', 'urd', 'jpn', 'kor', 'spa', 'fre', 'ger', 'ara', 'rus', 'por', 'ita', 'chi', 'zho', 'sdh' }) do
	META[word] = true
end

local MONTHS = {}
for _, word in ipairs({
	'january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december',
	'jan', 'feb', 'mar', 'apr', 'jun', 'jul', 'aug', 'sep', 'sept', 'oct', 'nov', 'dec',
}) do
	MONTHS[word] = true
end

local TLDs = { 'com', 'net', 'org', 'info', 'mx', 'gg', 'bz', 'li', 'to', 'cc', 'tv', 'me', 'io', 'in', 'co' }

local GENERIC_DIRS = {
	downloads = true, download = true, videos = true, video = true, movies = true, movie = true,
	tv = true, tvshows = true, series = true, desktop = true, documents = true, temp = true, tmp = true,
}

local function is_meta_token(token)
	local lower = token:lower()
	if META[lower] then return true end
	-- `x264-GROUP`, `Blu-Ray`, `Atmos-TRiToN`: the leading segment carries the tag.
	local first = lower:match('^([^-]+)%-')
	if first and META[first] then return true end
	-- explicit language tags such as `eng-en`, `hi-in`
	if lower:match('^%a%a%a?%-%a%a%a?$') then return true end
	return false
end

local function is_year_token(token)
	if not token:match('^%d%d%d%d$') then return false end
	local n = tonumber(token)
	return n ~= nil and n >= 1900 and n <= CURRENT_YEAR + 2
end

local function clean_token(token)
	return (token:gsub('^[%p]+', ''):gsub('[%p]+$', ''))
end

-- Parses a filename stem (no extension). Returns a record or nil.
local function parse_stem(stem)
	local record = {
		raw = stem,
		title = '',
		confidence = 0,
	}

	local leading = stem:match('^%s*%[([^%]]*)%]')
	if leading then record.leading_group = trim(leading) end

	-- Parenthesised/bracketed years are the most reliable signal.
	local paren_year
	for y in stem:gmatch('[%(%[]%s*(%d%d%d%d)%s*[%)%]]') do
		if is_year_token(y) then
			paren_year = y
			break
		end
	end

	local source = stem
	-- URLs / site names (www.TamilBlasters.com, YTS.MX, ...)
	source = source:gsub('%f[%w]www%.[%w%-%.]+', ' ')
	for _, tld in ipairs(TLDs) do
		source = source:gsub('%f[%w][%w%-]+%.' .. tld .. '%f[%W]', ' ')
	end
	-- Bracketed and parenthesised metadata chunks (keeps balanced nesting).
	source = source:gsub('%b[]', ' ')
	source = source:gsub('%b()', ' ')
	-- Separators become spaces; hyphens inside titles are preserved.
	source = source:gsub('[._]+', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')

	local tokens = {}
	for raw in source:gmatch('%S+') do
		tokens[#tokens + 1] = { raw = raw, clean = clean_token(raw) }
	end

	local title_parts = {}
	local year = paren_year
	local season, episode
	local boundary = nil

	local i = 1
	while i <= #tokens do
		local token = tokens[i]
		local clean = token.clean
		local lower = clean:lower()

		-- A bare dash separator introduces the episode number:
		-- `Show Name - 05`, `Show Name - 5`, `Show Name - Episode 5`.
		-- This must be checked before the `clean == ''` skip below, because
		-- cleaning a lone dash strips it to an empty string.
		if token.raw == '-' or token.raw == '\226\128\147' or token.raw == '\226\128\148' then
			local next_token = tokens[i + 1]
			if next_token and next_token.clean:match('^%d%d?$') then
				episode = tonumber(next_token.clean)
				boundary = i
				break
			end
			i = i + 1
		elseif clean == '' then
			i = i + 1
		else
			-- S01E06 / S1E6
			local s, e = clean:upper():match('^S(%d%d?)E(%d%d?)$')
			if s then
				season, episode = tonumber(s), tonumber(e)
				boundary = i
				break
			end

			-- Split form: `S01.E02`, `S01 E02`
			local split_s = clean:upper():match('^S(%d%d?)$')
			if split_s then
				local next_token = tokens[i + 1]
				local split_e = next_token and next_token.clean:upper():match('^E(%d%d?)$')
				if split_e then
					season, episode = tonumber(split_s), tonumber(split_e)
					boundary = i + 1
					break
				end
			end

			-- 1x06
			local xs, xe = clean:lower():match('^(%d%d?)x(%d%d?)$')
			if xs then
				season, episode = tonumber(xs), tonumber(xe)
				boundary = i
				break
			end

			-- E05
			local only_ep = clean:upper():match('^E(%d%d?)$')
			if only_ep then
				episode = tonumber(only_ep)
				boundary = i
				break
			end

			-- Episode 21 / EP 1
			if lower == 'episode' or lower == 'ep' or lower == 'ep.' then
				local next_token = tokens[i + 1]
				if next_token and next_token.clean:match('^%d%d?$') then
					episode = tonumber(next_token.clean)
					boundary = i
					break
				end
			end

			-- 10 October 2026 / 1 AUG 2026 (air date)
			if clean:match('^%d%d?$') then
				local next_token = tokens[i + 1]
				if next_token and MONTHS[next_token.clean:lower()] then
					boundary = i
					break
				end
			end

			if is_meta_token(clean) then
				boundary = i
				break
			end

			if is_year_token(clean) and i > 1 then
				if not year then year = clean end
				boundary = i
				break
			end

			title_parts[#title_parts + 1] = clean
			i = i + 1
		end
	end

	-- A numeric title such as `1917` must survive; a leading year token is
	-- only accepted when a real title follows it.
	local title = table.concat(title_parts, ' ')
		:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')

	if title == '' then return nil end

	record.title = title
	record.year = year
	record.season = season
	record.episode = episode
	record.is_series = (season ~= nil or episode ~= nil)

	-- Release group: the scene tag is the final token (`...-TRiToN`,
	-- `...x264-CtrlHD`). Only look at the last token so cast names such as
	-- `Dur-e-Fishan` are not mistaken for groups.
	if boundary then
		local last = tokens[#tokens]
		if last then
			local suffix = last.clean:match('^.+%-([%w]+)$')
			if suffix and #suffix >= 2 and not is_meta_token(suffix) and suffix:match('^[%u]') then
				record.release_group = suffix
			end
		end
	end
	if not record.release_group and record.leading_group then
		local lg = record.leading_group:lower()
		if not lg:find('english') and not lg:find('hindi') and not lg:find('united')
			and not lg:find('auto%-generated') and not lg:match('^%d+$') then
			record.release_group = record.leading_group
		end
	end

	-- Technical tags of the file itself, used only to rank candidates.
	local compact = stem:lower():gsub('[^%w]', '')
	record.tech = {}
	local function add_tech(list)
		for _, tag in ipairs(list) do
			if compact:find(tag, 1, true) then
				record.tech[#record.tech + 1] = tag
				return
			end
		end
	end
	add_tech({ '2160p', '1080p', '720p', '480p', '4k' })
	add_tech({ 'bluray', 'remux', 'bdremux', 'bdrip', 'brrip', 'webdl', 'webrip', 'hdtv', 'dvdrip' })
	add_tech({ 'x264', 'x265', 'h264', 'h265', 'hevc', 'av1' })

	-- Confidence: title only is usable, every extra anchor helps.
	local confidence = 0.5
	if record.year then confidence = confidence + 0.2 end
	if record.season then confidence = confidence + 0.1 end
	if record.episode then confidence = confidence + 0.2 end
	if #title_parts >= 2 then confidence = confidence + 0.05 end
	record.confidence = clamp01(confidence)

	return record
end

local function parse_name(name)
	local stem = tostring(name or ''):gsub('%.[%w]+$', '')
	return parse_stem(stem)
end

local function parse_media(path, metadata_title)
	local record = parse_name(basename(path))

	-- Fallback to the parent folder when the filename gives nothing usable.
	if not record or #record.title < 3 then
		local folder = basename(dirname(path))
		if folder and folder ~= '' and not GENERIC_DIRS[folder:lower()] then
			local folder_record = parse_stem(folder:gsub('%.[%w]+$', ''))
			if folder_record and #folder_record.title >= 3 then
				if not record or #folder_record.title > #record.title then
					record = folder_record
					record.from_folder = true
				end
			end
		end
	end

	-- An embedded Title tag is often cleaner than a scene filename.
	if metadata_title and type(metadata_title) == 'string' and #metadata_title > 0 then
		local meta = parse_stem(metadata_title)
		if meta and record and #meta.title > #record.title + 2 then
			meta.year = meta.year or record.year
			meta.season = meta.season or record.season
			meta.episode = meta.episode or record.episode
			meta.is_series = (meta.season ~= nil or meta.episode ~= nil)
			meta.from_metadata = true
			record = meta
		elseif meta and not record then
			record = meta
			record.from_metadata = true
		end
	end

	if not record or #record.title < 2 then return nil end
	return record
end

-- Builds a scoring record from a free-form query typed by the user.
-- The query must be scored against itself, not against the title that was
-- derived from the filename - otherwise retyping a correct title could
-- never produce a match.
local function record_for_query(query)
	local record = parse_name(query)
	if record and #record.title >= 2 then return record end
	return {
		title = trim(query),
		year = nil, season = nil, episode = nil,
		is_series = false,
		tech = {},
		confidence = 0.5,
	}
end

-- ---------------------------------------------------------------------------
-- Layer 2: query ladder
-- ---------------------------------------------------------------------------

local STOPWORDS = {
	['the'] = true, ['a'] = true, ['an'] = true, ['of'] = true,
	-- 'and' and 'or' are Lua keywords and must be bracketed as table keys.
	['and'] = true, ['or'] = true, ['to'] = true,
	['in'] = true, ['on'] = true, ['for'] = true, ['with'] = true, ['part'] = true,
}

local function build_ladder(record, learned_query)
	local ladder, seen = {}, {}
	local function add(query, rec)
		query = query and trim(query:gsub('%s+', ' '))
		if query and #query > 0 and not seen[query:lower()] then
			seen[query:lower()] = true
			ladder[#ladder + 1] = { query = query, record = rec or record }
		end
	end

	-- A learned query is a user correction: it must be scored against
	-- itself, not against the (possibly wrong) title from the filename.
	if learned_query and #learned_query > 0 then
		add(learned_query, record_for_query(learned_query))
	end

	local title = record.title
	local ep_tag
	if record.season and record.episode then
		ep_tag = string.format('S%02dE%02d', record.season, record.episode)
	elseif record.episode then
		ep_tag = 'Episode ' .. tostring(record.episode)
	end

	if ep_tag then
		if record.year then add(title .. ' ' .. record.year .. ' ' .. ep_tag) end
		add(title .. ' ' .. ep_tag)
		if record.episode and record.season then
			add(title .. ' Episode ' .. tostring(record.episode))
		elseif record.episode then
			add(title .. ' ' .. tostring(record.episode))
		end
	end

	if record.year then add(title .. ' ' .. record.year) end
	add(title)

	-- Last resort: the first 2-3 significant words of the title. Split on any
	-- non-alphanumeric separator, otherwise a hyphenated title such as
	-- `Dar-e-Nijaat` is a single word and the fallback rung would be identical
	-- to the full title (and therefore dropped as a duplicate).
	local words = {}
	for word in title:gmatch('[%w]+') do
		local lower_word = word:lower()
		if not STOPWORDS[lower_word] and #word > 1 then words[#words + 1] = word end
	end
	if #words > 1 then
		add(table.concat(words, ' ', 1, math.min(3, #words)))
		if #words > 2 then add(table.concat(words, ' ', 1, 2)) end
	end

	while #ladder > query_ladder_max do ladder[#ladder] = nil end
	return ladder
end

-- Flattens a ladder into its query strings (for logging and the OSD).
local function queries_of(ladder)
	local out = {}
	for _, entry in ipairs(ladder) do out[#out + 1] = entry.query end
	return out
end

local function display_name(record)
	local text = record.title
	if record.season and record.episode then
		text = string.format('%s S%02dE%02d', text, record.season, record.episode)
	elseif record.episode then
		text = string.format('%s Episode %d', text, record.episode)
	elseif record.year then
		text = string.format('%s (%s)', text, record.year)
	end
	return text
end

local function format_record(record)
	return string.format('title="%s" year=%s season=%s episode=%s series=%s group=%s conf=%.2f',
		record.title, tostring(record.year), tostring(record.season), tostring(record.episode),
		tostring(record.is_series), tostring(record.release_group), record.confidence)
end

-- ---------------------------------------------------------------------------
-- Layer 3: candidate scoring
-- ---------------------------------------------------------------------------

local function sig_words(text)
	local words = {}
	for word in tostring(text or ''):lower():gmatch('[%w]+') do
		if not STOPWORDS[word] then words[#words + 1] = word end
	end
	-- dedupe
	local seen, unique = {}, {}
	for _, word in ipairs(words) do
		if not seen[word] then
			seen[word] = true
			unique[#unique + 1] = word
		end
	end
	return unique
end

local function jaccard(a, b)
	local sa, sb = {}, {}
	for _, word in ipairs(a) do sa[word] = true end
	for _, word in ipairs(b) do sb[word] = true end
	local inter, union = 0, 0
	for word in pairs(sa) do
		union = union + 1
		if sb[word] then inter = inter + 1 end
	end
	for word in pairs(sb) do
		if not sa[word] then union = union + 1 end
	end
	if union == 0 then return 0 end
	return inter / union
end

-- Returns a score in [0,1] or nil when the candidate is definitely wrong.
local function score_candidate(attrs, record, langs)
	if type(attrs) ~= 'table' then return nil end
	if type(attrs.files) ~= 'table' or not attrs.files[1] or not attrs.files[1].file_id then
		return nil
	end

	local lang = tostring(attrs.language or ''):lower()
	local lang_ok = false
	for _, wanted in ipairs(langs) do
		if lang == wanted or (wanted == 'en' and lang == 'eng') then
			lang_ok = true
			break
		end
	end
	if not lang_ok then return nil end

	-- An exact file-hash match is definitive: no title guessing involved.
	if attrs.moviehash_match == true then return 1.0 end

	local feature = attrs.feature_details or {}

	-- The release name is the encode the subtitle was timed against; the
	-- feature is the movie/series the uploader filed it under. Uploads get
	-- filed under the wrong feature often enough that neither signal alone
	-- is reliable, so a candidate is kept when EITHER of them names the
	-- same title. The file name is the fallback for releases that carry no
	-- title at all (`720p.HDDVD.DTS.x264-ESiR`).
	local candidate = parse_name(attrs.release or '')
	if not candidate or #candidate.title < 2 then
		candidate = parse_name(attrs.files[1].file_name or '')
	end
	if not candidate or #candidate.title < 2 then return nil end

	local record_words = sig_words(record.title)
	local release_jaccard = jaccard(record_words, sig_words(candidate.title))
	local feature_jaccard = 0
	if feature.title then
		feature_jaccard = jaccard(record_words, sig_words(feature.title))
	end

	-- Zero significant-token overlap on BOTH signals: this candidate is
	-- definitely not the file we are looking for.
	if release_jaccard <= 0 and feature_jaccard <= 0 then return nil end

	local title_jaccard = math.max(release_jaccard, feature_jaccard)

	if record.year then
		local candidate_year = candidate.year
		if not candidate_year and feature_jaccard > 0 then
			candidate_year = tonumber(feature.year)
		end
		if candidate_year then
			local diff = math.abs(tonumber(record.year) - candidate_year)
			if diff > 1 then return nil end
			title_jaccard = title_jaccard + 0.15
		end
	end

	if record.episode and candidate.episode then
		if tonumber(record.episode) ~= tonumber(candidate.episode) then return nil end
		title_jaccard = title_jaccard + 0.20
	elseif record.episode and not candidate.episode then
		-- A season pack can still contain the episode; give it a small lift so
		-- it is not preferred over an exact episode, but do not reject it.
		title_jaccard = title_jaccard + 0.02
	end

	if record.season and candidate.season then
		if tonumber(record.season) ~= tonumber(candidate.season) then return nil end
		title_jaccard = title_jaccard + 0.05
	end

	-- Ranking only: prefer the release whose resolution/source/codec matches
	-- the file. Never a hard filter, so a lone 720p sub still wins.
	local compact = tostring(attrs.release or attrs.files[1].file_name or ''):lower():gsub('[^%w]', '')
	for _, tag in ipairs(record.tech or {}) do
		if compact:find(tag, 1, true) then title_jaccard = title_jaccard + 0.03 end
	end

	return title_jaccard
end

-- A compressed "release signature": filename minus extension, minus the
-- trailing `-GROUP`, minus punctuation. Used only by single mode to decide
-- whether one candidate came from the same release as the file.
local function release_core(name)
	local text = tostring(name or ''):gsub('%.[%w]+$', '')
	text = text:gsub('%-[^%-%s]+_?%w*$', '')
	return text:lower():gsub('[^%w]', '')
end

local function collect_candidates(subs, record, langs, only_hash)
	local results, seen = {}, {}
	for _, candidate in ipairs(subs or {}) do
		local attrs = candidate and candidate.attributes
		if type(attrs) == 'table' then
			if not only_hash or attrs.moviehash_match == true then
				local score = score_candidate(attrs, record, langs)
				local file_id = attrs.files and attrs.files[1] and attrs.files[1].file_id
				if score and score >= min_score and file_id and not seen[file_id] then
					seen[file_id] = true
					results[#results + 1] = {
						attrs = attrs,
						score = score,
						file_id = file_id,
						release = tostring(attrs.release or attrs.files[1].file_name or 'subtitle'),
						language = tostring(attrs.language or '?'),
						hi = attrs.hearing_impaired == true,
						downloads = tonumber(attrs.download_count) or 0,
						hash = attrs.moviehash_match == true,
					}
				end
			end
		end
	end

	table.sort(results, function(a, b)
		if a.hash ~= b.hash then return a.hash end
		if math.abs(a.score - b.score) > 0.0001 then return a.score > b.score end
		if a.hi ~= b.hi then return not a.hi end
		return a.downloads > b.downloads
	end)

	return results
end

-- ---------------------------------------------------------------------------
-- ziggy backend (uosc's binary, same credentials)
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

local function search_hash(path, langs, callback)
	run_ziggy({
		'search-subtitles',
		'--languages', table.concat(langs, ','),
		'--page', '1',
		'--hash', path,
	}, callback)
end

local function search_text(path, query, langs, callback)
	run_ziggy({
		'search-subtitles',
		'--languages', table.concat(langs, ','),
		'--page', '1',
		'--query', query,
	}, callback)
end

local function ensure_dir(dir)
	local probe = io.open(dir .. '/.autosubs_probe', 'w')
	if probe then
		probe:close()
		os.remove(dir .. '/.autosubs_probe')
		return true
	end
	os.execute('mkdir "' .. dir .. '" >nul 2>nul')
	probe = io.open(dir .. '/.autosubs_probe', 'w')
	if probe then
		probe:close()
		os.remove(dir .. '/.autosubs_probe')
		return true
	end
	return false
end

local function subtitles_dir()
	local dir = expand(uosc_settings().subtitles_dir)
	local probe_path = dir .. '/.autosubs_write_test'
	local probe = io.open(probe_path, 'w')
	if probe then
		probe:close()
		os.remove(probe_path)
		return dir
	end
	-- The configured folder is missing: create it rather than littering the
	-- video's own folder with subtitle files.
	if ensure_dir(dir) then return dir end
	return dirname(mp.get_property('path') or '')
end

-- ---------------------------------------------------------------------------
-- Layer 5: learned corrections
-- ---------------------------------------------------------------------------

local learned_path = expand('~~/cache/autosubs/learned.json')
local learned
local learned_dirty = false

local function looked_key(path)
	return basename(path):lower():gsub('%.[%w]+$', ''):gsub('[^%w]', '')
end

local function load_learned()
	if learned then return learned end
	learned = {}
	local raw = read_file(learned_path)
	if raw then
		local ok, data = pcall(utils.parse_json, raw)
		if ok and type(data) == 'table' then
			for key, value in pairs(data) do
				if type(key) == 'string' and type(value) == 'string' then
					learned[key] = value
				end
			end
		end
	end
	return learned
end

local function save_learned()
	if not learned_dirty then return end
	if not ensure_dir(dirname(learned_path)) then return end

	local count = 0
	for _ in pairs(learned) do count = count + 1 end
	if count > 300 then
		for key in pairs(learned) do
			learned[key] = nil
			count = count - 1
			if count <= 300 then break end
		end
	end

	local ok, json = pcall(utils.format_json, learned)
	if not ok or not json then return end
	local f = io.open(learned_path, 'w')
	if f then
		f:write(json)
		f:close()
		learned_dirty = false
		msg.info('learned cache saved (' .. tostring(count) .. ' entries)')
	end
end

local function remember_query(path, query)
	if not query or #query == 0 then return end
	load_learned()
	local key = looked_key(path)
	if learned[key] == query then return end
	learned[key] = query
	learned_dirty = true
	msg.info('learned "' .. key .. '" -> "' .. query .. '"')
end

-- ---------------------------------------------------------------------------
-- download + attach
-- ---------------------------------------------------------------------------

local function load_subtitle(file, label, lang)
	-- `sub-add url [flags] [title] [lang]`: passing the language keeps the
	-- track filterable in mpv's track menu.
	if lang and lang ~= '' then
		mp.commandv('sub-add', file, 'select', label, lang)
	else
		mp.commandv('sub-add', file, 'select', label)
	end
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

local function download_candidate(result, path, query_used, manual)
	run_ziggy({
		'download-subtitles',
		'--file-id', tostring(result.file_id),
		'--destination', subtitles_dir(),
	}, function(err, data)
		if err or type(data) ~= 'table' or type(data.file) ~= 'string' then
			report_failure('subtitle download failed: ' .. tostring(err or 'invalid response'), manual)
			return
		end
		load_subtitle(data.file, result.release, result.language)
		if query_used then
			remember_query(path, query_used)
			save_learned()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Layer 4: uosc results menu (palette = editable query)
-- ---------------------------------------------------------------------------

local menu_state = {}

local function menu_items(results)
	local items = {}
	for _, result in ipairs(results) do
		local hint = result.language
		if result.hi then hint = hint .. ' · HI' end
		if result.hash then hint = hint .. ' · hash' end
		hint = hint .. ' · ' .. tostring(result.downloads) .. ' downloads'
		items[#items + 1] = {
			title = result.release,
			hint = hint,
			icon = result.hash and 'check' or 'subtitles',
			value = { kind = 'download', file_id = result.file_id, label = result.release, lang = result.language },
		}
	end
	return items
end

local function build_menu(record, query, results, source)
	local items = menu_items(results)
	if #items == 0 then
		items[1] = {
			title = query and ('No matches for "' .. truncate(query, 48) .. '"') or 'No matches',
			align = 'center', muted = true, italic = true, selectable = false,
		}
	end
	items[#items + 1] = { separator = true }
	items[#items + 1] = {
		title = 'Type a different title and press Enter',
		align = 'center', muted = true, italic = true, selectable = false,
	}

	local footnote
	if source == 'hash' then
		footnote = 'exact file-hash match'
	elseif query then
		footnote = 'searched "' .. query .. '" · ' .. tostring(#results) .. ' match' .. (#results == 1 and '' or 'es')
	else
		footnote = tostring(#results) .. ' matches'
	end

	return {
		type = 'autosubs-results',
		title = 'Subtitles: ' .. display_name(record),
		footnote = footnote,
		search_style = 'palette',
		search_debounce = 'submit',
		-- 'callback' makes uosc deliver the search event through the same
		-- `menu-event` channel as the item activation.
		--
		-- Do NOT use a command array here (`{ 'script-message-to', ... }`):
		-- uosc dispatches `on_search` with `mp.command_native(<table>)`, and
		-- `script-message-to` is a variadic command - mpv >= 0.41 rejects it
		-- with "this command uses a variable number of arguments, which does
		-- not work with named arguments". The typed query would be silently
		-- lost.
		on_search = 'callback',
		search_suggestion = query or record.title,
		items = items,
		callback = { 'autosubs', 'menu-event' },
		keep_open = false,
	}
end

local function send_menu(data)
	-- Replace any previous autosubs menu instead of stacking them.
	mp.commandv('script-message-to', 'uosc', 'close-menu', 'autosubs-results')
	mp.add_timeout(0.02, function()
		mp.commandv('script-message-to', 'uosc', 'open-menu', utils.format_json(data))
	end)
end

local function update_menu(data)
	mp.commandv('script-message-to', 'uosc', 'update-menu', utils.format_json(data))
end

local function show_results(path, record, query, results, source, manual)
	menu_state = {
		path = path,
		record = record,
		search_record = record,
		query = query,
		source = source,
		manual = manual,
		seq = (menu_state.seq or 0) + 1,
	}
	send_menu(build_menu(record, query, results, source))
end

-- ---------------------------------------------------------------------------
-- lookup orchestration
-- ---------------------------------------------------------------------------

local function score_response(data, record, langs, only_hash)
	local subs = type(data and data.data) == 'table' and data.data or {}
	return collect_candidates(subs, record, langs, only_hash)
end

local function deliver(path, record, query, results, source, manual)
	if #results == 0 then
		msg.info(string.format('no confident match for "%s"', tostring(query or display_name(record))))
		if manual or auto_load == 'prompt' then
			show_results(path, record, query, results, source, manual)
		end
		return
	end

	if auto_load == 'single' and not manual then
		local chosen
		if #results == 1 then
			chosen = results[1]
		else
			local wanted = release_core(basename(path))
			local exact = {}
			for _, result in ipairs(results) do
				if wanted ~= '' and release_core(result.release) == wanted then
					exact[#exact + 1] = result
				end
			end
			if #exact == 1 then chosen = exact[1] end
		end
		if chosen then
			msg.info('single strong match, loading: ' .. chosen.release)
			download_candidate(chosen, path, query, manual)
		else
			msg.info(string.format('%d candidates, none uniquely strong (single policy)', #results))
		end
		return
	end

	show_results(path, record, query, results, source, manual)
end

local function run_ladder(path, record, langs, manual, index)
	index = index or 1
	local ladder = menu_state.ladder
	if index > #ladder then
		deliver(path, record, nil, {}, 'text', manual)
		return
	end

	local entry = ladder[index]
	local query = entry.query
	local rung_record = entry.record or record
	msg.info(string.format('rung %d/%d: "%s"', index, #ladder, query))

	search_text(path, query, langs, function(err, data)
		if err then
			report_failure('subtitle search failed: ' .. tostring(err), manual)
			deliver(path, rung_record, query, {}, 'text', manual)
			return
		end

		local results = score_response(data, rung_record, langs, false)
		local raw = type(data and data.data) == 'table' and #data.data or 0
		msg.info(string.format('rung %d: %d raw, %d above score %.2f', index, raw, #results, min_score))

		if #results > 0 then
			deliver(path, rung_record, query, results, 'text', manual)
		else
			run_ladder(path, record, langs, manual, index + 1)
		end
	end)
end

local function file_size(path)
	local info = utils.file_info(path)
	return info and info.size or 0
end

local function lookup(path, record, manual)
	local langs = preferred_languages()
	load_learned()
	local learned_query = learned[looked_key(path)]
	if learned_query then
		msg.info('learned query for this file: "' .. learned_query .. '"')
	end

	menu_state.ladder = build_ladder(record, learned_query)
	msg.info('parsed ' .. format_record(record))
	msg.info('ladder: ' .. utils.format_json(queries_of(menu_state.ladder)))

	-- Layer 0: hash first, so the filename never has to be right.
	if hash_first and file_size(path) >= 131072 then
		msg.info('layer 0: moviehash lookup')
		search_hash(path, langs, function(err, data)
			if err then
				report_failure('subtitle hash lookup failed: ' .. tostring(err), manual)
				deliver(path, record, nil, {}, 'text', manual)
				return
			end
			local hash_results = score_response(data, record, langs, true)
			msg.info(string.format('layer 0: %d raw, %d hash matches', type(data and data.data) == 'table' and #data.data or 0, #hash_results))
			if #hash_results > 0 then
				deliver(path, record, nil, hash_results, 'hash', manual)
			else
				run_ladder(path, record, langs, manual, 1)
			end
		end)
	else
		run_ladder(path, record, langs, manual, 1)
	end
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

local function metadata_title()
	local md = mp.get_property_native('metadata') or {}
	for key, value in pairs(md) do
		if tostring(key):lower() == 'title' and type(value) == 'string' then
			return value
		end
	end
	return nil
end

local function usable_record(record)
	if not record then return false end
	if #record.title < 2 then return false end
	-- A single very short token carries no search signal ("lg").
	if #record.title < 3 and not record.year then return false end
	return true
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

	local record = parse_media(path, manual and nil or metadata_title())
	if not usable_record(record) then
		msg.info('no usable title in filename: ' .. tostring(path))
		if manual then
			mp.osd_message('Auto-subs: no title in filename, opening search.', 3)
			open_uosc_picker()
		else
			report_failure('no usable title in filename: ' .. basename(path), manual)
		end
		return
	end

	lookup(path, record, manual)
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
	menu_state = {}

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

-- ---------------------------------------------------------------------------
-- menu events / manual binding / debug helpers
-- ---------------------------------------------------------------------------

-- Runs a user-typed query and refreshes the results menu with it.
local function run_menu_search(query)
	if not menu_state.path then return end
	query = trim(query)
	if #query == 0 then return end

	menu_state.seq = (menu_state.seq or 0) + 1
	local seq = menu_state.seq
	local langs = preferred_languages()
	local record = record_for_query(query)

	msg.info('menu search: "' .. query .. '"')
	search_text(menu_state.path, query, langs, function(err, data)
		if seq ~= menu_state.seq then return end -- stale response
		if err then
			report_failure('subtitle search failed: ' .. tostring(err), menu_state.manual)
			return
		end
		local results = score_response(data, record, langs, false)
		msg.info(string.format('menu search "%s": %d matches above score %.2f', query, #results, min_score))

		menu_state.query = query
		menu_state.search_record = record
		update_menu(build_menu(record, query, results, 'text'))
	end)
end

mp.register_script_message('menu-event', function(json)
	local data = utils.parse_json(json)
	if type(data) ~= 'table' then return end

	-- uosc sends the palette submission through the same callback channel.
	if data.type == 'search' then
		run_menu_search(tostring(data.query or ''))
		return
	end

	if data.type ~= 'activate' then return end
	local value = data.value
	if type(value) ~= 'table' or value.kind ~= 'download' then return end
	if not menu_state.path then return end
	local result = {
		file_id = value.file_id,
		release = value.label,
		language = value.lang,
	}
	download_candidate(result, menu_state.path, menu_state.query, menu_state.manual)
end)

-- Also reachable directly, e.g. from another script or a custom binding.
mp.register_script_message('menu-search', function(query)
	run_menu_search(query)
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

-- Debug: `script-message-to autosubs debug-query [path]` prints the parsed
-- record and the full ladder for any filename, without touching the network.
mp.register_script_message('debug-query', function(arg)
	local path = (arg and arg ~= '' and arg) or current_path()
	if not path then
		mp.osd_message('Auto-subs: no file.', 3)
		return
	end
	local record = parse_media(path, nil)
	if not usable_record(record) then
		msg.info('autosubs debug: no usable record for ' .. tostring(path))
		mp.osd_message('Auto-subs: no usable title.', 4)
		return
	end
	local ladder = build_ladder(record, nil)
	msg.info('autosubs debug: ' .. tostring(path))
	msg.info('autosubs debug: ' .. format_record(record))
	for i, entry in ipairs(ladder) do
		msg.info(string.format('autosubs debug: rung %d: "%s"', i, entry.query))
	end
	mp.osd_message('query ladder: ' .. table.concat(queries_of(ladder), ' | '), 8)
end)
