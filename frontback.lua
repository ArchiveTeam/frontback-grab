dofile("urlcode.lua")
dofile("table_show.lua")

local url_count = 0
local tries = 0
local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')

local downloaded = {}
local addedtolist = {}

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

line_num = function(linenum, filename)
  local num = 0
  for line in io.lines(filename) do
    num = num + 1
    if num == linenum then
      return line
    end
  end
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]
  
  if downloaded[string.match(url, "https?://(.+)")] == true or addedtolist[string.match(url, "https?://(.+)")] == true then
    return false
  end
  
  if item_type == "image" and downloaded[string.match(url, "https?://(.+)")] ~= true and addedtolist[string.match(url, "https?://(.+)")] ~= true then
    if html == 0 or (string.match(url, "[^A-Za-z]"..item_type) and string.match(url, "frontback%.me") and not string.match(url, "[^A-Za-z]"..item_value.."[A-Za-z]")) then
      addedtolist[string.match(url, "https?://(.+)")] = true
      return true
    else
      return false
  else
    return false
  end
end


wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
    
  local function check(url)
    if downloaded[string.match(url, "https?://(.+)")] ~= true and addedtolist[string.match(url, "https?://(.+)")] ~= true and string.match(url, "[^A-Za-z]"..item_type) and string.match(url, "frontback%.me") and not string.match(url, "[^A-Za-z]"..item_value.."[A-Za-z]") then
      if string.match(url, "&amp;") then
        table.insert(urls, { url=string.gsub(url, "&amp;", "&") })
        addedtolist[string.match(string.gsub(url, "&amp;", "&"), "https?://(.+)")] = true
        addedtolist[string.match(url, "https?://(.+)")] = true
      else
        table.insert(urls, { url=url })
        addedtolist[string.match(url, "https?://(.+)")] = true
      end
    end
  end
  
  if item_type == "image" then
    if string.match(url, "[^A-Za-z0-9]"..item_value) and string.match(url, "frontback%.me") and not string.match(url, "[^A-Za-z0-9]"..item_value..".") then
      html = read_file(file)
      for newurl in string.gmatch(html, '"(https?://[^"]+)"') do
        check(newurl)
      end
      for newurl in string.gmatch(html, "'(https?://[^']+)'") do
        check(newurl)
      end
      if string.match(url, "%?") then
        check(string.match(url, "(https?://[^%?]+)%?"))
      end
      for newurl in string.gmatch(html, '("/[^"]+)"') do
        if string.match(newurl, '"//') then
          check(string.gsub(newurl, '"//', 'http://'))
        else
          check(string.match(url, "(https?://[^/]+)/")..string.match(newurl, '"(.+)'))
        end
      end
    end
  end
  
  return urls
end
  

wget.callbacks.httploop_result = function(url, err, http_stat)
  -- NEW for 2014: Slightly more verbose messages because people keep
  -- complaining that it's not moving or not working
  local status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. ".  \n")
  io.stdout:flush()

  if item_type == "forum" or item_type == "forumlang" then
    return wget.actions.ABORT
  end
  
  if (status_code >= 200 and status_code <= 399) or status_code == 403 then
    if string.match(url.url, "https://") then
      local newurl = string.gsub(url.url, "https://", "http://")
      downloaded[string.match(newurl, "https?://(.+)")] = true
    else
      downloaded[string.match(url.url, "https?://(.+)")] = true
    end
  end

  if status_code == 302 or status_code == 301 then
    os.execute("python check302.py '"..url["url"].."'")
    if io.open("302file", "r") == nil then
      if string.match(url["url"], item_value) and string.match(url["host"], "frontback%.me") then
        io.stdout:write("Something went wrong!! ABORTING  \n")
        io.stdout:flush()
        return wget.actions.ABORT
      end
    end
    local redirfile = io.open("302file", "r")
    local fullfile = redirfile:read("*all")
    local numlinks = 0
    for newurl in string.gmatch(fullfile, "https?://") do
      numlinks = numlinks + 1
    end
    local foundurl = line_num(2, "302file")
    if numlinks > 1 then
      io.stdout:write("Found "..foundurl.." after redirect")
      io.stdout:flush()
      if downloaded[string.match(foundurl, "https?://(.+)")] == true or addedtolist[string.match(foundurl, "https?://(.+)")] == true then
        io.stdout:write(", this url has already been downloaded or added to the list to be downloaded, so it is skipped.  \n")
        io.stdout:flush()
        redirfile:close()
        os.remove("302file")
        return wget.actions.EXIT
      elseif not string.match(foundurl, "https?://") then
        if string.match(url["url"], item_value) and string.match(url["host"], "frontback%.me") then
          io.stdout:write("Something went wrong!! ABORTING  \n")
          io.stdout:flush()
          return wget.actions.ABORT
        end
      end
      redirfile:close()
      os.remove("302file")
      io.stdout:write(".  \n")
      io.stdout:flush()
    end
  end
  
  if status_code >= 500 or
    (status_code >= 400 and status_code ~= 404 and status_code ~= 403) then
    io.stdout:write("\nServer returned "..http_stat.statcode..". Sleeping.\n")
    io.stdout:flush()

    os.execute("sleep 1")

    tries = tries + 1

    if tries >= 4 and string.match(url["url"], item_value) and string.match(url["host"], "frontback%.me") then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      return wget.actions.ABORT
    elseif tries >= 4 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      return wget.actions.EXIT
    else
      return wget.actions.CONTINUE
    end
  elseif status_code == 0 then
    io.stdout:write("\nServer returned "..http_stat.statcode..". Sleeping.\n")
    io.stdout:flush()

    os.execute("sleep 10")
    
    tries = tries + 1

    if tries >= 4 and string.match(url["url"], item_value) and string.match(url["host"], "frontback%.me") then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      return wget.actions.ABORT
    elseif tries >= 4 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      return wget.actions.EXIT
    else
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  -- We're okay; sleep a bit (if we have to) and continue
  -- local sleep_time = 0.1 * (math.random(75, 1000) / 100.0)
  local sleep_time = 0

  --  if string.match(url["host"], "cdn") or string.match(url["host"], "media") then
  --    -- We should be able to go fast on images since that's what a web browser does
  --    sleep_time = 0
  --  end

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end
