--[[
    pip.lua - picture-in-picture / always-on-top mini player

    Alt+p            toggle the mini player        (also: script-binding pip/toggle)

    Entering PiP:
      * leaves fullscreen / maximised state first
      * remembers ontop, border, geometry (incl. position when mpv knows it),
        the live window size, fullscreen/maximised and the skin's own
        autofit-smaller floor
      * goes borderless + always-on-top and shrinks to a fixed size
        (portrait videos get a portrait window) anchored to the bottom-right
        corner of the monitor's *work area* - i.e. above the taskbar.

    Leaving PiP restores every remembered value exactly, so repeated toggles
    are loss-free.

    Geometry notes (verified on Windows 10, mpv 0.41, 1920x1200 @125%):
      * `geometry=WxH+X+Y` with negative X/Y measures from the right/bottom
        edge of the *work area* (GetMonitorInfo rcWork), not the raw screen,
        so the taskbar is excluded automatically and no manual taskbar
        subtraction is needed.
      * `+50%+50%` centres the window in the work area.
      * The liquid-glass skin clamps small windows up to its own minimum
        (760x320) whenever `osd-width` changes. We re-assert our size when
        that happens (see enforce_size) without moving the window.
]]

local mp = require 'mp'
local msg = require 'mp.msg'
local opt = require 'mp.options'

local options = {
    -- Width/height of the mini player
    pip_width = 480,
    pip_height = 270,
    -- Margin from the screen edge, px
    pip_margin = 24,
}
opt.read_options(options, 'pip')

local function sane_number(value, fallback, minimum)
    local n = tonumber(value)
    if not n or n ~= n then return fallback end
    return math.max(minimum, math.floor(n))
end

local BASE_W = sane_number(options.pip_width, 480, 120)
local BASE_H = sane_number(options.pip_height, 270, 120)
local MARGIN = sane_number(options.pip_margin, 24, 0)

-- "normal" or "pip". Kept in this script only, so a new mpv process always
-- starts clean (no stale saved state can leak across sessions).
local mode = "normal"
local saved = nil
local busy = false
local busy_token = 0
-- How many times we are willing to correct the size in one PiP session.
-- The skin clamps us back once per osd-width change; a small budget is
-- enough and guarantees we can never end up in an endless resize loop.
local enforce_budget = 0
local ENFORCE_MAX = 24

-- ------------------------------------------------------------------ helpers --
local function num(name, fallback)
    local value = mp.get_property_number(name)
    if value == nil then return fallback end
    return value
end

local function flag(name)
    return mp.get_property_native(name) == true
end

local function target_dims()
    local aspect = num("video-params/aspect", 0)
    local portrait
    if aspect > 0 then
        portrait = aspect < 1
    else
        local w = num("video-params/w", 0)
        local h = num("video-params/h", 0)
        portrait = w > 0 and h > 0 and h > w
    end
    local short = math.min(BASE_W, BASE_H)
    local long = math.max(BASE_W, BASE_H)
    if portrait then return short, long end
    return long, short
end

local function pip_geometry(w, h)
    return string.format("%dx%d-%d-%d", w, h, MARGIN, MARGIN)
end

local function snapshot()
    return string.format(
        "ontop=%s border=%s geometry=%q fullscreen=%s maximized=%s " ..
        "osd=%sx%s autofit-smaller=%q",
        tostring(mp.get_property("ontop")),
        tostring(mp.get_property("border")),
        tostring(mp.get_property("geometry")),
        tostring(mp.get_property("fullscreen")),
        tostring(mp.get_property("window-maximized")),
        tostring(mp.get_property("osd-width")),
        tostring(mp.get_property("osd-height")),
        tostring(mp.get_property("autofit-smaller")))
end

local function log(why)
    msg.warn(string.format("PIP %-12s mode=%s %s", why, mode, snapshot()))
end

local function capture_state()
    return {
        ontop = flag("ontop"),
        border = flag("border"),
        -- "" when the user never set --geometry (e.g. the window was simply
        -- dragged). In that case the option is restored as "" and the size
        -- is restored separately.
        geometry = mp.get_property("geometry") or "",
        fullscreen = flag("fullscreen"),
        maximized = flag("window-maximized"),
        autofit_smaller = mp.get_property("autofit-smaller") or "",
        width = num("osd-width", 0),
        height = num("osd-height", 0),
    }
end

-- ------------------------------------------------------------- PiP entering --
local function apply_pip()
    local w, h = target_dims()
    -- border first: removing the frame changes the client rect, and the
    -- geometry below is applied to the final, frameless window.
    mp.set_property("border", "no")
    mp.set_property("ontop", "yes")
    -- Override the skin's own minimum (760x320) for the lifetime of the PiP
    -- session, so loading another file cannot pop the mini player back open.
    mp.set_property("autofit-smaller", string.format("%dx%d", w, h))
    mp.set_property("geometry", pip_geometry(w, h))
    mode = "pip"
    enforce_budget = ENFORCE_MAX
    busy = false
    mp.set_property_native("user-data/pip/active", true)
    log("entered")
