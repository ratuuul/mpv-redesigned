-- sponsorblock_minimal.lua
--
-- This script skips sponsored segments of YouTube videos
-- using data from https://github.com/ajayyy/SponsorBlock
--
-- Everything is fetched with one curl request per file and every category
-- is sent in that single request (see script-opts/sponsorblock_minimal.conf).
--
-- Behaviour that the fixes below guarantee:
--   * A skip that could not leave the segment (mpv clamped the seek back
--     into it) is never retried, so the OSD cannot spam.
--   * Every segment is skipped automatically at most once per file. Seeking
--     back into it plays it normally, so rewatching is still possible.
--   * A video without segments is not an error and produces no warning.
--   * The key binding is registered once, when the script loads.
--   * hash mode computes SHA-256 in Lua, so no external tool is needed.

local opt = require 'mp.options'
local utils = require 'mp.utils'

local ranges = nil       -- segment list of the current file
local last_skip = nil    -- {from, to} of the segment we just skipped
local enabled = true     -- user preference, toggled with `b`
local observing = false  -- is the time-pos observer currently attached?

local category_names = {
	["Chapter"] = "chapter",
	["Endcards/Credits"] = "outro",
	["Filler Tangent"] = "filler",
	["Highlight"] = "poi_highlight",
	["Interaction Reminder"] = "interaction",
	["Intermission/Intro Animation"] = "intro",
	["Non-Music Section"] = "music_offtopic",
	["Preview/Recap"] = "preview",
	["Sponsor"] = "sponsor",
	["Unpaid/Self Promotion"] = "selfpromo",
}

local options = {
	server = "https://sponsor.ajay.app/api/skipSegments",

	-- Categories to fetch and skip
	categories = "sponsor",

	-- Set this to "true" to use sha256HashPrefix instead of videoID
	hash = ""
}

opt.read_options(options)

