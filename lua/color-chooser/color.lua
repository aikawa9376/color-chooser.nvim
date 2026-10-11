local M = {}

function M.clamp(value, low, high)
  return math.max(low or 0, math.min(high or 1, value))
end

local function round(value)
  return math.floor(value + 0.5 + 1e-9)
end

function M.hsv_to_rgb(h, s, v, a)
  h = (h % 360) / 60
  local c = v * s
  local x = c * (1 - math.abs(h % 2 - 1))
  local m = v - c
  local segments = { { c, x, 0 }, { x, c, 0 }, { 0, c, x }, { 0, x, c }, { x, 0, c }, { c, 0, x } }
  local rgb = segments[math.floor(h) + 1]
  return { r = rgb[1] + m, g = rgb[2] + m, b = rgb[3] + m, a = a or 1 }
end

function M.rgb_to_hsv(color)
  local r, g, b = color.r, color.g, color.b
  local maximum, minimum = math.max(r, g, b), math.min(r, g, b)
  local delta, h = maximum - minimum, 0
  if delta > 0 then
    if maximum == r then
      h = 60 * (((g - b) / delta) % 6)
    elseif maximum == g then
      h = 60 * ((b - r) / delta + 2)
    else
      h = 60 * ((r - g) / delta + 4)
    end
  end
  return h, maximum == 0 and 0 or delta / maximum, maximum
end

function M.hsl_to_rgb(h, s, l, a)
  local v = l + s * math.min(l, 1 - l)
  return M.hsv_to_rgb(h, v == 0 and 0 or 2 * (1 - l / v), v, a)
end

function M.rgb_to_hsl(color)
  local h, _, v = M.rgb_to_hsv(color)
  local minimum = math.min(color.r, color.g, color.b)
  local l, delta = (v + minimum) / 2, v - minimum
  local s = (l == 0 or l == 1) and 0 or delta / (1 - math.abs(2 * l - 1))
  return h, s, l
end

function M.hex(color, alpha, uppercase)
  local result = string.format("#%02x%02x%02x", round(color.r * 255), round(color.g * 255), round(color.b * 255))
  if alpha then
    result = result .. string.format("%02x", round((color.a or 1) * 255))
  end
  return uppercase and result:upper() or result
end

local function decimal(value, precision)
  return string.format("%." .. precision .. "f", value):gsub("0+$", ""):gsub("%.$", "")
end

local function numeric(token, scale, percent_only)
  local percentage = token:sub(-1) == "%"
  local raw = percentage and token:sub(1, -2) or token
  if not raw:match("^[+-]?%d*%.?%d+$") or (percent_only and not percentage) then
    return nil
  end
  return M.clamp(tonumber(raw) / (percentage and 100 or scale))
end

local function angle(token)
  local raw, unit = token:match("^([+-]?%d*%.?%d+)(%a*)$")
  local scales = { [""] = 1, deg = 1, grad = 0.9, rad = 180 / math.pi, turn = 360 }
  if not raw or not scales[unit] then
    return nil
  end
  return (tonumber(raw) * scales[unit]) % 360
end

