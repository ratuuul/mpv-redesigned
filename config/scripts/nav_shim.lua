-- =============================================================================
--  nav-shim - skin-aware navigation helper
--
--  Purpose: one keymap for both skins.
--
--  Liquid Glass (the uosc fork) renders beautiful centred macOS-style
--  overlays for seek / volume / scroll, but its messages only exist when
--  that skin is loaded. ModernZ has its own, different feedback.
--
--  This shim talks to whichever skin is present:
--    * Liquid Glass detected  -> forward to its lg-* messages
--    * otherwise              -> perform the action natively and let the
--                                active skin render its own feedback
--
--  Detection is explicit, not guessed: the Liquid Glass skin sets
--  user-data/skin/liquidglass = true when it loads.
-- =============================================================================

local msg = require 'mp.msg'

-- --- skin detection --------------------------------------------------------
-- The Liquid Glass skin sets this on load. We also probe once at startup so
-- the shim is correct even if the skin is reloaded later.
local function liquid_glass_loaded()
    return mp.get_property_native('user-data/skin/liquidglass') == true
end

local function forward_to_uosc(message, ...)
    -- script-message-to returns nil + error when the target script or the
    -- message does not exist, so we can fail over safely.
    local args = { 'script-message-to', 'uosc', message }
    for _, a in ipairs({ ... }) do
        args[#args + 1] = tostring(a)
    end
    local ok = mp.commandv(unpack(args))
    return ok ~= nil
end

-- =============================================================================
--  Actions
-- =============================================================================

-- --- seek ------------------------------------------------------------------
local function do_seek(seconds)
    if liquid_glass_loaded() and forward_to_uosc('lg-seek', seconds) then
        return
    end
    -- `seek` with a signed relative value; exact seeking keeps frame accuracy.
    mp.commandv('seek', tostring(seconds), 'exact')
end

-- --- scroll ----------------------------------------------------------------
-- The wheel scrolls the timeline (not the volume) on both skins.
local function do_scroll(direction)
    if liquid_glass_loaded() and
       forward_to_uosc(direction > 0 and 'lg-scroll-up' or 'lg-scroll-down') then
        return
    end
    do_seek(direction * 5)
end

-- --- volume ----------------------------------------------------------------
local function do_volume(delta)
    if liquid_glass_loaded() and forward_to_uosc('lg-volume', delta) then
        return
    end
    mp.commandv('add', 'volume', tostring(delta))
end

-- --- percent seek ----------------------------------------------------------
local function do_seek_percent(percent)
    if liquid_glass_loaded() and forward_to_uosc('lg-seek-percent', percent) then
        return
    end
    local duration = mp.get_property_number('duration')
    if not duration or duration <= 0 then return end
    local target = duration * (percent / 100)
    mp.commandv('seek', tostring(target), 'absolute')
    -- Show the resulting time, since ModernZ's OSC shows the bar, not a number.
    mp.osd_message(string.format('%d%%  %s', percent,
        mp.get_property_native('time-pos') and
        mp.utils.format_time(mp.get_property_number('time-pos')) or ''), 1.2)
end

-- --- speed -----------------------------------------------------------------
local function do_speed(direction)
    if liquid_glass_loaded() and forward_to_uosc('lg-speed', direction) then
        return
    end
    mp.commandv('multiply', 'speed', direction > 0 and '1.1' or '0.9091')
end

-- =============================================================================
--  Message interface (called from input.conf)
-- =============================================================================

mp.register_script_message('nav-seek', function(amount)
    do_seek(tonumber(amount) or 0)
end)

mp.register_script_message('nav-scroll-up', function()
    do_scroll(1)
end)

mp.register_script_message('nav-scroll-down', function()
    do_scroll(-1)
end)

mp.register_script_message('nav-volume', function(delta)
    do_volume(tonumber(delta) or 0)
end)

mp.register_script_message('nav-seek-percent', function(percent)
    do_seek_percent(tonumber(percent) or 0)
end)

mp.register_script_message('nav-speed', function(direction)
    do_speed(tonumber(direction) or 1)
end)

mp.register_script_message('nav-speed-reset', function()
    mp.commandv('set', 'speed', '1')
end)

-- Re-check when a new file starts, in case the skin reloaded.
mp.observe_property('user-data/skin/liquidglass', 'native', function(_, value)
    msg.debug(string.format('nav-shim: skin = %s',
        value == true and 'Liquid Glass' or 'default/ModernZ'))
end)

msg.info('nav-shim loaded')
