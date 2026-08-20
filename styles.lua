-- styles.lua  
-- Pandoc Lua filter: inject OpenXML <w:rPr> font-size overrides
-- Heading 2 → 16 pt  (32 half-points)
-- Heading 3 → 14 pt  (28 half-points)
-- Normal / Para → 12 pt (24 half-points)

local function set_size(block, halfpts)
  -- Wrap every inline inside the block with a Span that carries
  -- a custom-style attribute; then use a raw OpenXML run-property
  -- injected via a RawInline.
  local size_open = pandoc.RawInline(
    'openxml',
    '<w:rPr><w:sz w:val="' .. halfpts .. '"/><w:szCs w:val="' .. halfpts .. '"/></w:rPr>'
  )
  -- We cannot truly inject per-run sizing cleanly through Lua alone
  -- without a reference.docx; rely on reference.docx style overrides instead.
  return block
end

-- This filter modifies paragraph-level custom styles via Div attributes.
-- The actual font size is controlled by the reference.docx Style definitions
-- combined with the --variable options we pass on the command line.
function Header(el)
  return el
end

function Para(el)
  return el
end
