-- ========================================================================================
-- DAAP | In-Session Manifest Utility (REAPER Dock Panel)
-- Version: 0.2.0
-- Purpose:
--   Display-only "pre-prep prep" manifest inside the session BEFORE export/render:
--     - Track inventory
--     - FX chains per track + parameter snapshots
--     - Routing topology (sends/receives/hardware outs)
-- Notes:
--   - Requires ReaImGui (install via ReaPack).
--   - Uses cached snapshot to avoid per-frame API thrash. Hit "Refresh Snapshot" to rescan.
--   - Export-to-file is intentionally deferred; display-only for this version.
-- ========================================================================================

-- ==============================
-- Safety: ReaImGui presence check
-- ==============================
if not reaper.ImGui_CreateContext then
  reaper.MB(
    "ReaImGui is not available.\n\nInstall it via:\nExtensions > ReaPack > Browse packages... > search 'ReaImGui'\n",
    "DAAP In-Session Manifest Utility",
    0
  )
  return
end

-- ==============================
-- UI Constants
-- ==============================
local UI_TITLE = "DAAP | In-Session Manifest Utility v0.2.0"
local ctx = reaper.ImGui_CreateContext(UI_TITLE)

-- ==============================
-- User Options (Display-Only)
-- ==============================
local OPT_INCLUDE_MASTER          = true
local OPT_SHOW_FX_PARAMS          = true
local OPT_SHOW_ONLY_ENABLED_FX    = false
local OPT_MAX_PARAMS_PER_FX       = 64     -- safety cap for UI sanity
local OPT_MAX_TRACKS_RENDERED     = 2048   -- safety cap
local OPT_MAX_SENDS_PER_TRACK     = 256    -- safety cap
local OPT_PAPER_STYLE             = true   -- "paper manifest" palette

-- ==============================
-- Internal Cache (Snapshot)
-- ==============================
local SNAP = {
  generated_at = 0.0,
  project_name = "",
  project_path = "",
  track_count = 0,
  tracks = {},        -- array of track manifests
  master = nil,       -- master manifest
  plugins_index = {}, -- deduped plugin inventory across project
  analytics = nil
}

-- ==============================
-- Helpers
-- ==============================
local function now_seconds()
  return reaper.time_precise()
end

local function safe_str(s)
  if not s or s == "" then return "(unnamed)" end
  return s
end

local function normalize_fx_name(name)
  name = safe_str(name)
  -- Basic cleanup to reduce duplicates caused by prefixes / spacing.
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  -- Optional: strip common container wrappers if they clutter your list (safe to adjust later)
  -- name = name:gsub("^VST3:%s*", ""):gsub("^VST:%s*", ""):gsub("^AU:%s*", ""):gsub("^JS:%s*", "")
  return name
end

local function classify_fx_status(fx_name, enabled, offline, ident_ok, fxname_ok)
  local n = string.lower(safe_str(fx_name))

  -- Heuristic indicators REAPER commonly uses for missing/unavailable FX
  local looks_missing =
      n:find("missing", 1, true) or
      n:find("unavailable", 1, true) or
      n:find("not found", 1, true) or
      n:find("failed", 1, true) or
      n:find("could not", 1, true)

  -- New: “unavailable” if REAPER can’t resolve a real FX identity/name
  if (ident_ok == false) or (fxname_ok == false) or looks_missing then
    return "unavailable"
  end

  -- Offline could also be user-forced offline (still important)
  if offline then
    return "offline"
  end

  -- Bypassed/inactive
  if not enabled then
    return "bypassed"
  end

  return "active"
end

local function parse_vendor_from_fx_name(fx_name)
  -- Common patterns:
  --   "VST3: Pro-Q 3 (FabFilter)"
  --   "ReaEQ (Cockos)"
  --   "FabFilter Pro-Q 3" (no vendor)
  local s = safe_str(fx_name)

  -- Vendor in trailing parentheses
  local vendor = s:match("%(([^%)]+)%)%s*$")
  if vendor and vendor ~= "" then return vendor end

  -- Sometimes "VST3: Vendor: Plugin" (rare)
  local maybe = s:match("^[^:]+:%s*([^:]+):%s*.+$")
  if maybe and maybe ~= "" then return maybe end

  return "Unknown"
end

local function classify_fx_type(fx_name)
  local n = string.lower(safe_str(fx_name))

  -- Order matters: more specific first
  if n:find("dynamic eq", 1, true) or n:find("dyn eq", 1, true) then return "Dynamic EQ" end
  if n:find("multiband", 1, true) and
     (n:find("compressor", 1, true) or n:find("compression", 1, true) or n:find("compress", 1, true) or
     n:match("%f[%a]comp%f[%A]")) then
    return "Multiband Comp"
  end

  -- Compressor / Dynamics
  if n:find("compressor", 1, true) or n:find("compression", 1, true) or n:find("compress", 1, true) or
     n:find("limiting amp", 1, true) or n:match("%f[%a]comp%f[%A]") then
    return "Compressor"
  end

  if n:find("equal", 1, true) or n:find(" eq", 1, true) or n:find("eq ", 1, true) then return "EQ" end
  if n:find("limiter", 1, true) or n:find("brickwall", 1, true) then return "Limiter" end
  if n:find("gate", 1, true) or n:find("expander", 1, true) then return "Gate/Expander" end
  if n:find("reverb", 1, true) or n:find("room", 1, true) or n:find("plate", 1, true) or n:find("hall", 1, true) then
    return "Reverb"
  end
  if n:find("delay", 1, true) or n:find("echo", 1, true) then return "Delay" end
  if n:find("chorus", 1, true) then return "Chorus" end
  if n:find("flanger", 1, true) then return "Flanger" end
  if n:find("phaser", 1, true) then return "Phaser" end
  if n:find("tremolo", 1, true) then return "Tremolo" end
  if n:find("vibrato", 1, true) then return "Vibrato" end
  if n:find("distort", 1, true) or n:find("saturat", 1, true) or n:find("overdrive", 1, true) or n:find("fuzz", 1, true) then
    return "Distortion/Saturation"
  end
  if n:find("de%-ess", 1, true) or n:find("deesser", 1, true) then return "De-Esser" end
  if n:find("pitch", 1, true) or n:find("tune", 1, true) or n:find("autotune", 1, true) then return "Pitch" end

  return "Other/Unknown"
