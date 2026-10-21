-- sponsorblock_minimal.lua
--
-- This script skips sponsored segments of YouTube videos
-- using data from https://github.com/ajayyy/SponsorBlock

local opt = require 'mp.options'
local utils = require 'mp.utils'

local ON = false
local ranges = nil
local last_skip = nil -- {from, to} of the segment just skipped; see skip_ads
local sha256_state = nil -- nil = untested, false = unavailable, true = usable

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

function skip_ads(name,pos)
	if not pos or type(ranges) ~= 'table' then return end

	-- A seek can be clamped by mpv (--length/--end, A-B loop, or simply the
	-- last keyframe before EOF), leaving the playhead inside the very segment
	-- we just jumped out of. Block that segment until playback has genuinely
	-- left it, otherwise the observer re-fires on every frame and spams OSD.
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
				-- Policy: one automatic skip per segment per file. Seeking back
				-- to rewatch an intro/recap is respected (it will play through
				-- instead of being skipped again), and `b` off/on does not
				-- re-arm, so the player can never get stuck in a skip loop.
				i.skipped = true

				local now = mp.get_property_number("time-pos") or pos

				-- Keep the target inside the file. A tail segment (outro,
				-- preview) can end past duration; an unclamped seek there
				-- leaves the playhead inside the segment and loops.
				local target = to + 0.01
				local duration = mp.get_property_number("duration")
				if duration and duration > 0 then
					target = math.min(target, duration - 0.1)
				end

				if target > now then
					mp.msg.verbose(("skip %.2f -> %.2f"):format(now, target))
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

local function is_array(t)
	if type(t) ~= 'table' then return false end
	for k in pairs(t) do
		if type(k) ~= 'number' then return false end
	end
	return true
end

-- Drop entries that are not a usable {start, end} segment (the API can return
-- error strings or objects with a missing segment field).
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

-- hash=true is the privacy mode. sha256sum is a Unix tool; detect it once and
-- fall back to the plain video ID instead of failing silently.
local function have_sha256sum()
	if sha256_state ~= nil then return sha256_state end
	local res = mp.command_native{
		name = "subprocess",
		capture_stdout = true,
		capture_stderr = true,
		playback_only = false,
		args = {"sha256sum", "--version"}
	}
	sha256_state = res ~= nil and res.status == 0
	if not sha256_state then
		mp.msg.warn("sponsorblock: hash=true needs sha256sum, which is unavailable; using the video ID instead")
	end
	return sha256_state
end

function fetch_sponsor_segments(youtube_id)
	local args = {"curl", "-L", "-s", "-G", "--data-urlencode", ("categories=%s"):format(utils.format_json(categories))}
	local url = options.server
	local use_hash = options.hash == "true" and have_sha256sum()

	if use_hash then
		local sha = mp.command_native{
			name = "subprocess",
			capture_stdout = true,
			playback_only = false,
			args = {"sha256sum"},
			stdin_data = youtube_id
		}
		local prefix = sha and sha.stdout and string.sub(sha.stdout, 1, 4) or ""
		if prefix ~= "" then
			url = ("%s/%s"):format(url, prefix)
		else
			use_hash = false
			mp.msg.warn("sponsorblock: could not hash the video ID; using the plain video ID instead")
		end
	end

	if not use_hash then
		table.insert(args, "--data-urlencode")
		table.insert(args, "videoID=" .. youtube_id)
	end
	table.insert(args, url)

	local sponsors = mp.command_native{
		name = "subprocess",
		capture_stdout = true,
		playback_only = false,
		args = args
	}
	if not sponsors or not sponsors.stdout or sponsors.stdout == "" then
		mp.msg.verbose("sponsorblock: no segments (empty API response)")
		return nil
	end

	local json = utils.parse_json(sponsors.stdout)
	if not is_array(json) then
		-- A 404 comes back as plain "Not Found" or {"error": ...}; that just
		-- means this video has no segments. Not worth a warning.
		mp.msg.verbose("sponsorblock: no segments for this video")
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

	local chapters = mp.get_property_native("chapter-list")
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
					table.insert(ranges, {["segment"] = {chapter.time, to}, ["category"] = category})
				end
			end
		end
	end

	if not have_sponsorblock_chapters then
		return nil
	end

	return ranges
end

function file_loaded()
	-- Reset per-file state; segments are rebuilt for the new file.
	mp.unobserve_property(skip_ads)
	ON = false
	last_skip = nil
	ranges = get_ranges_from_chapters() or fetch_ranges()

	if type(ranges) == 'table' and #ranges > 0 then
		ON = true
		mp.observe_property("time-pos", "native", skip_ads)
	end
end

function end_file()
	mp.unobserve_property(skip_ads)
	ranges = nil
	last_skip = nil
	ON = false
end

function toggle()
	if ON then
		mp.unobserve_property(skip_ads)
		mp.osd_message("[sponsorblock] off")
		ON = false
	else
		mp.observe_property("time-pos", "native", skip_ads)
		mp.osd_message("[sponsorblock] on")
		ON = true
	end
end

-- Registered once at script load, not per file.
mp.add_key_binding("b", "sponsorblock", toggle)
mp.register_event("file-loaded", file_loaded)
mp.register_event("end-file", end_file)
