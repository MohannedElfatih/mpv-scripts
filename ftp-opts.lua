--[[
    This script dynamically changes some settings at runtime while playing files over the ftp protocol

    Settings currently changed:

        - converts filepaths taken directly from a browser into a string format readable by mpv
            -e.g. "ftp://test%20ing" would become "ftp://test ing"

        - detects when ftp subtitle files are incorrrectly loaded and attempts to re-add them using the corrected filepath

        - if a directory is loaded it attempts to open a playlist file inside it (default is playlist.pls)
        
        - ordered chapters are loaded from a playlist file in the source directory (default is playlist.pls)
]]--

local opt = require 'mp.options'
local msg = require 'mp.msg'

--add options using script-opts=ftpopts-option=value
local o = {
    directory_playlist = 'playlist.pls',
    ordered_chapter_playlist = 'playlist.pls',

    --if true the script will always check warning messages to see if one is about an ftp sub file
    --if false the script will only keep track of warning messages when already playing an ftp file
    --essesntially if this is false you can't drag an ftp sub file onto a non ftp video stream
    always_check_subs = true
}

opt.read_options(o, 'ftpopts')

local originalOpts = {
    ordered_chapters = ""
}
local ftp = false
local path

--decodes a URL address
--this piece of code was taken from: https://stackoverflow.com/questions/20405985/lua-decodeuri-luvit/20406960#20406960
local decodeURI
do
    local char, gsub, tonumber = string.char, string.gsub, tonumber
    local function _(hex) return char(tonumber(hex, 16)) end

    function decodeURI(s)
        msg.debug('decoding string: ' .. s)
        s = gsub(s, '%%(%x%x)', _)
        msg.debug('returning string: ' .. s)
        return s
    end
end

--runs all of the custom operations for ftp files
function setFTPOpts()
    msg.info('FTP protocol detected - modifying settings')

    --converts the path into a valid string
    path = path:gsub([[\]],[[/]])
    path = decodeURI(path)

    local directory = path:sub(1, path:find("/[^/]*$"))
    local filename = path:sub(path:find("/[^/]*$") + 1)

    --sets ordered chapters to use a playlist file inside the directory
    mp.set_property('ordered-chapters-files', directory .. '/' .. o.ordered_chapter_playlist)

    --if there is no period in the filename then the file is actually a directory
    if not filename:find('%.') then
        msg.info('directory loaded - attempting to load playlist file')
        path = path .. "/" .. o.directory_playlist
    end

    --reloads the file, replacing the old one
    --does not run if decodeURI did not change any characters in the address
    if path ~= mp.get_property('path') then
        msg.info('attempting to reload file with corrected path')
        local pos = mp.get_property_number('playlist-pos')
        local endPlaylist = mp.get_property_number('playlist-count', 0)
        mp.commandv('loadfile', path, 'append')
        mp.commandv('playlist-move', endPlaylist, pos+1)
        mp.commandv('playlist-remove', pos)
    end
end

--reverts options to before the ftp protocol was used
function revertOpts()
    msg.info('reverting settings to default')
    mp.set_property('ordered-chapters-files', originalOpts.ordered_chapters)
end

--saves the original options to revert when no-longer playing an ftp file
function saveOpts()
    msg.verbose('saving original option values')
    originalOpts.ordered_chapters = mp.get_property('ordered-chapters-files')
end

--stores the previous sub so that we can detect infinite file loops caused by a
--completely invalid URL
local prevSub

--converts the URL of an errored subtitle and tries adding it again
function addSubtitle(sub)
    sub = decodeURI(sub)

    --if this sub was the same as the prev, then cancel the function
    --otherwise this would cause an infinite loop
    --this is different behaviour from mpv default since you can't add the same file twice in a row
    --but I don't know of any reason why one would do that, so I'm leaving it like this
    if (sub == prevSub) then
        msg.verbose('revised sub file was still not valid - cancelling event loop')
        return
    end
    msg.info('attempting to add revised file address')
    mp.commandv('sub-add', sub)
    prevSub = sub
end

--only passes the warning if it matches the desired format
function parseMessage(event)
    if (not ftp) and (not o.always_check_subs) then return end

    local error = event.text
    if not error:find("Can not open external file ") then return end

    --isolating the file that was added
    sub = error:sub(28, -3)
    if sub:sub(1, 3) ~= "ftp" then return end
    addSubtitle(sub)
end

--tests if the file being opened uses the ftp protocol
function testFTP()
    --reloading a file with corrected addresses causes this function to be rerun.
    --this check prevents the function from being run twice for each file
    if path == mp.get_property('path') then
        msg.verbose('skipping ftp configuration because script reloaded same file')
        return
    end

    path = mp.get_property('path')

    msg.verbose('checking for ftp protocol')
    local protocol = path:sub(1, 3)

    if (not ftp) and protocol == 'ftp' then
        saveOpts()
    end

    if protocol == "ftp" then
        ftp = true
        setFTPOpts()
        return
    elseif ftp then
        revertOpts()
    end
    ftp = false
end

--scans warning messages to tell if a subtitle track was incorrectly added
mp.enable_messages('warn')
mp.register_event('log-message', parseMessage)

mp.register_event('start-file', testFTP)