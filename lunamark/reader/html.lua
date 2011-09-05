-- (c) 2009-2011 John MacFarlane.  Released under MIT license.
-- See the file LICENSE in the source for details.

local htmlparser = require("lunamark.htmlparser")
local entities = require("lunamark.entities")

local M = {}

local function convert_entities(s)
  return s:gsub("&#[Xx](%x+);", entities.hex_entity):gsub("&#(%d+);", entities.dec_entity):gsub("&(%a+);", entities.char_entity)
end

local function lookup_attr(node, name)
  if node.attrs then
    for _,x in ipairs(node.attrs) do
      if x.name == name then
        return convert_entities(x.value or "")
      end
    end
  end
end

-- tags that aren't interpreted, but do need to be treated as block tags
local leavespace = { address = true, center = true, dir = true, div = true,
                     dl = true, form = true, menu = true, noframes = true,
                     frameset = true, table = true }

local function handle_nodes(writer, nodes, preserve_space)
  local output = {}
  local firstblock = true
  local function preblockspace()
    if firstblock then
      firstblock = false
    else
      table.insert(output, writer.interblocksep)
    end
  end
  local i = 1
  while nodes[i] do
    local node = nodes[i]
    if type(node) == "string" then -- text node
      local contents
      if preserve_space then
        contents = writer.string(convert_entities(node))
      else
        local s = convert_entities(node)
        contents = s:gsub("%s+", writer.space):gsub("%S+", writer.string)
      end
      table.insert(output, contents)
    elseif node.tag and node.child then -- tag with contents
      local tag = node.tag
      local function getcontents()
        return handle_nodes(writer, node.child,
              preserve_space or tag == "pre" or tag == "code")
      end
      if tag == "p" then
        preblockspace()
        table.insert(output, writer.paragraph(getcontents()))
      elseif tag == "blockquote" then
        preblockspace()
        table.insert(output, writer.blockquote(getcontents()))
      elseif tag == "li" then
        table.insert(output, getcontents())
      elseif tag == "ul" then
        preblockspace()
        local items = {}
        for _,x in ipairs(node.child) do
          if x.tag == "li" then
            table.insert(items, handle_nodes(writer, x.child, false))
          end
        end
        table.insert(output, writer.bulletlist(items))
      elseif tag == "ol" then
        preblockspace()
        local items = {}
        for _,x in ipairs(node.child) do
          if x.tag == "li" then
            table.insert(items, handle_nodes(writer, x.child, false))
          end
        end
        table.insert(output, writer.orderedlist(items))
      elseif tag == "pre" then
        preblockspace()
        table.insert(output, writer.verbatim(getcontents()))
      elseif tag:match("^h[123456]$") then
        local lev = tonumber(tag:sub(2,2))
        preblockspace()
        local bodynodes = {}
        while nodes[i+1] do
          local nd = nodes[i+1]
          if nd.tag and nd.tag:match("^h[123456]$") and
             tonumber(nd.tag:sub(2,2)) <= lev then
             break
          else
            table.insert(bodynodes,nd)
          end
          i = i + 1
        end
        local body = handle_nodes(writer, bodynodes, preserve_space)
        table.insert(output, writer.section(getcontents(), lev, body))
      elseif tag == "a" then
        local src = lookup_attr(node, "href") or ""
        local tit = lookup_attr(node, "title")
        table.insert(output, writer.link(getcontents(),src,tit))
      elseif tag == "em" or tag == "i" then
        table.insert(output, writer.emphasis(getcontents()))
      elseif tag == "strong" or tag == "b" then
        table.insert(output, writer.strong(getcontents()))
      elseif tag == "code" then
        table.insert(output, writer.code(getcontents()))
      elseif tag == "script" or tag == "style" then
        -- skip getcontents()
      elseif tag == "title" then
        writer.set_metadata("title", writer.string(getcontents()))
      else  --skip unknown tag
        if leavespace[tag] then
          preblockspace()
        end
        table.insert(output, getcontents())
      end
    elseif node.tag then  -- self-closing tag
      local tag = node.tag
      if tag == "hr" then
        preblockspace()
        table.insert(output, writer.hrule)
      elseif tag == "br" then
        table.insert(output, writer.linebreak)
      elseif tag == "img" then
        local alt = lookup_attr(node, "alt") or ""
        local src = lookup_attr(node, "src") or ""
        local tit = lookup_attr(node, "title")
        table.insert(output, writer.image(alt,src,tit))
      else
        -- skip
      end
    else -- comment or xmlheader
      -- skip
    end
    i = i + 1
  end
  return table.concat(output)
end

--- Create a new html parser.
function M.new(writer, options)

  return function(inp)
    local parser = htmlparser.new(inp)
    local parsed = parser:parse()
    return handle_nodes(writer, parsed), writer.get_metadata()
  end

end

return M
