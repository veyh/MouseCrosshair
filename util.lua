local _, ns = ...

local strfind = _G.strfind
local tinsert = _G.tinsert
local strsub = _G.strsub

local util = {}
ns.util = util

function util.Pack(...)
  return { n = select("#", ...), ... }
end

function util.Unpack(args)
  return unpack(args, 1, args.n or #args)
end

function util.Deindent(source)
  local lines = {}
  local sourceLines = util.StrSplit("\n", source)
  local minIndent = util.getMinIndent(sourceLines)

  for
    index = 1,
    #sourceLines - (util.isEmptyString(sourceLines[#sourceLines]) and 1 or 0)
  do
    local line = sourceLines[index]

    table.insert(lines, line:sub(
      math.min(minIndent, util.getLineIndent(line)) + 1
    ))
  end

  return (
    table.concat(lines, "\n"):gsub("\\\n", "")
  )
end

function util.getMinIndent(sourceLines)
  local minIndent

  for index = 1, #sourceLines do
    local line = sourceLines[index]

    if not util.isEmptyString(line) then
      local indent = util.getLineIndent(line)

      if not minIndent
      or indent < minIndent then
        minIndent = indent
      end
    end
  end

  return minIndent
end

function util.isEmptyString(s)
  return s:match("^%s*$")
end

function util.getLineIndent(line)
  return (line:find("%S") or 1) - 1
end

function util.StrSplit(delimiter, text)
  local list = {}
  local pos = 1

  if strfind("", delimiter, 1) then -- this would result in endless loops
    error("delimiter matches empty string!")
  end

  while true do
    local first, last = strfind(text, delimiter, pos)

    if first then -- found?
      tinsert(list, strsub(text, pos, first - 1))
      pos = last + 1

    else
      tinsert(list, strsub(text, pos))
      break
    end
  end

  return list
end