-- Parse a whole literal. All channels are stored as floats in [0, 1].
function M.parse(text)
  text = text:match("^%s*(.-)%s*$")
  local digits = text:match("^#(%x+)$") or text:match("^0[xX](%x+)$")
  if digits then
    local n = #digits
    local prefix = text:sub(1, 1) == "#" and "#" or text:sub(1, 2)
    if (prefix ~= "#" and n ~= 6 and n ~= 8) or (n ~= 3 and n ~= 4 and n ~= 6 and n ~= 8) then
      return nil
    end
    local short = n <= 4
    local size = short and 1 or 2
    local function channel(index)
      local chunk = digits:sub(index * size + 1, (index + 1) * size)
      return tonumber(short and chunk .. chunk or chunk, 16) / 255
    end
    return { r = channel(0), g = channel(1), b = channel(2), a = (n == 4 or n == 8) and channel(3) or 1 }, {
      kind = "hex", alpha = n == 4 or n == 8, short = short, prefix = prefix,
      uppercase = digits:find("[A-F]") ~= nil and digits:find("[a-f]") == nil,
    }
  end

  local name, body = text:lower():match("^(%a+)%((.*)%)$")
  if name ~= "rgb" and name ~= "rgba" and name ~= "hsl" and name ~= "hsla" then
    return nil
  end
  local comma = body:find(",", 1, true) ~= nil
  local channels, alpha = {}, nil
  if comma then
    if body:find("/", 1, true) then
      return nil
    end
    for part in (body .. ","):gmatch("(.-),") do
      local token = part:match("^%s*(%S+)%s*$")
      if not token then
        return nil
      end
      channels[#channels + 1] = token
    end
    if #channels == 4 then
      alpha = table.remove(channels)
    end
  else
    local before, after = body:match("^(.-)/(.-)$")
    if before then
      alpha = after:match("^%s*(%S+)%s*$")
      if not alpha then
        return nil
      end
      body = before
    end
    for token in body:gmatch("%S+") do
      channels[#channels + 1] = token
    end
  end
  if #channels ~= 3 then
    return nil
  end
  local a = 1
  if alpha then
    a = numeric(alpha, 1)
  end
  if not a then
    return nil
  end
  local color
  if name:sub(1, 3) == "rgb" then
    local r, g, b = numeric(channels[1], 255), numeric(channels[2], 255), numeric(channels[3], 255)
    if not r or not g or not b then
      return nil
    end
    if comma and (channels[1]:find("%%") ~= nil) ~= (channels[2]:find("%%") ~= nil) then
      return nil
    end
    if comma and (channels[1]:find("%%") ~= nil) ~= (channels[3]:find("%%") ~= nil) then
      return nil
    end
    color = { r = r, g = g, b = b, a = a }
  else
    local h, s, l = angle(channels[1]), numeric(channels[2], 1, true), numeric(channels[3], 1, true)
    if not h or not s or not l then
      return nil
    end
    color = M.hsl_to_rgb(h, s, l, a)
  end
  return color, { kind = name:sub(1, 3), alpha = alpha ~= nil, comma = comma,
    percent = name:sub(1, 3) == "rgb" and channels[1]:sub(-1) == "%" }
end

function M.format(color, format)
  format = format or { kind = "hex" }
  local alpha = format.alpha or (color.a or 1) < 1
  if format.kind == "hex" then
    local text = M.hex(color, alpha, format.uppercase)
    if format.short then
      local digits, possible = text:sub(2), true
      for i = 1, #digits, 2 do
        if digits:sub(i, i) ~= digits:sub(i + 1, i + 1) then
          possible = false
        end
      end
      if possible then
        text = "#" .. digits:gsub("(%x)%x", "%1")
      end
    end
    return (format.prefix or "#") .. text:sub(2)
  end
  local channels
  if format.kind == "rgb" then
    channels = {}
    for _, key in ipairs({ "r", "g", "b" }) do
      channels[#channels + 1] = format.percent and (decimal(color[key] * 100, 2) .. "%") or tostring(round(color[key] * 255))
    end
  else
    local h, s, l = M.rgb_to_hsl(color)
    channels = { decimal(h, 2), decimal(s * 100, 2) .. "%", decimal(l * 100, 2) .. "%" }
  end
  local name = format.kind
  local body = table.concat(channels, format.comma and ", " or " ")
  if alpha then
    if format.comma then
      name = name .. "a"
    end
    body = body .. (format.comma and ", " or " / ") .. decimal(color.a or 1, 3)
  end
  return name .. "(" .. body .. ")"
end

-- Byte columns match Neovim's cursor and text APIs, including multibyte prefixes.
function M.find_at(line, column)
  local candidates = {}
  local function collect(pattern)
    local offset = 1
    while true do
      local first, last = line:find(pattern, offset)
      if not first then
        break
      end
      local before, after = line:sub(first - 1, first - 1), line:sub(last + 1, last + 1)
      if not before:match("[%w_#]") and not after:match("[%w_]") then
        local text = line:sub(first, last)
        local color, format = M.parse(text)
        if color then
          candidates[#candidates + 1] = { color = color, format = format, text = text, start_col = first - 1, end_col = last }
        end
      end
      offset = last + 1
    end
  end
  collect("#%x+")
  collect("0[xX]%x+")
  collect("[rR][gG][bB][aA]?%b()")
  collect("[hH][sS][lL][aA]?%b()")
  for _, candidate in ipairs(candidates) do
    if column >= candidate.start_col and column < candidate.end_col then
      return candidate
    end
  end
end

return M