end

local function enter()
    busy = true
    busy_token = busy_token + 1
    local token = busy_token

    saved = capture_state()
    log("enter-saved")

    local was_fullscreen = saved.fullscreen
    local was_maximized = saved.maximized
    if was_fullscreen then mp.set_property("fullscreen", "no") end
    if was_maximized then mp.set_property("window-maximized", "no") end

    -- Leaving fullscreen/maximising is asynchronous on Windows; applying
    -- geometry too early gets swallowed by the mode change.
    local delay = (was_fullscreen or was_maximized) and 0.35 or 0.03
    mp.add_timeout(delay, function()
        if busy_token ~= token then return end
        apply_pip()
    end)
end

-- ------------------------------------------------------------- PiP leaving --
local function restore()
    busy = true
    busy_token = busy_token + 1
    local token = busy_token
    local st = saved or {}
    local geometry = st.geometry or ""

    -- Restore size *and* position. A remembered geometry may be size-only
    -- ("1280x720"), position-only ("-24-24" / "0x0-24-24"), or both. The
    -- size must always be restored, because the mini player overwrote it.
    local gw, gh = geometry:match("^%s*(%d+)x(%d+)")
    local rest = geometry:match("^%s*%d+x%d+(.*)$") or geometry
    local w = tonumber(gw) or 0
    local h = tonumber(gh) or 0
    if w <= 0 or h <= 0 then
        w = math.floor(st.width or 0)
        h = math.floor(st.height or 0)
    end

    if w > 0 and h > 0 then
        local pos = rest or ""
        if pos == "" and geometry == "" then
            -- mpv never knew an explicit geometry (the user had dragged the
            -- window): centre it, which is where mpv puts a fresh window.
            pos = "+50%+50%"
        end
        mp.set_property("geometry", string.format("%dx%d%s", w, h, pos))
    else
        mp.set_property("geometry", geometry)
    end

    mp.set_property("ontop", st.ontop and "yes" or "no")
    mp.set_property("border", st.border and "yes" or "no")
    mp.set_property("autofit-smaller", st.autofit_smaller or "")

    if st.maximized then
        -- maximise/fullscreen last, and only after the restored geometry has
        -- been applied: a geometry change while fullscreen makes mpv leave
        -- fullscreen again on Windows.
        mp.add_timeout(0.30, function()
            if token == busy_token and mode == "normal" then
                mp.set_property("window-maximized", "yes")
            end
        end)
    end
    if st.fullscreen then
        mp.add_timeout(0.40, function()
            if token == busy_token and mode == "normal" then
                mp.set_property("fullscreen", "yes")
            end
        end)
    end

    mode = "normal"
    saved = nil
    busy = false
    mp.set_property_native("user-data/pip/active", false)
    log("left")

    -- If the window had no explicit geometry, the option is restored to ""
    -- (bit-identical to before) only after the centring move has been applied:
    -- clearing it in the same tick would cancel the pending position.
    -- While fullscreen/maximised we must leave the geometry in place: writing
    -- `geometry` in fullscreen makes mpv drop out of fullscreen on Windows.
    if geometry == "" and not st.fullscreen and not st.maximized then
        mp.add_timeout(0.25, function()
            if token == busy_token and mode == "normal" then
                mp.set_property("geometry", "")
            end
        end)
    end

    -- Snapshot once everything (incl. delayed restores) has settled.
    mp.add_timeout(0.60, function()
        if token == busy_token and mode == "normal" then log("left-final") end
    end)
end

-- The active skin (liquid-glass) enforces a controls-safe minimum window size
-- by watching osd-width/osd-height and rewriting `geometry`. Keep our size by
-- re-asserting a size-only geometry: that preserves wherever the user dragged
-- the mini player to. The skin has a 0.2 s cooldown between its clamps, so one
-- immediate correction is enough and the loop settles.
local function enforce_size()
    if mode ~= "pip" or busy then return end
    if flag("fullscreen") or flag("window-maximized") then return end
    if enforce_budget <= 0 then return end

    local w, h = target_dims()
    local cw = num("osd-width", 0)
    local ch = num("osd-height", 0)
    if cw <= 0 or ch <= 0 then return end
    if math.abs(cw - w) <= 2 and math.abs(ch - h) <= 2 then return end

    enforce_budget = enforce_budget - 1
    if enforce_budget == 0 then
        msg.warn("PIP size enforcement budget exhausted; leaving window as-is")
        return
    end
    mp.set_property("geometry", string.format("%dx%d", w, h))
end

mp.observe_property("osd-width", "number", enforce_size)
mp.observe_property("osd-height", "number", enforce_size)

-- ------------------------------------------------------------------- toggle --
local function toggle()
    if busy then
        msg.verbose("pip: toggle ignored, transition in progress")
        return
    end
    if mode == "pip" then
        restore()
    else
        enter()
    end
end

mp.add_key_binding("Alt+p", "toggle", toggle)