local categories = {}
for str in string.gmatch(string.lower(options.categories), "([^;,]+)") do
	categories[#categories + 1] = str
end

-- --------------------------------------------------------------- sha-256 --
-- hash=true needs the first four hex characters of the SHA-256 of the video
-- ID. `sha256sum` is a Unix tool and is not on a stock Windows PATH, so the
-- digest is computed here instead of shelling out to something that may not
-- exist. mpv's Lua has no integer type, so the 32 bit arithmetic is done
-- with doubles (exact up to 2^53); the `bit` library is only used when the
-- interpreter happens to provide it.
local sha256_K = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local has_bit = type(bit) == "table" and type(bit.bxor) == "function"

local function u32(x)
	x = x % 4294967296
	if x < 0 then x = x + 4294967296 end
	return x
end

local function bxor(a, b)
	if has_bit then return u32(bit.bxor(a, b)) end
	local r, p = 0, 1
	a, b = u32(a), u32(b)
	for _ = 1, 32 do
		local x, y = a % 2, b % 2
		if x ~= y then r = r + p end
		a = (a - x) / 2
		b = (b - y) / 2
		p = p * 2
	end
	return r
end

local function band(a, b)
	if has_bit then return u32(bit.band(a, b)) end
	local r, p = 0, 1
	a, b = u32(a), u32(b)
	for _ = 1, 32 do
		local x, y = a % 2, b % 2
		if x == 1 and y == 1 then r = r + p end
		a = (a - x) / 2
		b = (b - y) / 2
		p = p * 2
	end
	return r
end

local function bnot(a)
	if has_bit then return u32(bit.bnot(a)) end
	return 4294967295 - u32(a)
end

local function rshift(a, n)
	if has_bit then return u32(bit.rshift(a, n)) end
	return math.floor(u32(a) / 2 ^ n)
end

local function ror(a, n)
	if has_bit then return u32(bit.ror(a, n)) end
	a = u32(a)
	local p = 2 ^ n
	return math.floor(a / p) + (a % p) * (4294967296 / p)
end

local function add32(a, b)
	return u32(a + b)
end

local function sha256_hex(msg)
	local h = {
		0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
		0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
	}

	local bitlen = #msg * 8
	msg = msg .. "\128" .. string.rep("\0", (55 - #msg) % 64)
	for i = 7, 0, -1 do
		msg = msg .. string.char(math.floor(bitlen / 2 ^ (8 * i)) % 256)
	end

	for chunk = 1, #msg, 64 do
		local w = {}
		for i = 0, 15 do
			local a, b, c, d = string.byte(msg, chunk + i * 4, chunk + i * 4 + 3)
			w[i] = a * 16777216 + b * 65536 + c * 256 + d
		end
		for i = 16, 63 do
			local x = w[i - 15]
			local y = w[i - 2]
			local s0 = bxor(bxor(ror(x, 7), ror(x, 18)), rshift(x, 3))
			local s1 = bxor(bxor(ror(y, 17), ror(y, 19)), rshift(y, 10))
			w[i] = add32(add32(add32(w[i - 16], s0), w[i - 7]), s1)
		end

		local a, b, c, d = h[1], h[2], h[3], h[4]
		local e, f, g, hh = h[5], h[6], h[7], h[8]
		for i = 0, 63 do
			local S1 = bxor(bxor(ror(e, 6), ror(e, 11)), ror(e, 25))
			local ch = bxor(band(e, f), band(bnot(e), g))
			local t1 = add32(add32(add32(add32(hh, S1), ch), sha256_K[i + 1]), w[i])
			local S0 = bxor(bxor(ror(a, 2), ror(a, 13)), ror(a, 22))
			local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
			local t2 = add32(S0, maj)
			hh = g; g = f; f = e
			e = add32(d, t1)
			d = c; c = b; b = a
			a = add32(t1, t2)
		end

		h[1] = add32(h[1], a); h[2] = add32(h[2], b)
		h[3] = add32(h[3], c); h[4] = add32(h[4], d)
		h[5] = add32(h[5], e); h[6] = add32(h[6], f)
		h[7] = add32(h[7], g); h[8] = add32(h[8], hh)
	end

	local hexdigits = "0123456789abcdef"
	local out = {}
	for i = 1, 8 do
		local s = ""
		for j = 1, 8 do
			local d = math.floor(h[i] / 16 ^ (8 - j)) % 16 + 1
			s = s .. hexdigits:sub(d, d)
		end
		out[i] = s
	end
	return table.concat(out)
end

-- The SponsorBlock privacy mode wants the first four hex characters of the
-- SHA-256 of the video ID.
local function hash_prefix(youtube_id)
	local ok, digest = pcall(sha256_hex, youtube_id)
	if not ok or type(digest) ~= "string" or #digest < 4 then return nil end
	return digest:sub(1, 4)
end

-- ------------------------------------------------------------------ skip --
-- Observer on time-pos. Fires once per frame while the playhead moves.
function skip_ads(name, pos)
	if not pos or type(ranges) ~= 'table' then return end

	-- A seek can be clamped by mpv (--length/--end, A-B loop, or simply the
	-- last keyframe before EOF), leaving the playhead inside the very
	-- segment we just jumped out of. Block that segment until playback has
	-- genuinely left it, otherwise the observer re-fires on every frame and
	-- spams the OSD.
	if last_skip then
		if pos >= last_skip[1] and pos < last_skip[2] then
			return
		end
		last_skip = nil
	end

	for _, i in pairs(ranges) do
		if type(i) == 'table' and type(i.segment) == 'table' and #i.segment >= 2 then
			local from, to = i.segment[1], i.segment[2]
			if type(from) == 'number' and type(to) == 'number' and from <= pos and to > pos and not i.skipped then
				-- Policy (Bug B): one automatic skip per segment per file.
				-- Seeking back into the segment afterwards plays it through
				-- instead of being skipped again, so rewatching an intro or
				-- a recap is still possible, and the player can never get
				-- stuck in a skip loop. Toggling `b` does not re-arm it.
				i.skipped = true

				local now = mp.get_property_number("time-pos") or pos

				-- Keep the target inside the file. A tail segment (outro,
				-- preview) can end past the duration; an unclamped seek
				-- there leaves the playhead inside the segment and loops.
				local target = to + 0.01
				local duration = mp.get_property_number("duration")
				if duration and duration > 0 then
					target = math.min(target, duration - 0.1)
				end

				if target > now then
					mp.msg.verbose(("JUMP %.2f -> %.2f"):format(now, target))
					mp.osd_message(("[sponsorblock] skipping forward %ds"):format(math.floor(target - now + 0.5)))
					--need to do the +0.01 otherwise mpv will start spamming skip sometimes
					--example: https://www.youtube.com/watch?v=4ypMJzeNooo
					mp.set_property("time-pos", target)
					last_skip = { from, to }
				end
				return
			end
		end
	end
end

-- --------------------------------------------------------------- fetching --
local function is_array(t)
	if type(t) ~= 'table' then return false end
	for k in pairs(t) do
		if type(k) ~= 'number' then return false end
	end
	return true
end

-- Drop entries that are not a usable {start, end} segment. The API can
-- return error objects or entries without a segment field; indexing those
-- blindly is what used to crash the script on a nil `segment`.
local function valid_segments(list)
	if not is_array(list) then return nil end
	local out = {}
	for _, i in ipairs(list) do
		if type(i) == 'table' and type(i.segment) == 'table' and #i.segment >= 2
			and type(i.segment[1]) == 'number' and type(i.segment[2]) == 'number' then
			out[#out + 1] = i
		end
	end
	if #out == 0 then return nil end
	return out
end

-- Splits the raw curl output into the body and the HTTP status code.
-- curl appends the marker to whatever the server returned, so the marker is
-- searched from the back and everything before it is the body.
local function split_response(raw)
	local s, e, code = raw:find("<<HTTP:(%d+)>>", 1, false)
	local last = nil
	while s do
		last = { s, e, code }
		s, e, code = raw:find("<<HTTP:(%d+)>>", e + 1, false)
	end
	if not last then return raw, nil end
	return raw:sub(1, last[1] - 1), last[3]
end

function fetch_sponsor_segments(youtube_id)
	local args = {
		"curl", "-L", "-s", "-G",
		"--write-out", "<<HTTP:%{http_code}>>",
		"--data-urlencode", ("categories=%s"):format(utils.format_json(categories)),
	}
	local url = options.server
	local use_hash = false

	if options.hash == "true" then
		local prefix = hash_prefix(youtube_id)
		if prefix then
			use_hash = true
			url = ("%s/%s"):format(url, prefix)
		else
			mp.msg.warn("sponsorblock: could not hash the video ID; using the plain video ID instead")
		end
	end

	if not use_hash then
		table.insert(args, "--data-urlencode")
		table.insert(args, "videoID=" .. youtube_id)
	end
	table.insert(args, url)

	local res = mp.command_native{
		name = "subprocess",
		capture_stdout = true,
		capture_stderr = true,
		playback_only = false,
		args = args
	}
	if not res then
		mp.msg.warn("sponsorblock: could not run curl, no segments for this file")
		return nil
	end
	if res.status ~= 0 then
		mp.msg.warn(("sponsorblock: the request failed (curl exit %d), no segments for this file"):format(res.status or -1))
		return nil
	end

	local body, status = split_response(res.stdout or "")

	-- A video without segments is answered with HTTP 404 and a short body.
	-- That is not an error, so it must stay quiet (or verbose at most).
	if status == "404" then
		mp.msg.verbose("sponsorblock: no segments for this video (HTTP 404)")
		return nil
	end
	if status and status ~= "200" then
		mp.msg.verbose(("sponsorblock: no segments for this video (HTTP %s)"):format(status))
		return nil
	end
	if body == "" then
		mp.msg.verbose("sponsorblock: no segments for this video (empty API response)")
		return nil
	end

	local json = utils.parse_json(body)
	if json == nil then
		mp.msg.verbose("sponsorblock: no segments for this video (the API response is not JSON)")
		return nil
	end
	if type(json) == 'table' and json.error then
		mp.msg.verbose(("sponsorblock: no segments for this video (API error: %s)"):format(tostring(json.error)))
		return nil
	end
	if not is_array(json) then
		mp.msg.verbose("sponsorblock: no segments for this video (the API response is not a JSON array)")
		return nil
	end
	if #json == 0 then
		mp.msg.verbose("sponsorblock: no segments for this video")
		return nil
	end

	if use_hash then
		for _, i in pairs(json) do
			if type(i) == 'table' and i.videoID == youtube_id then
				return valid_segments(i.segments)
			end
		end
		return nil
	end

	return valid_segments(json)
end

function fetch_ranges()
	local video_path = mp.get_property("path", "")
	local video_referer = string.match(mp.get_property("http-header-fields", ""), "Referer:([^,]+)") or ""

	local urls = {
		"ytdl://youtu%.be/([%w-_]+).*",
		"ytdl://w?w?w?%.?youtube%.com/v/([%w-_]+).*",
		"https?://youtu%.be/([%w-_]+).*",
		"https?://w?w?w?%.?youtube%.com/v/([%w-_]+).*",
		"/watch.*[?&]v=([%w-_]+).*",
		"/embed/([%w-_]+).*",
		"^ytdl://([%w-_]+)$",
		-- local file names: "Title [videoid].ext" (the template download.lua
		-- uses) and "title-videoid.ext"
		"%[([%w-_]+)%]%.",
		"-([%w-_]+)%."
	}
	local youtube_id = nil
	local purl = mp.get_property("metadata/by-key/PURL", "")
	for i,url in ipairs(urls) do
		youtube_id = youtube_id or string.match(video_path, url) or string.match(video_referer, url) or string.match(purl, url)
		if youtube_id then break end
	end

	if youtube_id and string.len(youtube_id) >= 11 then
		youtube_id = string.sub(youtube_id, 1, 11)
		return fetch_sponsor_segments(youtube_id)
	end
end

function get_ranges_from_chapters()
	local skipped_categories = {}
	for _, category in ipairs(categories) do
		skipped_categories[category] = true
	end

	local ranges = {}

	local chapters = mp.get_property_native("chapter-list") or {}
	local duration = mp.get_property_native("duration")
	local have_sponsorblock_chapters = false

	for i, chapter in ipairs(chapters) do
		local categories_string = string.match(chapter.title, "%[SponsorBlock%]:%s(.+)")

		if categories_string then
			have_sponsorblock_chapters = true

			for category_name in string.gmatch(categories_string, "([^,]+),?%s?") do
				local category = category_names[category_name]
				if skipped_categories[category] then
					local to = duration
					if i < #chapters then
						to = chapters[i+1].time
					end
					if type(to) == 'number' and type(chapter.time) == 'number' then
						table.insert(ranges, {["segment"] = {chapter.time, to}, ["category"] = category})
					end
				end
			end
		end
	end

	if not have_sponsorblock_chapters then
		return nil
	end

	return ranges
end

-- ------------------------------------------------------------- lifecycle --
-- The observer is attached at most once. Keeping the flag here makes it
-- impossible to register it twice, no matter how often a file is loaded or
-- how often `b` is pressed.
local function set_observer(on)
	if on and not observing then
		mp.observe_property("time-pos", "native", skip_ads)
		observing = true
	elseif not on and observing then
		mp.unobserve_property(skip_ads)
		observing = false
	end
end

function file_loaded()
	-- Reset per-file state; segments are rebuilt for the new file.
	set_observer(false)
	last_skip = nil
	ranges = get_ranges_from_chapters() or fetch_ranges()

	if type(ranges) == 'table' and #ranges > 0 then
		set_observer(enabled)
	end
end

function end_file()
	set_observer(false)
	ranges = nil
	last_skip = nil
end

function toggle()
	enabled = not enabled
	if enabled then
		mp.osd_message("[sponsorblock] on")
	else
		mp.osd_message("[sponsorblock] off")
	end
	set_observer(enabled and type(ranges) == 'table' and #ranges > 0)
end

-- Registered once at script load, not per file.
mp.add_key_binding("b", "sponsorblock", toggle)
mp.register_event("file-loaded", file_loaded)
mp.register_event("end-file", end_file)
