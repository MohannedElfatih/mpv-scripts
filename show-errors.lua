local mp = require 'mp'
local msg = require 'mp.msg'
local opt = require 'mp.options'

local o = {
    --add a blacklist for error messages to not print to the OSD
    --each statement must be seperated by a '|' character. Do not leave
    --spaces around the | unless they are part of the blacklisted string
    --can be either the command prefix, a.k.a "ffmpeg"
    --or the error text, but not both.
    --Error text is all of the text after the "[prefix] " part of the message
    blacklist = "",

    --also show warning messages on the OSD
    --keep in mind that these can be quite wordy in comparison to errors
    warnings = false
}

opt.read_options(o, 'show_errors')

--splits the string into a table on the semicolons
local blacklist = {}
for str in string.gmatch(o.blacklist, "([^|]+)") do
    msg.verbose('adding "' .. str .. '" to blacklist')
    blacklist[str] = true
end

local ov = mp.create_osd_overlay("ass-events")

if o.warnings then
    mp.enable_messages('warn')
else
    mp.enable_messages('error')
end

mp.register_event('log-message', function(log)
    --the log messages seem to always end with a newline character and extra space
    if blacklist[log.text:sub(1, -3)] or blacklist[log.prefix] then return end
    local colour = ""

    if log.level == "error" then
        colour = "{\\c&H0000AA>&}"
    elseif log.level == "warn" then
        colour = "{\\c&H1AA3FF>&}"
    elseif log.level == "fatal" then
        colour = "{\\c&H1A75FF>&}"
    end

    message = colour .. "[" .. log.prefix .. "] " .. log.text
    ov.data = ov.data .. message
    ov:update()

    mp.add_timeout(4, function ()
        local endln = ov.data:find('\n') + 1
        ov.data = ov.data:sub(endln)
        ov:update()
    end)
end)