end

local function sanitize_filename(s)
  s = tostring(s or "REAPER_Project")
  s = s:gsub("[\\/:*?\"<>|]", "_")
  s = s:gsub("%s+", "_")
  return s
end

local function fmt_time(ts)
  return os.date("%Y-%m-%d_%H%M%S", ts or os.time())
end

local function get_project_basename()
  local _, proj_file = reaper.EnumProjects(-1, "")
  if proj_file and proj_file ~= "" then
    -- Strip directories
    local name = proj_file:match("([^/\\]+)$")
    -- Strip extension
    name = name:gsub("%.rpp$", "")
    return name
  end
  return "UNSAVED_PROJECT"
end

local function export_receipt_txt()
  -- Prefer the directory of the current project file (most predictable).
  local _, proj_file = reaper.EnumProjects(-1, "")
  local proj_dir = reaper.GetProjectPath("") or ""

  -- If for some reason project path is empty, fall back to REAPER resource path.
  if not proj_dir or proj_dir == "" then
    proj_dir = reaper.GetResourcePath() or "."
  end

  local base = sanitize_filename(get_project_basename())
  local fname = string.format("DAAP_ManifestReceipt_%s_%s.txt", base, fmt_time(os.time()))
  local sep = package.config:sub(1, 1)
  if proj_dir:sub(-1) ~= sep then
    proj_dir = proj_dir .. sep
  end
  local fullpath = proj_dir .. fname

  local f, err = io.open(fullpath, "w")
  if not f then
    last_refresh_note = "Export failed: " .. tostring(err)
    return
  end

  local function W(line)
    f:write(line .. "\n")
  end

  W("============================================================")
  W("DAAP | IN-SESSION MANIFEST RECEIPT (FULL PARAMETERS)")
  W("============================================================")
  W("Project: " .. tostring(SNAP.project_name))
  W("Path:    " .. tostring(SNAP.project_path))
  W("Snapshot:" .. string.format(" %.3f", SNAP.generated_at))
  W("Tracks:  " .. tostring(SNAP.track_count))
  W("Exported:" .. os.date("%Y-%m-%d %H:%M:%S"))
  W("File:    " .. fullpath)
  W("")

  -- -------- Analytics --------
  local a = SNAP.analytics
  W("------------------------------------------------------------")
  W("ANALYTICS (COUNTS)")
  W("------------------------------------------------------------")
  if a then
    W(string.format("Total plugin instances: %d", a.total_instances or 0))
    W(string.format("Unique plugins:         %d", a.unique_plugins or 0))
    W(string.format("Makers represented:     %d", a.unique_makers or 0))
    W("")
    W("By FX Type (instances):")
    do
      local rows = {}
      for k, v in pairs(a.type_counts or {}) do rows[#rows + 1] = { k = k, v = v } end
      table.sort(rows, function(x, y) return x.v > y.v end)
      for i = 1, #rows do W(string.format("  - %s: %d", rows[i].k, rows[i].v)) end
    end
    W("")
    W("By Maker (instances):")
    do
      local rows = {}
      for maker, cnt in pairs(a.maker_counts or {}) do rows[#rows + 1] = { maker = maker, cnt = cnt } end
      table.sort(rows, function(x, y) return x.cnt > y.cnt end)
      for i = 1, #rows do W(string.format("  - %s: %d", rows[i].maker, rows[i].cnt)) end
    end
    W("")
    local u = a.unidentified_plugins or {}
    W(string.format("Unidentified (needs DB): %d", #u))
    for i = 1, #u do
      W(string.format("  - %s | maker=%s | type=%s | instances=%d",
        u[i].name, u[i].maker, u[i].ptype, u[i].instances))
    end
  else
    W("(analytics not available)")
  end
  W("")

  -- -------- Plugins Used --------
  W("------------------------------------------------------------")
  W("PLUGINS USED (PROJECT-WIDE)")
  W("------------------------------------------------------------")
  do
    local list = {}
    for _, v in pairs(SNAP.plugins_index or {}) do
      if v and v.name then list[#list + 1] = v end
    end
    table.sort(list, function(x, y)
      local xc = x.count or 0
      local yc = y.count or 0
      if xc == yc then return (x.name or "") < (y.name or "") end
      return xc > yc
    end)

    for i = 1, #list do
      local p = list[i]
      W(string.format("- %s (instances: %d)", p.name, p.count or 0))
      -- list unique tracks
      local seen = {}
      for t = 1, #(p.tracks or {}) do
        local tn = p.tracks[t] and p.tracks[t].track_name or nil
        if tn and not seen[tn] then
          seen[tn] = true
          W("    - " .. tn)
        end
      end
    end
  end
  W("")

  -- -------- Master + Tracks --------
  local function dump_track(tm)
    W("============================================================")
    W("TRACK: " .. tostring(tm.name))
    W("GUID:  " .. tostring(tm.guid))
    W(string.format("Items: %s | Channels: %s | Mute: %s | Solo: %s | Phase: %s",
      tostring(tm.item_count), tostring(tm.chan_count), tostring(tm.mute),
      tostring(tm.solo), tostring(tm.phase)))
    W("")

    W("FX CHAIN:")
    if tm.fx and tm.fx.chain and #tm.fx.chain > 0 then
      for i = 1, #tm.fx.chain do
        local fx = tm.fx.chain[i]
        local st = tostring(fx.status or "UNKNOWN"):upper()

        W("  ----------------------------------------------------------")
        W(string.format("  FX [%02d] %s (%s)", (fx.index or 0) + 1, tostring(fx.name), st))
        if fx.guid and fx.guid ~= "" then W("    FX GUID: " .. fx.guid) end
        if fx.preset and fx.preset ~= "" then W("    Preset:  " .. fx.preset) end

        -- FULL PARAMETER DUMP (captured)
        if fx.params and fx.params.params then
          W(string.format("    Params:  %d / %d captured",
            fx.params.count_captured or 0,
            fx.params.count_total or 0
          ))
          for p = 1, #fx.params.params do
            local param = fx.params.params[p]
            W(string.format("      - %s = %s",
              tostring(param.name),
              tostring(param.formatted)
            ))
          end
          if (fx.params.count_total or 0) > (fx.params.count_captured or 0) then
            W(string.format("      ... (%d more params not exported due to cap)",
              (fx.params.count_total - fx.params.count_captured)
            ))
          end
        else
          W("    Params:  (not captured)")
        end
      end
    else
      W("  (none)")
    end
    W("")

    -- Routing summary (kept concise)
    W("ROUTING:")
    if tm.routing then
      local sends = (tm.routing.sends and tm.routing.sends.sends) or {}
      local recvs = (tm.routing.receives and tm.routing.receives.receives) or {}
      local outs  = (tm.routing.hardware_outs and tm.routing.hardware_outs.outs) or {}

      W(string.format("  Sends: %d", #sends))
      for i = 1, #sends do
        local s = sends[i]
        W(string.format("    -> %s | vol=%s | pan=%.2f | src=%d dst=%d | mute=%s",
          tostring(s.dest_name), tostring(s.vol_db), s.pan or 0, s.src_chan or 0, s.dst_chan or 0, tostring(s.mute)))
      end

      W(string.format("  Receives: %d", #recvs))
      for i = 1, #recvs do
        local r = recvs[i]
        W(string.format("    <- %s | vol=%s | pan=%.2f | src=%d dst=%d | mute=%s",
          tostring(r.src_name), tostring(r.vol_db), r.pan or 0, r.src_chan or 0, r.dst_chan or 0, tostring(r.mute)))
      end

      W(string.format("  Hardware Outs: %d", #outs))
      for i = 1, #outs do
        local o = outs[i]
        W(string.format("    HW | vol=%s | pan=%.2f | src=%d dst=%d | mute=%s",
          tostring(o.vol_db), o.pan or 0, o.src_chan or 0, o.dst_chan or 0, tostring(o.mute)))
      end
    else
      W("  (no routing data)")
    end
    W("")
  end

  if SNAP.master then dump_track(SNAP.master) end
  for i = 1, #(SNAP.tracks or {}) do dump_track(SNAP.tracks[i]) end

  f:close()

  last_refresh_note = "Exported receipt: " .. fname
  reaper.ShowMessageBox("Manifest receipt saved to:\n\n" .. fullpath, "DAAP Export Receipt", 0)
end

-- ==============================
-- ImGui Style Stack Safety
-- ==============================
local STYLE_PUSHED_COLORS = 0
local STYLE_PUSHED_VARS   = 0

local function StylePushColor(col, u32)
  reaper.ImGui_PushStyleColor(ctx, col, u32)
  STYLE_PUSHED_COLORS = STYLE_PUSHED_COLORS + 1
end

local function StylePushVar(var, v)
  reaper.ImGui_PushStyleVar(ctx, var, v)
  STYLE_PUSHED_VARS = STYLE_PUSHED_VARS + 1
end

local function StylePopColor(count)
  if count and count > 0 and STYLE_PUSHED_COLORS > 0 then
    local n = math.min(count, STYLE_PUSHED_COLORS)
    reaper.ImGui_PopStyleColor(ctx, n)
    STYLE_PUSHED_COLORS = STYLE_PUSHED_COLORS - n
  end
end

local function StylePopAll()
  if STYLE_PUSHED_VARS > 0 then
    reaper.ImGui_PopStyleVar(ctx, STYLE_PUSHED_VARS)
    STYLE_PUSHED_VARS = 0
  end
  if STYLE_PUSHED_COLORS > 0 then
    reaper.ImGui_PopStyleColor(ctx, STYLE_PUSHED_COLORS)
    STYLE_PUSHED_COLORS = 0
  end
end

local function rgba(r, g, b, a)
  return reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, a)
end

local function push_paper_style()
  -- Background / text
  StylePushColor(reaper.ImGui_Col_WindowBg(), rgba(1, 1, 1, 1))
  StylePushColor(reaper.ImGui_Col_ChildBg(),  rgba(1, 1, 1, 1))
  StylePushColor(reaper.ImGui_Col_PopupBg(),  rgba(1, 1, 1, 1))
  StylePushColor(reaper.ImGui_Col_Text(),     rgba(0, 0, 0, 1))

  -- Lines / headers / frames / buttons
  StylePushColor(reaper.ImGui_Col_Border(),         rgba(0.2, 0.2, 0.2, 1))
  StylePushColor(reaper.ImGui_Col_Separator(),      rgba(0.2, 0.2, 0.2, 1))
  StylePushColor(reaper.ImGui_Col_Header(),         rgba(0.92, 0.92, 0.92, 1))
  StylePushColor(reaper.ImGui_Col_HeaderHovered(),  rgba(0.88, 0.88, 0.88, 1))
  StylePushColor(reaper.ImGui_Col_HeaderActive(),   rgba(0.84, 0.84, 0.84, 1))
  StylePushColor(reaper.ImGui_Col_FrameBg(),        rgba(0.95, 0.95, 0.95, 1))
  StylePushColor(reaper.ImGui_Col_FrameBgHovered(), rgba(0.92, 0.92, 0.92, 1))
  StylePushColor(reaper.ImGui_Col_FrameBgActive(),  rgba(0.90, 0.90, 0.90, 1))
  StylePushColor(reaper.ImGui_Col_Button(),         rgba(0.93, 0.93, 0.93, 1))
  StylePushColor(reaper.ImGui_Col_ButtonHovered(),  rgba(0.90, 0.90, 0.90, 1))
  StylePushColor(reaper.ImGui_Col_ButtonActive(),   rgba(0.87, 0.87, 0.87, 1))

  -- Flat "paper" corners
  StylePushVar(reaper.ImGui_StyleVar_FrameRounding(), 0)
  StylePushVar(reaper.ImGui_StyleVar_WindowRounding(), 0)
end

local function format_db_from_gain(g)
  if not g or g <= 0 then return "-inf dB" end
  local db = 20.0 * math.log(g, 10)
  return string.format("%.2f dB", db)
end

local function track_display_name(track, fallback_index)
  local _, name = reaper.GetTrackName(track, "")
  name = safe_str(name)
  if fallback_index then
    return string.format("%02d. %s", fallback_index, name)
  end
  return name
end

local function get_track_guid(track)
  -- returns string like "{...}"
  return reaper.GetTrackGUID(track)
end

local function get_fx_basic(track, fx_index)
  local fx = {}

  local _, fx_name = reaper.TrackFX_GetFXName(track, fx_index, "")
  fx.name = safe_str(fx_name)
  fx.index = fx_index

  -- Stronger identity / availability signals (more reliable than name heuristics)
  local ok_ident, ident = reaper.TrackFX_GetNamedConfigParm(track, fx_index, "fx_ident")
  fx.ident_ok = (ok_ident == true) and (ident ~= nil) and (ident ~= "")
  fx.ident = ident or ""

  local ok_fn, fn = reaper.TrackFX_GetNamedConfigParm(track, fx_index, "fx_name")
  fx.fxname_ok = (ok_fn == true) and (fn ~= nil) and (fn ~= "")
  fx.fxname = fn or ""

  fx.enabled = (reaper.TrackFX_GetEnabled(track, fx_index) == true)
  fx.offline = (reaper.TrackFX_GetOffline(track, fx_index) == true)
  fx.status = classify_fx_status(fx.name, fx.enabled, fx.offline, fx.ident_ok, fx.fxname_ok)

  -- GUID can be useful for stable identity across sessions
  fx.guid = reaper.TrackFX_GetFXGUID(track, fx_index)

  -- Preset name (may be empty if none/unsupported)
  local ok, preset = reaper.TrackFX_GetPreset(track, fx_index, "")
  if ok and preset and preset ~= "" then
    fx.preset = preset
  else
    fx.preset = ""
  end

  return fx
end

local function get_fx_params_snapshot(track, fx_index, max_params)
  local params = {}
  local num = reaper.TrackFX_GetNumParams(track, fx_index) or 0
  local limit = math.min(num, max_params or num)

  for p = 0, limit - 1 do
    local param = {}
    local _, pname = reaper.TrackFX_GetParamName(track, fx_index, p, "")
    param.name = safe_str(pname)

    local val, minval, maxval = reaper.TrackFX_GetParam(track, fx_index, p)
    param.value = val or 0.0
    param.min = minval or 0.0
    param.max = maxval or 1.0

    local _, fval = reaper.TrackFX_GetFormattedParamValue(track, fx_index, p, "")
    param.formatted = fval or ""

    params[#params + 1] = param
  end

  return {
    count_total = num,
    count_captured = limit,
    params = params
  }
end

-- ------------------------------
-- Routing Introspection
-- ------------------------------
local function get_send_common(track, category, send_index)
  -- category: 0=send, 1=receive, 2=hardware output
  local s = {}

  s.index = send_index
  s.category = category

  -- Volume & pan
  local vol = reaper.GetTrackSendInfo_Value(track, category, send_index, "D_VOL")
  local pan = reaper.GetTrackSendInfo_Value(track, category, send_index, "D_PAN")
  s.vol = vol or 1.0
  s.vol_db = format_db_from_gain(s.vol)
  s.pan = pan or 0.0

  -- Mute/phase
  s.mute  = (reaper.GetTrackSendInfo_Value(track, category, send_index, "B_MUTE") or 0) == 1
  s.phase = (reaper.GetTrackSendInfo_Value(track, category, send_index, "B_PHASE") or 0) == 1

  -- Channels (source/dest)
  s.src_chan = reaper.GetTrackSendInfo_Value(track, category, send_index, "I_SRCCHAN") or 0
  s.dst_chan = reaper.GetTrackSendInfo_Value(track, category, send_index, "I_DSTCHAN") or 0

  return s
end

local function get_track_sends_manifest(track)
  local sends = {}
  local send_count = reaper.GetTrackNumSends(track, 0) or 0
  local limit = math.min(send_count, OPT_MAX_SENDS_PER_TRACK)

  for i = 0, limit - 1 do
    local s = get_send_common(track, 0, i)

    -- Destination track pointer
    local dest_tr = reaper.GetTrackSendInfo_Value(track, 0, i, "P_DESTTRACK")
    if dest_tr then
      s.dest_name = track_display_name(dest_tr)
      s.dest_guid = get_track_guid(dest_tr)
    else
      s.dest_name = "(unknown)"
      s.dest_guid = ""
    end

    sends[#sends + 1] = s
  end

  return {
    count_total = send_count,
    count_captured = limit,
    sends = sends
  }
end

local function get_track_receives_manifest(track)
  local recvs = {}
  local recv_count = reaper.GetTrackNumSends(track, 1) or 0
  local limit = math.min(recv_count, OPT_MAX_SENDS_PER_TRACK)

  for i = 0, limit - 1 do
    local r = get_send_common(track, 1, i)

    -- Source track pointer
    local src_tr = reaper.GetTrackSendInfo_Value(track, 1, i, "P_SRCTRACK")
    if src_tr then
      r.src_name = track_display_name(src_tr)
      r.src_guid = get_track_guid(src_tr)
    else
      r.src_name = "(unknown)"
      r.src_guid = ""
    end

    recvs[#recvs + 1] = r
  end

  return {
    count_total = recv_count,
    count_captured = limit,
    receives = recvs
  }
end

local function get_track_hardware_outs_manifest(track)
  local outs = {}
  local hw_count = reaper.GetTrackNumSends(track, 2) or 0
  local limit = math.min(hw_count, OPT_MAX_SENDS_PER_TRACK)

  for i = 0, limit - 1 do
    local o = get_send_common(track, 2, i)

    -- For hardware sends, destination isn't a track; capture destination channel index
    o.hw_dst_chan = o.dst_chan
    outs[#outs + 1] = o
  end

  return {
    count_total = hw_count,
    count_captured = limit,
    outs = outs
  }
end

-- ------------------------------
-- Track Manifest Builder
-- ------------------------------
local function build_track_manifest(track, index_for_display)
  local tm = {}

  tm.index = index_for_display or 0
  tm.guid = get_track_guid(track)
  tm.name = track_display_name(track, index_for_display)
  tm.mute = reaper.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
  tm.solo = reaper.GetMediaTrackInfo_Value(track, "I_SOLO") ~= 0
  tm.phase = reaper.GetMediaTrackInfo_Value(track, "B_PHASE") == 1

  tm.chan_count = reaper.GetMediaTrackInfo_Value(track, "I_NCHAN") or 2
  tm.item_count = reaper.CountTrackMediaItems(track) or 0

  -- ------------------------------
  -- FX Chain
  -- ------------------------------
  tm.fx = { count = 0, chain = {} }

  local fx_count = reaper.TrackFX_GetCount(track) or 0
  tm.fx.count = fx_count

  for fx_i = 0, fx_count - 1 do
    local fx = get_fx_basic(track, fx_i)

    if (not OPT_SHOW_ONLY_ENABLED_FX) or (fx.enabled and not fx.offline) then
      if OPT_SHOW_FX_PARAMS then
        fx.params = get_fx_params_snapshot(track, fx_i, OPT_MAX_PARAMS_PER_FX)
      else
        fx.params = nil
      end
      tm.fx.chain[#tm.fx.chain + 1] = fx
    end
  end

  -- ------------------------------
  -- Routing
  -- ------------------------------
  tm.routing = {
    sends = get_track_sends_manifest(track),
    receives = get_track_receives_manifest(track),
    hardware_outs = get_track_hardware_outs_manifest(track)
  }

  return tm
end

local function build_master_manifest()
  local master = reaper.GetMasterTrack(0)
  if not master then return nil end

  local mm = build_track_manifest(master, nil)
  mm.name = "MASTER"
  mm.index = -1
  return mm
end

-- ------------------------------
-- Project Metadata
-- ------------------------------
local function collect_project_identity()
  local proj = 0
  local proj_path = reaper.GetProjectPath("") or ""
  local _, proj_file = reaper.EnumProjects(-1, "")
  SNAP.project_path = proj_path
  SNAP.project_name = safe_str(proj_file)
end

local function build_analytics()
  local a = {
    total_instances = 0,
    unique_plugins = 0,
    unique_makers = 0,
    type_counts = {},          -- type -> instances
    maker_counts = {},         -- maker -> instances
    track_fx_counts = {},      -- track_name -> instance count
    unidentified_plugins = {}  -- plugins with Unknown maker or Other/Unknown type
  }

  -- Use plugins_index as source of truth
  local idx = SNAP.plugins_index or {}
  local makers_seen = {}

  -- Convert plugins_index map to list for counting
  local plugin_list = {}
  for _, p in pairs(idx) do
    if p and p.name then plugin_list[#plugin_list + 1] = p end
  end
  a.unique_plugins = #plugin_list

  for i = 1, #plugin_list do
    local p = plugin_list[i]
    local pname = p.name
    local instances = p.count or 0
    a.total_instances = a.total_instances + instances

    local maker = parse_vendor_from_fx_name(pname)
    makers_seen[maker] = true
    a.maker_counts[maker] = (a.maker_counts[maker] or 0) + instances

    local ptype = classify_fx_type(pname)
    a.type_counts[ptype] = (a.type_counts[ptype] or 0) + instances

    if maker == "Unknown" and ptype == "Other/Unknown" then
      a.unidentified_plugins[#a.unidentified_plugins + 1] = {
        name = pname, maker = maker, ptype = ptype, instances = instances
      }
    end
  end

  -- Track FX instance counts
  for i = 1, #SNAP.tracks do
    local tm = SNAP.tracks[i]
    local fx_count = 0
    if tm.fx and tm.fx.chain then
      fx_count = #tm.fx.chain
    end
    a.track_fx_counts[tm.name] = (a.track_fx_counts[tm.name] or 0) + fx_count
  end

  if SNAP.master then
    local fx_count = 0
    if SNAP.master.fx and SNAP.master.fx.chain then
      fx_count = #SNAP.master.fx.chain
    end
    a.track_fx_counts["MASTER"] = (a.track_fx_counts["MASTER"] or 0) + fx_count
  end

  -- Count unique makers
  local mc = 0
  for _ in pairs(makers_seen) do mc = mc + 1 end
  a.unique_makers = mc

  return a
end

-- ==============================
-- Snapshot Collection
-- ==============================
local function refresh_snapshot()
  SNAP.generated_at = now_seconds()
  collect_project_identity()

  SNAP.tracks = {}
  SNAP.master = nil
  SNAP.plugins_index = {}

  local track_count = reaper.CountTracks(0) or 0
  SNAP.track_count = track_count

  local limit = math.min(track_count, OPT_MAX_TRACKS_RENDERED)
  for i = 0, limit - 1 do
    local tr = reaper.GetTrack(0, i)
    if tr then
      local tm = build_track_manifest(tr, i + 1)
      SNAP.tracks[#SNAP.tracks + 1] = tm

      -- Build global plugin inventory (deduped)
      if tm.fx and tm.fx.chain then
        for k = 1, #tm.fx.chain do
          local fx = tm.fx.chain[k]
          local key = normalize_fx_name(fx.name)

          if not SNAP.plugins_index[key] then
            SNAP.plugins_index[key] = {
              name = key,
              count = 0,
              tracks = {} -- array of { track_name=..., track_guid=... }
            }
          end

          SNAP.plugins_index[key].count = SNAP.plugins_index[key].count + 1
          SNAP.plugins_index[key].tracks[#SNAP.plugins_index[key].tracks + 1] = {
            track_name = tm.name,
            track_guid = tm.guid
          }
        end
      end
    end
  end

  if OPT_INCLUDE_MASTER then
    SNAP.master = build_master_manifest()
  end

  if OPT_INCLUDE_MASTER and SNAP.master and SNAP.master.fx and SNAP.master.fx.chain then
    for k = 1, #SNAP.master.fx.chain do
      local fx = SNAP.master.fx.chain[k]
      local key = normalize_fx_name(fx.name)

      if not SNAP.plugins_index[key] then
        SNAP.plugins_index[key] = { name = key, count = 0, tracks = {} }
      end

      SNAP.plugins_index[key].count = SNAP.plugins_index[key].count + 1
      SNAP.plugins_index[key].tracks[#SNAP.plugins_index[key].tracks + 1] = {
        track_name = "MASTER",
        track_guid = SNAP.master.guid
      }
    end
  end

  SNAP.analytics = build_analytics()
end

-- ==============================
-- UI Rendering Helpers
-- ==============================
local function draw_key_value(label, value)
  reaper.ImGui_Text(ctx, label)
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, tostring(value))
end

local function draw_routing_block(routing)
  if not routing then
    reaper.ImGui_Text(ctx, "(no routing data)")
    return
  end

  -- Sends
  if reaper.ImGui_TreeNode(ctx, "Sends (" .. tostring(routing.sends.count_total) .. ")") then
    local sends = routing.sends.sends or {}
    if #sends == 0 then
      reaper.ImGui_Text(ctx, "(none)")
    else
      for i = 1, #sends do
        local s = sends[i]
        reaper.ImGui_BulletText(ctx,
          string.format("→ %s | vol=%s | pan=%.2f | srcChan=%d dstChan=%d | mute=%s",
            safe_str(s.dest_name), s.vol_db, s.pan, s.src_chan, s.dst_chan, tostring(s.mute)
          )
        )
      end
    end
    reaper.ImGui_TreePop(ctx)
  end

  -- Receives
  if reaper.ImGui_TreeNode(ctx, "Receives (" .. tostring(routing.receives.count_total) .. ")") then
    local recvs = routing.receives.receives or {}
    if #recvs == 0 then
      reaper.ImGui_Text(ctx, "(none)")
    else
      for i = 1, #recvs do
        local r = recvs[i]
        reaper.ImGui_BulletText(ctx,
          string.format("← %s | vol=%s | pan=%.2f | srcChan=%d dstChan=%d | mute=%s",
            safe_str(r.src_name), r.vol_db, r.pan, r.src_chan, r.dst_chan, tostring(r.mute)
          )
        )
      end
    end
    reaper.ImGui_TreePop(ctx)
  end

  -- Hardware outs
  if reaper.ImGui_TreeNode(ctx, "Hardware Outs (" .. tostring(routing.hardware_outs.count_total) .. ")") then
    local outs = routing.hardware_outs.outs or {}
    if #outs == 0 then
      reaper.ImGui_Text(ctx, "(none)")
    else
      for i = 1, #outs do
        local o = outs[i]
        reaper.ImGui_BulletText(ctx,
          string.format("HW OUT | vol=%s | pan=%.2f | srcChan=%d dstChan=%d | mute=%s",
            o.vol_db, o.pan, o.src_chan, o.dst_chan, tostring(o.mute)
          )
        )
      end
    end
    reaper.ImGui_TreePop(ctx)
  end
end

local function draw_fx_chain(fx_block)
  if not fx_block or not fx_block.chain then
    reaper.ImGui_Text(ctx, "(no FX)")
    return
  end

  local chain = fx_block.chain
  if #chain == 0 then
    reaper.ImGui_Text(ctx, "(none detected)")
    return
  end

  for i = 1, #chain do
    local fx = chain[i]
    -- Status label (words only)
    local status_txt = ""
    if fx.status == "unavailable" then
      status_txt = "UNAVAILABLE"
    elseif fx.status == "offline" then
      status_txt = "OFFLINE"
    elseif fx.status == "bypassed" then
      status_txt = "BYPASSED"
    else
      status_txt = "ACTIVE"
    end

    local header = string.format("[%02d] %s (%s)",
      fx.index + 1,
      safe_str(fx.name),
      status_txt
    )

    if reaper.ImGui_TreeNode(ctx, header) then
      if fx.guid and fx.guid ~= "" then
        draw_key_value("FX GUID:", fx.guid)
      end
      if fx.preset and fx.preset ~= "" then
        draw_key_value("Preset:", fx.preset)
      end

      if fx.params then
        local ps = fx.params
        draw_key_value("Params (captured/total):", string.format("%d / %d", ps.count_captured, ps.count_total))
        reaper.ImGui_Separator(ctx)

        -- Parameter list (capped)
        for p = 1, #ps.params do
          local param = ps.params[p]
          reaper.ImGui_BulletText(ctx,
            string.format("%s = %s", safe_str(param.name), safe_str(param.formatted))
          )
        end

        if ps.count_total > ps.count_captured then
          reaper.ImGui_Text(ctx, string.format("... (%d more params not displayed)", ps.count_total - ps.count_captured))
        end
      end

      reaper.ImGui_TreePop(ctx)
    end
  end
end

local function draw_track_manifest(tm)
  if not tm then return end

  local label = tm.name
  if reaper.ImGui_TreeNode(ctx, label) then
    draw_key_value("Track GUID:", tm.guid)
    draw_key_value("Items:", tm.item_count)
    draw_key_value("Channels:", tm.chan_count)
    draw_key_value("Mute:", tostring(tm.mute))
    draw_key_value("Solo:", tostring(tm.solo))
    draw_key_value("Phase invert:", tostring(tm.phase))

    reaper.ImGui_Spacing(ctx)

    if reaper.ImGui_TreeNode(ctx, "FX Chain") then
      draw_fx_chain(tm.fx)
      reaper.ImGui_TreePop(ctx)
    end

    reaper.ImGui_Spacing(ctx)

    if reaper.ImGui_TreeNode(ctx, "Routing") then
      draw_routing_block(tm.routing)
      reaper.ImGui_TreePop(ctx)
    end

    reaper.ImGui_TreePop(ctx)
  end
end

-- ==============================
-- UI State
-- ==============================
local FILTER_TEXT = ""
local last_refresh_note = ""
local APP_RUNNING = true

local function hard_refresh()
  -- Full rescan
  refresh_snapshot()

  -- Optional: reset filter so you see everything again
  -- Comment out if you want filter preserved across refresh
  -- FILTER_TEXT = ""

  -- Clear any per-refresh notes
  last_refresh_note = "Snapshot refreshed @ " .. string.format("%.2f", reaper.time_precise())
end

-- ==============================
-- Main UI Loop
-- ==============================
local function main()
  if OPT_PAPER_STYLE then
    push_paper_style()
  end

  local visible, open = reaper.ImGui_Begin(ctx, UI_TITLE, true)
  if visible then
    local ok, err = xpcall(function()
      -- ------------------------------------------------------------
      -- HEADER / PROJECT IDENTITY
      -- ------------------------------------------------------------
      reaper.ImGui_Text(ctx, "DAAP In-Session Manifest (Display-Only)")
      reaper.ImGui_Separator(ctx)

      draw_key_value("Project:", SNAP.project_name)
      draw_key_value("Path:", SNAP.project_path)
      draw_key_value("Snapshot Time:", string.format("%.3f", SNAP.generated_at))
      draw_key_value("Tracks:", SNAP.track_count)

      reaper.ImGui_Spacing(ctx)

      -- ------------------------------------------------------------
      -- CONTROLS
      -- ------------------------------------------------------------
      if reaper.ImGui_Button(ctx, "Refresh Snapshot") then
        hard_refresh()
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Export Receipt (.txt)") then
        export_receipt_txt()
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Exit") then
        APP_RUNNING = false
      end
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx, safe_str(last_refresh_note))

      reaper.ImGui_Spacing(ctx)

      -- Filter input
      local changed, new_filter = reaper.ImGui_InputText(ctx, "Filter (track/fx)", FILTER_TEXT)
      if changed then FILTER_TEXT = new_filter end

      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)

      -- ------------------------------------------------------------
      -- ANALYTICS (INGREDIENTS OVERVIEW)
      -- ------------------------------------------------------------
      if reaper.ImGui_TreeNode(ctx, "Analytics (Ingredients)") then
        local a = SNAP.analytics

        if not a then
          reaper.ImGui_Text(ctx, "(analytics not available - refresh snapshot)")
        else
          reaper.ImGui_BulletText(ctx, string.format("Total plugin instances: %d", a.total_instances))
          reaper.ImGui_BulletText(ctx, string.format("Unique plugins: %d", a.unique_plugins))
          reaper.ImGui_BulletText(ctx, string.format("Plugin makers represented: %d", a.unique_makers))

          reaper.ImGui_Separator(ctx)

          -- Types breakdown
          reaper.ImGui_SetNextItemOpen(ctx, true, reaper.ImGui_Cond_Appearing())
          if reaper.ImGui_TreeNode(ctx, "By FX Type") then
            local rows = {}
            for k, v in pairs(a.type_counts) do rows[#rows + 1] = { k = k, v = v } end
            table.sort(rows, function(x, y) return x.v > y.v end)
            for i = 1, #rows do
              reaper.ImGui_BulletText(ctx, string.format("%s: %d", rows[i].k, rows[i].v))
            end
            reaper.ImGui_TreePop(ctx)
          end

          -- Makers breakdown (instances)
          reaper.ImGui_SetNextItemOpen(ctx, true, reaper.ImGui_Cond_Appearing())
          if reaper.ImGui_TreeNode(ctx, "By Maker (Instances)") then
            local rows = {}
            for maker, cnt in pairs(a.maker_counts) do
              rows[#rows + 1] = { maker = maker, cnt = cnt }
            end
            table.sort(rows, function(x, y) return x.cnt > y.cnt end)
            for i = 1, #rows do
              reaper.ImGui_BulletText(ctx, string.format("%s: %d", rows[i].maker, rows[i].cnt))
            end
            reaper.ImGui_TreePop(ctx)
          end

          -- Unidentified list
          reaper.ImGui_SetNextItemOpen(ctx, true, reaper.ImGui_Cond_Appearing())
          if reaper.ImGui_TreeNode(ctx, string.format("Unidentified / Needs DB (%d)", #a.unidentified_plugins)) then
            table.sort(a.unidentified_plugins, function(x, y) return (x.instances or 0) > (y.instances or 0) end)
            for i = 1, #a.unidentified_plugins do
              local u = a.unidentified_plugins[i]
              reaper.ImGui_BulletText(ctx, string.format("%s | maker=%s | type=%s | instances=%d",
                u.name, u.maker, u.ptype, u.instances))
            end
            reaper.ImGui_TreePop(ctx)
          end

          -- Track instance counts
          reaper.ImGui_SetNextItemOpen(ctx, true, reaper.ImGui_Cond_Appearing())
          if reaper.ImGui_TreeNode(ctx, "By Track (FX Instances)") then
            local rows = {}
            for tn, cnt in pairs(a.track_fx_counts or {}) do
              rows[#rows + 1] = { tn = tn, cnt = cnt }
            end
            table.sort(rows, function(x, y) return x.cnt > y.cnt end)
            for i = 1, #rows do
              reaper.ImGui_BulletText(ctx, string.format("%s: %d", rows[i].tn, rows[i].cnt))
            end
            reaper.ImGui_TreePop(ctx)
          end
        end

        reaper.ImGui_TreePop(ctx)
      end

      reaper.ImGui_Separator(ctx)

      -- ------------------------------------------------------------
      -- PLUGINS USED (PROJECT-WIDE INVENTORY)  [HARDENED]
      -- ------------------------------------------------------------
      do
        local opened = reaper.ImGui_TreeNode(ctx, "Plugins Used (Project)")
        if opened then
          local list = {}

          -- Defensive: SNAP.plugins_index may be nil during refactors
          local idx = SNAP.plugins_index or {}
          for _, v in pairs(idx) do
            if v and v.name then
              list[#list + 1] = v
            end
          end

          table.sort(list, function(a, b)
            local ac = a.count or 0
            local bc = b.count or 0
            if ac == bc then
              return (a.name or "") < (b.name or "")
            end
            return ac > bc
          end)

          reaper.ImGui_Text(ctx, string.format("Unique plugins: %d", #list))
          reaper.ImGui_Separator(ctx)

          if #list == 0 then
            reaper.ImGui_Text(ctx, "(none)")
          else
            for i = 1, #list do
              local p = list[i]
              local pname = p.name or "(unknown)"
              local pcount = p.count or 0
              local header = string.format("%s  (instances: %d)", pname, pcount)

              local opened_p = reaper.ImGui_TreeNode(ctx, header)
              if opened_p then
                local seen = {}
                local tracks = p.tracks or {}
                for t = 1, #tracks do
                  local tn = tracks[t] and tracks[t].track_name or nil
                  if tn and not seen[tn] then
                    seen[tn] = true
                    reaper.ImGui_BulletText(ctx, tn)
                  end
                end
                reaper.ImGui_TreePop(ctx)
              end
            end
          end

          reaper.ImGui_TreePop(ctx)
        end
      end

      reaper.ImGui_Separator(ctx)

      -- ------------------------------------------------------------
      -- MASTER
      -- ------------------------------------------------------------
      if OPT_INCLUDE_MASTER and SNAP.master then
        if FILTER_TEXT == "" or string.find(string.lower("master"), string.lower(FILTER_TEXT), 1, true) then
          if reaper.ImGui_TreeNode(ctx, "MASTER (Main Out)") then
            draw_track_manifest(SNAP.master)
            reaper.ImGui_TreePop(ctx)
          end
        end
        reaper.ImGui_Separator(ctx)
      end

      -- ------------------------------------------------------------
      -- TRACKS (COLLAPSIBLE)
      -- ------------------------------------------------------------
      local tracks_label = string.format("Tracks (%d)", #SNAP.tracks)
      if reaper.ImGui_TreeNode(ctx, tracks_label) then
        reaper.ImGui_Separator(ctx)

        local f = string.lower(FILTER_TEXT or "")
        for i = 1, #SNAP.tracks do
          local tm = SNAP.tracks[i]

          -- Basic filter over track name + FX names (coarse but effective)
          local show = true
          if f ~= "" then
            show = false

            if string.find(string.lower(tm.name), f, 1, true) then
              show = true
            else
              -- scan FX names
              if tm.fx and tm.fx.chain then
                for k = 1, #tm.fx.chain do
                  local fx = tm.fx.chain[k]
                  if string.find(string.lower(fx.name), f, 1, true) then
                    show = true
                    break
                  end
                end
              end
            end
          end

          if show then
            draw_track_manifest(tm)
          end
        end

        reaper.ImGui_TreePop(ctx)
      end
    end, debug.traceback)

    reaper.ImGui_End(ctx)

    if not ok then
      reaper.ShowConsoleMsg("\n[DAAP Manifest UI] UI error:\n" .. tostring(err) .. "\n")
    end
  else
    reaper.ImGui_End(ctx)
  end

  StylePopAll()

  if not APP_RUNNING then
    open = false
  end

  if open then
    reaper.defer(main)
  else
    reaper.ImGui_DestroyContext(ctx)
  end
end

-- ==============================
-- Boot
-- ==============================
hard_refresh()
reaper.defer(main)
