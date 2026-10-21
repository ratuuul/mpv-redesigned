--[[
lasthit.lua - double-click the window to reopen the last played media and
              resume it from the exact position.

WHAT IT DOES
  MPTN_LEFT_DBL (bound in input.conf) -> script-binding lasthit/play

  Looks up the most recent *real* media file that was played (mpv's own
  watch history, falling back to recentmenu's recent.json), finds its
  watch-later entry and loads the file with the saved `start` position.

  The idle background photo (scripts/bg.lua) is ignored, so the last real
  video is the one that gets reopened.
]]

local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

local function expand(path)
	local p = mp.command_native({ 'expand-path', path })
	return p and p:gsub('\\', '/') or path
end

-- Background photos live in ~~/cache/bg/ - they are never the "last media".
local function is_background(path, title)
	if not path then return true end
	local p = path:gsub('\\', '/'):lower()
	if p:find('/cache/bg/', 1, true) then return true end
	if p:find('/cache/bg_', 1, true) then return true end
	if title and tostring(title):lower() == 'background' then return true end
	return false
end

-- mpv's watch history is JSONL: one object per line, newest last.
-- It lives in the *state* dir (~~state/), not the config dir.
local function from_watch_history()
	local file = expand('~~state/watch_history.jsonl')
	local f = io.open(file, 'r')
	if not f then return nil end
	local last = nil
	for line in f:lines() do
		if line ~= '' then
			local ok, entry = pcall(utils.parse_json, line)
			if ok and type(entry) == 'table' then
				local path = entry.path
				if type(path) ~= 'string' then
					path = entry.name
					if type(path) ~= 'string' then path = nil end
				end
				if path and path ~= '' and not is_background(path, entry.title) then
					last = { path = path, name = entry.title or path }
				end
			elseif ok and type(entry) == 'string' and entry ~= '' and not is_background(entry) then
				last = { path = entry, name = entry }
			end
		end
	end
	f:close()
	return last
end

-- recentmenu keeps its own list in ~~/recent.json.
local function from_recent_json()
	local file = expand('~~/recent.json')
	local f = io.open(file, 'r')
	if not f then return nil end
	local content = f:read('*all')
	f:close()
	local ok, items = pcall(utils.parse_json, content)
	if not ok or type(items) ~= 'table' then return nil end
	local last = nil
	for _, item in ipairs(items) do
		if type(item) == 'table' and type(item.value) == 'table' then
			local path = item.value[2]
			if type(path) == 'string' and path ~= '' and not is_background(path) then
				last = { path = path, name = item.title or path }
			end
		end
	end
	return last
end

local function last_played()
	return from_watch_history() or from_recent_json()
end

-- mpv escapes some characters in watch-later files; compare both ways.
local function norm(s)
	if not s then return '' end
	s = s:gsub('\\', '/')
	s = s:gsub('//+', '/')
	return s:lower()
end

local function same_path(a, b)
	if not a or not b then return false end
	local x, y = norm(a), norm(b)
	if x == y then return true end
	-- Windows paths: mpv may store the URI-ish or the plain path.
	return x:gsub('^file://', '') == y:gsub('^file://', '')
end

-- Find the saved position for a path in the watch-later dir (~~state/).
local function saved_position(path)
	local dir = expand('~~state/watch_later/')
	local files = utils.readdir(dir, 'files')
	if not files then return nil end
	for _, name in ipairs(files) do
		local f = io.open(dir .. name, 'r')
		if f then
			local content = f:read('*all')
			f:close()
			local fn, start
			for line in content:gmatch('[^\r\n]+') do
				local key, value = line:match('^%s*([%w_%-]+)=(.*)$')
				if key == 'filename' then fn = value end
				if key == 'start' then start = tonumber(value) end
			end
			if fn and start and same_path(fn, path) then
				return start
			end
		end
	end
	return nil
end

local function play_last()
	-- A real media file is already loaded: do not interrupt playback.
	local current = mp.get_property('path')
	local current_title = mp.get_property('media-title')
	if current and not is_background(current, current_title) and
		mp.get_property_native('idle-active') == false then
		mp.osd_message('Already playing', 1.5)
		return
	end

	local entry = last_played()
	if not entry then
		mp.osd_message('No previous media', 2)
		return
	end

	-- mpv's own resume-playback already restores the position; the explicit
	-- start= is a fallback for entries whose watch-later file was written
	-- before `filename=` was added to it.
	local start = saved_position(entry.path)
	local opts = { 'replace' }
	if start and start > 0 then
		opts[#opts + 1] = 'start=' .. string.format('%.3f', start)
	end

	mp.commandv('loadfile', entry.path, unpack(opts))
	msg.info('reopened ' .. entry.path .. (start and (' @ ' .. start) or ''))
end

mp.add_key_binding(nil, 'play', play_last)
mp.register_script_message('play', play_last)
