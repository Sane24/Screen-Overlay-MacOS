-- Day Planner Overlay (Hammerspoon)
--
-- MORNING   First time the laptop is open and unlocked after 7am: full screen with a collage
--           of pics, a tip, today's calendar, and your plan. Confirm it, edit it, or plan the day.
-- PLANNING  Up to 5 tasks, each with a start time and a length ("4pm Study GRE 3h").
--           Tasks also go to Structured as timed blocks (if that shortcut exists).
-- TASKS     30 min before: spoken heads-up. At start time the screen gets covered:
--             Enter = type the first step, then the 25 min Clock timer (+ Structured focus timer)
--             S     = not now. You get one of your tips and 8 seconds to think. Then:
--                     Enter = just 2 minutes.  B = busy / out: type why, then pick how long.
--                     After 3 pushes it can only be started, moved to tomorrow, or dropped.
-- BLOCK END When the length you planned is up (counted from when you started), it checks in:
--             D = done (celebration with your pics)   G = still going (+30 min)   N = next step
-- NIGHT     At midnight: close out the day. Each open task: done, tomorrow (pick a time), or drop.
--           Then plan tomorrow if you want. Missed it? It shows the next time you open the laptop.
-- PICS      Overlays show pics from M.imageFolder, never cropped. Left / Right arrows flip through more.
--           Typing boxes get a dark screen with the time and a row of pics behind them.
-- QUIET     10pm to 7am: no task reminders, heads-ups or block check-ins.
--           The night review and morning still show.
--
-- Hotkeys (ctrl+alt+cmd + key)
--   N  plan today              shift+N  plan tomorrow
--   T  check-in now            O  morning screen now        R  close out today now
--   P  pause everything until tomorrow morning (press again to resume)
--   M  mute / unmute sounds (heads-up voice, celebration sound)
--
-- Shortcuts this uses (Shortcuts app). Only "Focus 25" is needed; the rest are optional.
--   "Focus 25"                  Start Timer, 25 minutes
--   "DayPlan to Structured"     adds a task to Structured (title, start, minutes from the clipboard)
--   "DayPlan Structured Focus"  starts Structured's focus timer
--   "DayPlan Agenda"            calendar events + reminders for the next 2 days

hs.menuIcon(true)

DayPlan = {}
local M = DayPlan

-- ===== settings =====
M.maxTasks          = 5                  -- tasks per day
M.defaultMinutes    = 30                 -- task length if you don't give one
M.extendMinutes     = 30                 -- "still going" / "next step" checks back after this long
M.morningHour       = 7                  -- morning screen: first unlock at or after this hour
M.reviewHour        = 0                  -- night review: 0 = midnight
M.dayStartHour      = 4                  -- a "day" runs 4am to 4am, so midnight still counts as today
M.headsUpMinutes    = 30                 -- spoken heads-up this many min before a task (0 = off)
M.checkinMinutes    = 0                  -- automatic check-ins every N min (0 = off)
M.quietFrom         = 22                 -- no task reminders from 10pm...
M.quietTo           = 7                  -- ...to 7am (nil = no quiet hours)
M.minShowSeconds    = 3                  -- overlays ignore keys/clicks for this long
M.notNowWaitSeconds = 8                  -- the "not now" screen locks for this long
M.maxSnoozes        = 3                  -- pushes per task before it's start / tomorrow / drop only
M.planPromptHour    = 8                  -- still no plan after this hour: ask again every hour (nil = never)
M.snoozes           = { 15, 30, 60 }     -- quick push buttons, in minutes
M.promptPics        = 4                  -- pics behind typing boxes
M.collagePics       = 4                  -- pics in the morning / night collage
M.celebratePics     = 6                  -- pics on the celebration screen
M.celebrateSound    = "Hero"             -- any name from /System/Library/Sounds (nil = none)
M.timerShortcut           = "Focus 25"
M.structuredAddShortcut   = "DayPlan to Structured"
M.structuredFocusShortcut = "DayPlan Structured Focus"
M.agendaShortcut          = "DayPlan Agenda"
M.file        = os.getenv("HOME") .. "/.hammerspoon/dayplan.json"
M.oldFile     = os.getenv("HOME") .. "/.hammerspoon/today.json"
M.agendaFile  = os.getenv("HOME") .. "/.hammerspoon/agenda.txt"
M.imageFolder = os.getenv("HOME") .. "/Desktop/crushing"   -- motivation pics (nil = off)

-- Look
M.theme = {
  bgTop    = { hex = "#1A1733", alpha = 0.98 },   -- background fades from this at the top...
  bgBottom = { hex = "#0A0A12", alpha = 0.98 },   -- ...to this at the bottom
  glow     = { hex = "#FFD166", alpha = 0.07 },   -- soft warm light behind the text
  accent   = { hex = "#FFD166" },
  onAccent = { hex = "#17140A" },
  text     = { white = 0.96 },
  dim      = { white = 0.66 },
  faint    = { white = 0.44 },
  panel    = { hex = "#0D0C18", alpha = 0.84 },
  picRadius = 18,
  fonts = {
    clock = "Avenir Next Ultra Light",
    title = "Avenir Next Demi Bold",
    body  = "Avenir Next Medium",
    small = "Avenir Next Regular",
  },
}

-- Tips, from your playbook. Edit freely.
M.startTips = {   -- shown on the "not now" screen
  "Just touch it. Open the file, pick up the pen. Putting it down after is allowed.",
  "Next-minute method: write what you'll do in just the next minute. Commit, do, close.",
  "Knuckles, stretch, start the 25 min timer.",
  "Do only the first step. That's the whole job right now.",
  "Make the worst possible first version on purpose.",
  "Write the win condition: what does done look like?",
  "3-2-1: 3 min moving, 2 min brain dump, 1 min writing what done looks like.",
  "Avoiding it because it's scary? Name the fear in one line. Shrink it to a move under two minutes.",
  "Phone in another room for this one set.",
  "Work next to someone.",
}
M.morningTips = { -- shown on the morning screen
  "Matcha, read the plan, then the hardest thing first.",
  "Nothing is ruined. Start from here.",
  "The old plan is information now, not a debt.",
  "Cardio before sitting.",
  "Can't choose? The one with a deadline wins. Both dated: the smaller one first.",
  "Write the win condition before you start.",
  "Phone in another room for timed sets.",
}
M.celebrateLines = { -- shown when you finish something
  "Crushing it.",
  "That's proof you can.",
  "Said you would. Did it.",
  "Future you says thanks.",
  "One less thing living in your head.",
}
-- ====================

M.canvases       = {}
M.canvasAreas    = {}
M.modal          = nil
M.mode           = nil
M.pausedUntil    = nil
M.lastCheckin    = nil
M.planNextAsk    = 0
M.muted          = hs.settings.get("dayplan.muted") or false
M.imgList        = {}
M.imgPos         = 1
M.imgEl          = {}
M.slotCount      = 0
M.hasImage       = false
M.lineIndex      = {}
M.overlayId      = 0
M.shortcutNames  = {}
M.shortcutQueue  = {}

local T      = M.theme
local MARKS  = { pending = "○", started = "▶", done = "✓", dropped = "✗", moved = "→" }

-- ---------- helpers ----------
local function trim(s)
  return ((s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function fmtTime(t)
  return (os.date("%I:%M %p", t):gsub("^0", ""))
end

local function fmtDur(secs)
  local m = math.max(0, math.floor(secs / 60 + 0.5))
  if m < 60 then return m .. " min" end
  return string.format("%dh %02dm", m // 60, m % 60)
end

-- task length for display: "45m", "1h", "1h 30m"
local function fmtLen(m)
  if not m then return "" end
  if m < 60 then return m .. "m" end
  if m % 60 == 0 then return (m // 60) .. "h" end
  return string.format("%dh %dm", m // 60, m % 60)
end

local function randomTip(list)
  if not list or #list == 0 then return "" end
  return list[math.random(#list)]
end

local function playSound(name)
  if M.muted or not name then return end
  local s = hs.sound.getByName(name)
  if s then s:play() end
end

local function isQuiet(now)
  if not (M.quietFrom and M.quietTo) then return false end
  local h = tonumber(os.date("%H", now))
  if M.quietFrom > M.quietTo then
    return h >= M.quietFrom or h < M.quietTo      -- e.g. 22 to 7, crosses midnight
  end
  return h >= M.quietFrom and h < M.quietTo
end

local function isLocked()
  local ok, p = pcall(hs.caffeinate.sessionProperties)
  if not ok or type(p) ~= "table" then return false end
  local v = p.CGSSessionScreenIsLocked
  return v == true or v == 1
end

-- ---------- days ----------
-- A "day" runs from dayStartHour to dayStartHour, so 12:30am still belongs to the day before.
local function dateOf(t) return os.date("%Y-%m-%d", t - M.dayStartHour * 3600) end
local function today() return dateOf(os.time()) end

local function ymd(date)
  local y, mo, d = date:match("^(%d+)-(%d+)-(%d+)$")
  return tonumber(y), tonumber(mo), tonumber(d)
end

local function dateAdd(date, n)
  local y, mo, d = ymd(date)
  return os.date("%Y-%m-%d", os.time({ year = y, month = mo, day = d + n, hour = 12 }))
end

local function prettyDate(date)
  local y, mo, d = ymd(date)
  local t = os.time({ year = y, month = mo, day = d, hour = 12 })
  return (os.date("%A, %b %d", t):gsub(" 0(%d)$", " %1"))
end

local function dayLabel(date)
  local td = today()
  if date == td then return "today" end
  if date == dateAdd(td, 1) then return "tomorrow" end
  return prettyDate(date)
end

-- a clock time on a planner day (times before dayStartHour land after midnight)
local function timeOn(date, h, m)
  local y, mo, d = ymd(date)
  local extra = (h < M.dayStartHour) and 1 or 0
  return os.time({ year = y, month = mo, day = d + extra, hour = h, min = m, sec = 0 })
end

local function reviewTime(date)
  local y, mo, d = ymd(date)
  local start = os.time({ year = y, month = mo, day = d, hour = M.dayStartHour, min = 0, sec = 0 })
  return start + ((M.reviewHour - M.dayStartHour) % 24) * 3600
end

local function nextMorning()
  local d = os.date("*t", os.time())
  local t = os.time({ year = d.year, month = d.month, day = d.day, hour = M.morningHour, min = 0, sec = 0 })
  if t <= os.time() then t = t + 24 * 3600 end
  return t
end

-- ---------- storage ----------
-- { days = { ["2026-11-04"] = { tasks = {...}, reviewed = bool, confirmed = bool } }, morningShown = date }
local function loadStore()
  local ok, s = pcall(hs.json.read, M.file)
  if ok and type(s) == "table" then
    if type(s.days) ~= "table" then s.days = {} end
    return s
  end
  s = { days = {} }
  local ok2, old = pcall(hs.json.read, M.oldFile)   -- carry over the old today.json once
  if ok2 and type(old) == "table" and type(old.date) == "string" and type(old.tasks) == "table" then
    s.days[old.date] = { tasks = old.tasks }
  end
  return s
end

local function saveStore(s)
  local cutoff = dateAdd(today(), -21)
  for date in pairs(s.days) do
    if date < cutoff then s.days[date] = nil end
  end
  hs.json.write(s, M.file, true, true)
end

local function dayOf(s, date)
  s.days[date] = s.days[date] or {}
  if type(s.days[date].tasks) ~= "table" then s.days[date].tasks = {} end
  return s.days[date]
end

local function activeIndex(d)
  local best, bestT = nil, -1
  for i, t in ipairs(d.tasks) do
    if t.state == "started" and (t.startedAt or 0) > bestT then
      best, bestT = i, (t.startedAt or 0)
    end
  end
  return best
end

local function nextIndex(d)
  local best, bestDue = nil, math.huge
  for i, t in ipairs(d.tasks) do
    if t.state == "pending" and t.due < bestDue then best, bestDue = i, t.due end
  end
  return best
end

local function openCount(d)
  local n = 0
  for _, t in ipairs(d.tasks) do
    if t.state == "pending" or t.state == "started" then n = n + 1 end
  end
  return n
end

local function doneCount(d)
  local n = 0
  for _, t in ipairs(d.tasks) do if t.state == "done" then n = n + 1 end end
  return n
end

local function taskListText(d, heading)
  local out = {}
  if heading then table.insert(out, heading) end
  for _, t in ipairs(d.tasks) do
    local len = fmtLen(t.minutes)
    table.insert(out, string.format("%s   %s    %s%s", MARKS[t.state] or "○", fmtTime(t.due), t.name,
      (len ~= "") and ("   ·  " .. len) or ""))
  end
  return table.concat(out, "\n")
end

local function setState(date, idx, state)
  local s = loadStore()
  local t = dayOf(s, date).tasks[idx]
  if t then
    t.state = state
    if state == "done" then t.doneAt = os.time() end
    saveStore(s)
  end
  return t
end

-- ---------- parsing ----------
-- "10:30am", "2pm", "14:00", "3:00" (1-7 with no am/pm = pm). Returns hour, minute, rest of the text.
local function parseClock(s)
  s = trim(s)
  local h, m, ap, rest = s:match("^(%d%d?):(%d%d)%s*([aApP])[mM]%f[%A]%s*(.*)$")
  if not h then
    h, ap, rest = s:match("^(%d%d?)%s*([aApP])[mM]%f[%A]%s*(.*)$")
    m = "0"
  end
  if not h then
    h, m, rest = s:match("^(%d%d?):(%d%d)%s*(.*)$")
    ap = nil
  end
  if not h then return nil end
  h, m = tonumber(h), tonumber(m)
  if ap then
    ap = ap:lower()
    if h < 1 or h > 12 then return nil end
    if ap == "p" and h < 12 then h = h + 12 end
    if ap == "a" and h == 12 then h = 0 end
  elseif h >= 1 and h <= 7 then
    h = h + 12
  end
  if h > 23 or m > 59 then return nil end
  return h, m, trim(rest)
end

local LEN_UNITS = { m = 1, min = 1, mins = 1, minute = 1, minutes = 1,
                    h = 60, hr = 60, hrs = 60, hour = 60, hours = 60 }

-- "45", "45m", "45 min" = minutes.  "2h", "1.5h", "1 hr" = hours.
local function parseLength(txt)
  local num, unit = trim(txt):lower():match("^(%d+%.?%d*)%s*(%a*)$")
  local n = tonumber(num or "")
  if not n then return nil end
  local mult = (unit == "") and 1 or LEN_UNITS[unit]
  if not mult then return nil end
  local mins = math.floor(n * mult + 0.5)
  if mins < 1 then return nil end
  return mins
end

-- "CS160 PRD 45m" -> "CS160 PRD", 45      "CS160 PRD" -> "CS160 PRD", nil
local function splitLength(s)
  local name, num, unit = s:match("^(.-)[,%s]+(%d+%.?%d*)%s*(%a+)$")
  if name and trim(name) ~= "" and LEN_UNITS[unit:lower()] then
    return trim(name), parseLength(num .. unit)
  end
  return trim(s), nil
end

local function snoozeLabel(mins)
  if mins >= 60 and mins % 60 == 0 then return (mins // 60) .. " hr" end
  return mins .. " min"
end

-- ---------- Shortcuts ----------
local function refreshShortcuts()
  M.shortcutsCheckedAt = os.time()
  local out = hs.execute("/usr/bin/shortcuts list")
  local names = {}
  for line in (out or ""):gmatch("[^\r\n]+") do names[trim(line)] = true end
  M.shortcutNames = names
end

local function hasShortcut(name)
  if not name then return false end
  if next(M.shortcutNames) == nil then return true end   -- list failed: just try it
  return M.shortcutNames[name] == true
end

-- Runs one shortcut at a time. opts: clipboard = text to hand it, output = file path, done = fn(ok)
local function runQueue()
  if M.shortcutBusy or #M.shortcutQueue == 0 then return end
  local job = table.remove(M.shortcutQueue, 1)
  M.shortcutBusy = true

  local saved
  if job.clipboard then
    local ok, data = pcall(hs.pasteboard.readAllData)
    saved = ok and data or nil
    hs.pasteboard.setContents(job.clipboard)
  end

  local args = { "run", job.name }
  if job.output then table.insert(args, "--output-path"); table.insert(args, job.output) end

  local finished = false
  local function finish(ok)
    if finished then return end
    finished = true
    if M.shortcutWatch then M.shortcutWatch:stop() end
    if job.clipboard then   -- put your clipboard back
      if saved and next(saved) then
        if not pcall(hs.pasteboard.writeAllData, saved) then hs.pasteboard.clearContents() end
      else
        hs.pasteboard.clearContents()
      end
    end
    M.shortcutBusy = false
    if job.done then job.done(ok) end
    runQueue()
  end

  M.shortcutTask = hs.task.new("/usr/bin/shortcuts", function(code) finish(code == 0) end, args)
  if not (M.shortcutTask and M.shortcutTask:start()) then finish(false) return end
  M.shortcutWatch = hs.timer.doAfter(60, function()   -- a stuck shortcut can't block the rest
    if M.shortcutTask and M.shortcutTask:isRunning() then M.shortcutTask:terminate() end
  end)
end

local function runShortcut(name, opts)
  opts = opts or {}
  table.insert(M.shortcutQueue, { name = name, clipboard = opts.clipboard,
    output = opts.output, done = opts.done })
  runQueue()
end

-- Clipboard handed to "DayPlan to Structured": 3 lines = title, start, minutes
local function syncStructured(date)
  if not hasShortcut(M.structuredAddShortcut) then return end
  local d = loadStore().days[date]
  if not d or type(d.tasks) ~= "table" then return end
  for _, t in ipairs(d.tasks) do
    if t.state == "pending" and not t.synced then
      local name, due, mins = t.name, t.due, (t.minutes or M.defaultMinutes)
      runShortcut(M.structuredAddShortcut, {
        clipboard = name .. "\n" .. os.date("%B %d, %Y at %I:%M %p", due) .. "\n" .. mins,
        done = function(ok)
          if not ok then
            if not M.warnedStructured then
              M.warnedStructured = true
              hs.alert.show('Couldn\'t add to Structured. Check the "' .. M.structuredAddShortcut .. '" shortcut.', 5)
            end
            return
          end
          local s = loadStore()
          local dd = s.days[date]
          if dd and type(dd.tasks) == "table" then
            for _, x in ipairs(dd.tasks) do
              if x.name == name and x.due == due then x.synced = true end
            end
            saveStore(s)
          end
        end,
      })
    end
  end
end

local function startTimers(name)
  if hasShortcut(M.timerShortcut) then
    runShortcut(M.timerShortcut, { done = function(ok)
      if not ok then hs.alert.show("Clock timer didn't start. Is one already running? Cancel it and try again.", 5) end
    end })
  else
    hs.alert.show('No "' .. M.timerShortcut .. '" shortcut found, so no Clock timer.', 4)
  end
  if hasShortcut(M.structuredFocusShortcut) then
    runShortcut(M.structuredFocusShortcut, { clipboard = name, done = function(ok)
      if not ok then hs.alert.show("Structured focus timer didn't start.", 4) end
    end })
  end
end

-- "DayPlan Agenda" output lines:  E|2026-11-04|10:30 AM|Title     R|2026-11-04|Title
local function parseAgenda(txt)
  local items = {}
  for line in (txt or ""):gmatch("[^\r\n]+") do
    local kind, date, rest = line:match("^%s*([ER])%s*|%s*(%d%d%d%d%-%d%d%-%d%d)%s*|(.*)$")
    if kind == "E" then
      local time, title = rest:match("^(.-)|(.*)$")
      if time then table.insert(items, { kind = "E", date = date, time = trim(time), title = trim(title) }) end
    elseif kind == "R" then
      table.insert(items, { kind = "R", date = date, title = trim(rest) })
    end
  end
  return items
end

local function agendaText(items, date, label)
  if not items then return "" end
  local out = {}
  for _, it in ipairs(items) do
    if it.date == date and #out < 8 then
      if it.kind == "E" then table.insert(out, it.time .. "    " .. it.title)
      else table.insert(out, "☐   " .. it.title) end
    end
  end
  if #out == 0 then return label .. ": nothing on the calendar" end
  return label:upper() .. "'S CALENDAR\n" .. table.concat(out, "\n")
end

local function fetchAgenda(cb)
  if not hasShortcut(M.agendaShortcut) then cb(nil) return end
  os.remove(M.agendaFile)
  runShortcut(M.agendaShortcut, { output = M.agendaFile, done = function(ok)
    if not ok then cb(nil) return end
    local f = io.open(M.agendaFile, "r")
    if not f then cb(nil) return end
    local txt = f:read("a")
    f:close()
    cb(parseAgenda(txt))
  end })
end

-- ---------- motivation pics ----------
local IMAGE_EXT = { jpg = true, jpeg = true, png = true, heic = true, gif = true, webp = true, tiff = true }

-- every image in the folder, shuffled
local function listImages()
  if not M.imageFolder then return {} end
  local ok, iter, dirObj = pcall(hs.fs.dir, M.imageFolder)
  if not ok or not iter then return {} end
  local files = {}
  for name in iter, dirObj do
    local ext = name:match("%.([^%.]+)$")
    if ext and IMAGE_EXT[ext:lower()] and name:sub(1, 1) ~= "." then
      table.insert(files, M.imageFolder .. "/" .. name)
    end
  end
  for i = #files, 2, -1 do
    local j = math.random(i)
    files[i], files[j] = files[j], files[i]
  end
  if #files > 1 and files[1] == M.lastImage then files[1], files[2] = files[2], files[1] end
  return files
end

local function loadImage(path)
  if not path then return nil end
  return hs.image.imageFromPath(path)
end

local PIC_GAP = 14   -- points between pics

-- width / height of a pic (and whether we could read its size)
local function aspectOf(img)
  local ok, sz = pcall(function() return img:size() end)
  if ok and type(sz) == "table" and sz.w and sz.h and sz.w > 0 and sz.h > 0 then
    return sz.w / sz.h, true
  end
  return 1, false
end

-- Lay pics out in `nrows` rows inside `area` at their real shape: nothing gets cropped.
-- Each row spans the width; if that's too tall, everything shrinks to fit. Returns rects, area used.
local function justify(aspects, area, gap, nrows)
  local n, total = #aspects, 0
  for _, a in ipairs(aspects) do total = total + a end
  local target = total / nrows
  local rows, cur, curSum = {}, {}, 0
  for i, a in ipairs(aspects) do
    table.insert(cur, i)
    curSum = curSum + a
    local rowsLeft, itemsLeft = nrows - #rows - 1, n - i
    if rowsLeft > 0 and (curSum >= target * 0.95 or itemsLeft == rowsLeft) then
      table.insert(rows, cur)
      cur, curSum = {}, 0
    end
  end
  if #cur > 0 then table.insert(rows, cur) end

  local heights, sumH = {}, 0
  for r, row in ipairs(rows) do
    local sum = 0
    for _, i in ipairs(row) do sum = sum + aspects[i] end
    heights[r] = (area.w - gap * (#row - 1)) / sum
    sumH = sumH + heights[r]
  end
  local scale = math.min(1, (area.h - gap * (#rows - 1)) / sumH)
  local y = area.y + (area.h - (sumH * scale + gap * (#rows - 1))) / 2
  local rects, used = {}, 0
  for r, row in ipairs(rows) do
    local h = heights[r] * scale
    local rowW = gap * (#row - 1)
    for _, i in ipairs(row) do rowW = rowW + aspects[i] * h end
    local x = area.x + (area.w - rowW) / 2
    for _, i in ipairs(row) do
      local w = aspects[i] * h
      rects[i] = { x = x, y = y, w = w, h = h }
      used = used + w * h
      x = x + w + gap
    end
    y = y + h + gap
  end
  return rects, used
end

-- try 1 to 4 rows, keep whichever shows the pics biggest
local function fitPics(aspects, area, gap)
  local best, bestUsed = {}, -1
  for r = 1, math.min(#aspects, 4) do
    local rects, used = justify(aspects, area, gap, r)
    if used > bestUsed then best, bestUsed = rects, used end
  end
  return best
end

-- rounded pic exactly the size of rect r: 3 canvas elements (clip, image, reset). The image is the 2nd.
local function picElements(img, r, known)
  return
    { type = "rectangle", action = "clip", frame = r,
      roundedRectRadii = { xRadius = T.picRadius, yRadius = T.picRadius } },
    { type = "image", image = img, frame = r, imageAlignment = "center",
      imageScaling = known and "scaleToFit" or "scaleProportionally" },
    { type = "resetClip" }
end

-- dark gradient + warm glow: 2 canvas elements
local function backgroundElements()
  return
    { type = "rectangle", action = "fill", fillGradient = "linear",
      fillGradientColors = { T.bgBottom, T.bgTop }, fillGradientAngle = 90 },
    { type = "rectangle", action = "fill", fillGradient = "radial",
      fillGradientColors = { T.glow, { hex = "#FFD166", alpha = 0 } },
      fillGradientCenter = { x = 0.35, y = 0.45 } }
end
local BG_COUNT = 2

-- ---------- overlay ----------
local function closeOverlay()
  for _, c in ipairs(M.canvases) do c:delete() end
  M.canvases = {}
  M.canvasAreas = {}
  if M.modal then M.modal:exit(); M.modal = nil end
  if M.waitTimer then M.waitTimer:stop(); M.waitTimer = nil end
  M.mode = nil
  M.hasImage = false
  M.slotCount = 0
  M.imgEl = {}
  M.lineIndex = {}
end

local function canAct()
  return (hs.timer.secondsSinceEpoch() - (M.shownAt or 0)) >= (M.waitFor or M.minShowSeconds)
end

local function pct(n) return string.format("%.2f%%", n) end

local KEY_GLYPH = { ["return"] = "⏎", escape = "esc" }
local function keyHint(b)
  local k = b.keys and b.keys[1]
  if not k then return "" end
  return KEY_GLYPH[k] or k:upper()
end

local function imageHint()
  if #M.imgList <= M.slotCount then return "" end
  if M.slotCount == 1 then return string.format("←  →      %d / %d", M.imgPos, #M.imgList) end
  return "←  →     more pics"
end

-- where the pics go, in % of the screen, and how many
local PIC_AREAS = {
  side    = { x = 3, y = 5, w = 46, h = 88 },   -- one pic, text on the right
  collage = { x = 3, y = 5, w = 46, h = 88 },   -- a few pics, text on the right
  gallery = { x = 3, y = 4, w = 60, h = 90 },   -- celebration: lots of pics, text on the right
}
local function picCount(layout)
  if layout == "collage" then return M.collagePics end
  if layout == "gallery" then return M.celebratePics end
  return 1
end

local function absRect(p, fr)
  return { x = fr.w * p.x / 100, y = fr.h * p.y / 100, w = fr.w * p.w / 100, h = fr.h * p.h / 100 }
end

-- left/right arrows: next or previous pic (or set of pics)
local function flipImage(step)
  if not M.hasImage or #M.imgList <= M.slotCount then return end
  M.imgPos = (M.imgPos - 1 + step * M.slotCount) % #M.imgList + 1
  local imgs, aspects, known = {}, {}, {}
  for j = 1, M.slotCount do
    local img = loadImage(M.imgList[(M.imgPos - 1 + j - 1) % #M.imgList + 1])
    if not img then return end
    imgs[j] = img
    aspects[j], known[j] = aspectOf(img)
  end
  for ci, c in ipairs(M.canvases) do
    local rects = fitPics(aspects, M.canvasAreas[ci], PIC_GAP)
    for j = 1, M.slotCount do
      c[M.imgEl[j] - 1].frame = rects[j]
      local el = c[M.imgEl[j]]
      el.image = imgs[j]
      el.frame = rects[j]
      el.imageScaling = known[j] and "scaleToFit" or "scaleProportionally"
    end
  end
  M.lastImage = M.imgList[M.imgPos]
  for _, c in ipairs(M.canvases) do c[M.hintIndex].text = imageHint() end
end

function M.setLine(key, text)
  local idx = M.lineIndex[key]
  if not idx then return end
  for _, c in ipairs(M.canvases) do c[idx].text = text end
end

function M.lineText(key)
  local idx = M.lineIndex[key]
  return idx and M.canvases[1] and M.canvases[1][idx].text
end

-- lines:   { { text=, size=, color=, font=, y=, h=, key= }, ... }  y, h in % of the screen
--          font: "clock", "title", "body" (default) or "small"
-- buttons: { { label=, keys={...}, fn=, primary=, hidden= }, ... }  hidden = key only, no button
-- opts:    wait = seconds keys/clicks stay locked
--          layout = "side" (one pic on the left, default), "collage" (a few pics on the left),
--                   "gallery" (lots of pics on the left 60%, for the celebration)
--          Pics keep their real shape. They're arranged in rows to be as big as fits.
local function showOverlay(mode, lines, buttons, opts)
  opts = opts or {}
  closeOverlay()
  M.overlayId = M.overlayId + 1
  M.mode = mode
  M.shownAt = hs.timer.secondsSinceEpoch()
  M.waitFor = opts.wait or M.minShowSeconds
  M.modal = hs.hotkey.modal.new()

  for _, b in ipairs(buttons) do
    for _, key in ipairs(b.keys) do
      M.modal:bind({}, key, function() if canAct() then b.fn() end end)
    end
  end
  M.modal:bind({}, "left", function() flipImage(-1) end)
  M.modal:bind({}, "right", function() flipImage(1) end)

  -- pics
  local layout = PIC_AREAS[opts.layout] and opts.layout or "side"
  M.imgList, M.imgPos = listImages(), 1
  local imgs = {}
  for i = 1, math.min(picCount(layout), #M.imgList) do
    local img = loadImage(M.imgList[i])
    if img then table.insert(imgs, img) end
  end
  M.slotCount = #imgs
  M.hasImage = (#imgs > 0)
  if M.hasImage then M.lastImage = M.imgList[1] end
  local aspects, known = {}, {}
  for j, img in ipairs(imgs) do aspects[j], known[j] = aspectOf(img) end

  -- element numbering (same on every screen)
  local count = BG_COUNT
  M.imgEl = {}
  for j = 1, #imgs do M.imgEl[j] = count + 2; count = count + 3 end
  M.hintIndex = count + 1
  count = count + 1
  M.lineIndex = {}
  for i, l in ipairs(lines) do
    if l.key then M.lineIndex[l.key] = count + i end
  end

  -- text column
  local cx, cw = 6, 88
  if M.hasImage then
    if layout == "gallery" then cx, cw = 66, 31 else cx, cw = 52, 45 end
  end
  local areaP = PIC_AREAS[layout]

  local visible = {}
  for _, b in ipairs(buttons) do if not b.hidden then table.insert(visible, b) end end
  local gap = 1.4
  local nb = math.max(#visible, 1)
  local bw = math.min(19, (cw - (nb - 1) * gap) / nb)
  local x0 = cx + (cw - (#visible * bw + (#visible - 1) * gap)) / 2
  local btnText = (bw < 9) and 13 or ((bw < 11) and 15 or ((bw < 15) and 17 or 20))

  for _, screen in ipairs(hs.screen.allScreens()) do
    local fr = screen:fullFrame()
    local c = hs.canvas.new(fr)
    c:level(hs.canvas.windowLevels.screenSaver)
    c:behaviorAsLabels({ "canJoinAllSpaces", "stationary", "fullScreenAuxiliary" })
    c:appendElements(backgroundElements())

    local area = absRect(areaP, fr)
    local rects = fitPics(aspects, area, PIC_GAP)
    for j, img in ipairs(imgs) do c:appendElements(picElements(img, rects[j], known[j])) end
    table.insert(M.canvasAreas, area)

    c:appendElements({ type = "text", text = M.hasImage and imageHint() or "", textFont = T.fonts.small,
      textSize = 15, textColor = T.faint, textAlignment = "center",
      frame = { x = pct(areaP.x), y = pct(areaP.y + areaP.h + 1.2), w = pct(areaP.w), h = "3.5%" } })

    for _, l in ipairs(lines) do
      c:appendElements({ type = "text", text = l.text or "", textSize = l.size,
        textFont = T.fonts[l.font or "body"] or T.fonts.body,
        textColor = l.color or T.text, textAlignment = "center",
        frame = { x = pct(cx), y = pct(l.y), w = pct(cw), h = pct(l.h) } })
    end

    local bh = math.floor(fr.h * 0.064)
    local by = fr.h * 0.80
    for i, b in ipairs(visible) do
      local bx = fr.w * (x0 + (i - 1) * (bw + gap)) / 100
      local bwp = fr.w * bw / 100
      local id = "b" .. i
      c:appendElements(
        { type = "rectangle", action = b.primary and "fill" or "strokeAndFill", id = id, trackMouseDown = true,
          roundedRectRadii = { xRadius = bh / 2, yRadius = bh / 2 },
          fillColor = b.primary and T.accent or { white = 1, alpha = 0.07 },
          strokeColor = { white = 1, alpha = 0.22 }, strokeWidth = 1,
          frame = { x = bx, y = by, w = bwp, h = bh } },
        { type = "text", text = b.label .. "    " .. keyHint(b), textFont = T.fonts.title,
          textSize = btnText, id = id, trackMouseDown = true,
          textColor = b.primary and T.onAccent or T.text, textAlignment = "center",
          frame = { x = bx, y = by + (bh - btnText * 1.4) / 2, w = bwp, h = btnText * 1.6 } }
      )
    end

    c:mouseCallback(function(_, msg, id)
      if msg ~= "mouseDown" then return end
      local i = tonumber(tostring(id):match("^b(%d+)$") or "")
      if i and visible[i] and canAct() then
        M.clickTimer = hs.timer.doAfter(0.05, visible[i].fn)
      end
    end)
    c:show(0.25)
    table.insert(M.canvases, c)
  end
  M.modal:enter()
end

-- counts down on the line with key "wait"
local function startWaitCountdown(secs)
  if secs <= 0 then M.setLine("wait", "esc = back") return end
  local id, left = M.overlayId, secs
  M.setLine("wait", "unlocks in " .. left .. "s")
  M.waitTimer = hs.timer.doEvery(1, function()
    if M.overlayId ~= id then return end
    left = left - 1
    if left <= 0 then
      M.setLine("wait", "esc = back")
      if M.waitTimer then M.waitTimer:stop(); M.waitTimer = nil end
    else
      M.setLine("wait", "unlocks in " .. left .. "s")
    end
  end)
end

-- fills the line with key `key` once the calendar loads (blank if there's no agenda shortcut)
local function loadAgendaInto(key, date, label)
  local id = M.overlayId
  if not hasShortcut(M.agendaShortcut) then M.setLine(key, "") return end
  fetchAgenda(function(items)
    if M.overlayId ~= id then return end
    M.setLine(key, agendaText(items, date, label))
  end)
end

-- Dark screen with the time, a title, and a row of pics, shown behind typing boxes.
-- It sits at normal window level so the typing box can appear on top of it
-- (the menu bar and Dock stay visible because of that).
local function showBackdrop(title)
  closeOverlay()
  M.overlayId = M.overlayId + 1
  M.mode = "prompt"

  local files, pics = listImages(), {}
  for _, path in ipairs(files) do
    if #pics >= M.promptPics then break end
    local img = loadImage(path)
    if img then table.insert(pics, img) end
  end

  for _, screen in ipairs(hs.screen.allScreens()) do
    local fr = screen:fullFrame()
    local c = hs.canvas.new(fr)
    c:level(hs.canvas.windowLevels.normal)
    c:behaviorAsLabels({ "canJoinAllSpaces", "stationary", "fullScreenAuxiliary" })
    c:appendElements(backgroundElements())
    c:appendElements(
      { type = "text", text = fmtTime(os.time()), textFont = T.fonts.clock, textSize = 96,
        textColor = T.text, textAlignment = "center", frame = { x = "0%", y = "4%", w = "100%", h = "13%" } },
      { type = "text", text = title or "", textFont = T.fonts.body, textSize = 28, textColor = T.accent,
        textAlignment = "center", textLineBreak = "truncateTail",
        frame = { x = "6%", y = "18%", w = "88%", h = "6%" } }
    )
    if #pics > 0 then
      local aspects, known = {}, {}
      for j, img in ipairs(pics) do aspects[j], known[j] = aspectOf(img) end
      local rects = fitPics(aspects, absRect({ x = 3, y = 56, w = 94, h = 40 }, fr), PIC_GAP)
      for j, img in ipairs(pics) do c:appendElements(picElements(img, rects[j], known[j])) end
    end
    c:canvasMouseEvents(true, false, false, false)   -- swallow clicks
    c:mouseCallback(function() end)
    c:show(0.2)
    table.insert(M.canvases, c)
  end
end

-- Cover the screen, then run the typing box(es) in fn on top of it.
local function thenPrompt(fn, title)
  showBackdrop(title)
  M.delay = hs.timer.doAfter(0.15, function()
    hs.focus()
    fn()
    if M.mode == "prompt" then closeOverlay() end
  end)
end

-- ---------- actions ----------
local function promptFirstStep(idx, small)
  local s = loadStore()
  local t = dayOf(s, today()).tasks[idx]
  if not t then return end
  local title = small and ("2-minute version of: " .. t.name) or ("First step for: " .. t.name)
  local info = small
    and "Only commit to 2 minutes. What's the tiniest move? You can stop once it's done."
    or "The smallest action you can start in 2 minutes."
  local btn, step = hs.dialog.textPrompt(title, info, t.step or "", "Start", "Back")
  step = trim(step)
  if btn ~= "Start" or step == "" then
    if small then M.showNotNow(idx) else M.showTask(idx) end
    return
  end
  local now = os.time()
  t.step, t.state, t.startedAt = step, "started", now
  t.checkAt = now + (t.minutes or M.defaultMinutes) * 60   -- block-end check-in
  saveStore(s)
  startTimers(t.name)
  hs.alert.show("Go: " .. step, 3)
end

-- block end: "next step"
local function promptNextStep(idx)
  local s = loadStore()
  local t = dayOf(s, today()).tasks[idx]
  if not t then return end
  local btn, step = hs.dialog.textPrompt("Next step for: " .. t.name,
    "The smallest action you can start in 2 minutes.", "", "Start", "Back")
  step = trim(step)
  if btn ~= "Start" or step == "" then M.showBlockEnd(idx) return end
  t.step = step
  t.checkAt = os.time() + M.extendMinutes * 60
  saveStore(s)
  startTimers(t.name)
  hs.alert.show("Go: " .. step .. "   ·   checking back at " .. fmtTime(t.checkAt), 4)
end

local function extendBlock(idx)
  closeOverlay()
  local s = loadStore()
  local t = dayOf(s, today()).tasks[idx]
  if not t then return end
  t.checkAt = os.time() + M.extendMinutes * 60
  saveStore(s)
  hs.alert.show("Keep going. Checking back at " .. fmtTime(t.checkAt), 3)
end

local function snooze(idx, mins, reason)
  closeOverlay()
  local s = loadStore()
  local t = dayOf(s, today()).tasks[idx]
  if not t then return end
  t.due = os.time() + mins * 60
  t.warned = (mins <= M.headsUpMinutes)   -- short push: no heads-up. long push: heads-up again
  t.snoozes = (t.snoozes or 0) + 1
  if type(t.reasons) ~= "table" then t.reasons = {} end
  if reason and reason ~= "" then table.insert(t.reasons, reason) end
  saveStore(s)
  M.pendingReason = nil
  hs.alert.show("Pushed to " .. fmtTime(t.due) .. ": " .. t.name, 3)
end

local function promptReason(idx)
  local btn, why = hs.dialog.textPrompt("What's stopping you right now?",
    'Like "in class" or "at the gym". If the real answer is "don\'t feel like it", go back and do 2 minutes.',
    "", "Next", "Back")
  why = trim(why)
  if btn ~= "Next" or why == "" then M.showNotNow(idx) return end
  M.pendingReason = why
  M.showSnoozePick(idx)
end

local function promptSnooze(idx)
  local btn, txt = hs.dialog.textPrompt("Push it how long?",
    'Minutes, like "45". Or hours, like "1.5h".', "", "Push", "Back")
  local mins = parseLength(txt or "")
  if btn ~= "Push" or not mins then M.showSnoozePick(idx) return end
  snooze(idx, mins, M.pendingReason)
end

-- move a task to the next day at a time you type. back() if cancelled, after() once moved.
local function promptMove(fromDate, idx, back, after)
  local t = dayOf(loadStore(), fromDate).tasks[idx]
  if not t then return end
  local toDate = dateAdd(fromDate, 1)
  local default = fmtTime(t.due) .. " " .. (t.minutes or M.defaultMinutes) .. "m"
  local btn, txt = hs.dialog.textPrompt("When on " .. prettyDate(toDate) .. "?",
    'A start time, and a length if you want: "10am" or "2pm 45m".', default, "Move", "Back")
  if btn ~= "Move" then back() return end
  local h, m, rest = parseClock(txt or "")
  if not h then
    hs.alert.show('Couldn\'t read the time. Try "10am" or "2pm 45m".', 3)
    back()
    return
  end
  local mins = parseLength(rest) or t.minutes or M.defaultMinutes

  local s = loadStore()
  local from = dayOf(s, fromDate).tasks[idx]
  from.state = "moved"
  local to = dayOf(s, toDate)
  local due = timeOn(toDate, h, m)
  table.insert(to.tasks, { name = from.name, due = due, minutes = mins, step = from.step or "",
    state = "pending", snoozes = 0, reasons = {}, warned = false, synced = false })
  table.sort(to.tasks, function(a, b) return a.due < b.due end)
  saveStore(s)
  hs.alert.show("Moved to " .. prettyDate(toDate) .. ", " .. fmtTime(due) .. ": " .. from.name, 3)
  syncStructured(toDate)
  if after then after() end
end

local function editStep()
  local s = loadStore()
  local d = dayOf(s, today())
  local idx = activeIndex(d)
  if not idx then return end
  local t = d.tasks[idx]
  local btn, step = hs.dialog.textPrompt("Next step for: " .. t.name,
    "The smallest action you can start in 2 minutes.", t.step or "", "Save", "Cancel")
  step = trim(step)
  if btn == "Save" and step ~= "" then
    t.step = step
    saveStore(s)
    hs.alert.show("Next step: " .. step, 3)
  end
end

-- mark done, then celebrate
local function finishTask(date, idx)
  closeOverlay()
  setState(date, idx, "done")
  M.celebrate(date, idx)
end

local function markDone()
  local idx = activeIndex(dayOf(loadStore(), today()))
  if not idx then closeOverlay() return end
  finishTask(today(), idx)
end

local function finishReview(date)
  local s = loadStore()
  dayOf(s, date).reviewed = true
  saveStore(s)
  M.reviewSnoozeUntil = nil
  closeOverlay()
  M.afterReview = hs.timer.doAfter(1, function() if M.tick then M.tick() end end)
end

-- Plan a day: one box per task. Run it through M.planDay so the backdrop shows.
function M.plan(date)
  date = date or today()
  M.planNextAsk = os.time() + 3600
  local d = dayOf(loadStore(), date)
  local old = {}
  for _, t in ipairs(d.tasks) do old[t.name] = t end
  local label = dayLabel(date)

  local new, i = {}, 1
  hs.focus()
  while i <= M.maxTasks do
    local prev = d.tasks[i]
    local default = prev and (fmtTime(prev.due) .. " " .. prev.name .. " " ..
      (prev.minutes or M.defaultMinutes) .. "m") or ""
    local okLabel = (i < M.maxTasks) and "Next" or "Save"
    local btn, text = hs.dialog.textPrompt(string.format("Task %d of %d for %s", i, M.maxTasks, label),
      'Time + task + length, like "4pm Study GRE 3h" or "10:30am CS160 PRD 45m".\n' ..
      "Leave it empty and press Enter when you're done.",
      default, okLabel, "Cancel")
    if btn ~= okLabel then return end
    text = trim(text)
    if text == "" then
      if not prev then break end   -- nothing left to add: save
      i = i + 1                     -- you cleared an old task: drop it, keep going
    else
      local h, m, rest = parseClock(text)
      local name, mins
      if h then name, mins = splitLength(rest) end
      if not h or not name or name == "" then
        hs.alert.show('Couldn\'t read that. Try "4pm Study GRE 3h".', 3)
      else
        if not mins then
          local b2, len = hs.dialog.textPrompt("How long for: " .. name .. "?",
            'Like "45m" or "1.5h".', M.defaultMinutes .. "m", "OK", "Skip")
          mins = (b2 == "OK" and parseLength(len or "")) or M.defaultMinutes
        end
        local due = timeOn(date, h, m)
        local o = old[name] or {}
        local same = (o.due == due and o.minutes == mins)
        table.insert(new, { name = name, due = due, minutes = mins, step = o.step or "",
          state = o.state or "pending", startedAt = o.startedAt, checkAt = o.checkAt,
          snoozes = o.snoozes or 0, reasons = o.reasons or {},
          warned = same and (o.warned or false) or false,
          synced = same and (o.synced or false) or false })
        i = i + 1
      end
    end
  end

  table.sort(new, function(a, b) return a.due < b.due end)
  local s = loadStore()
  dayOf(s, date).tasks = new
  saveStore(s)
  M.planNextAsk = os.time() + 3 * 3600

  if #new == 0 then
    hs.alert.show("Plan cleared for " .. label, 2)
  else
    local parts = {}
    for _, t in ipairs(new) do table.insert(parts, fmtTime(t.due) .. " " .. t.name) end
    hs.alert.show(label:gsub("^%l", string.upper) .. ": " .. table.concat(parts, "   |   "), 4)
  end
  syncStructured(date)
end

function M.planDay(date)
  date = date or today()
  thenPrompt(function() M.plan(date) end, "Plan " .. dayLabel(date))
end

-- ---------- screens ----------
local function clockLine(size, y, h)
  return { text = fmtTime(os.time()), font = "clock", size = size, y = y, h = h, key = "clock" }
end

function M.showTask(idx)
  local d = dayOf(loadStore(), today())
  local t = d.tasks[idx]
  if not t or t.state ~= "pending" then return end
  local lines = {
    clockLine(124, 7, 17),
    { text = string.format("TASK %d OF %d    ·    %s    ·    %s", idx, #d.tasks, fmtTime(t.due),
        fmtLen(t.minutes or M.defaultMinutes)), font = "small", size = 17, color = T.faint, y = 27, h = 4 },
    { text = t.name, key = "name", font = "title", size = 60, y = 33, h = 24 },
  }
  if (t.snoozes or 0) > 0 then
    table.insert(lines, { text = "pushed " .. t.snoozes .. "x already", font = "small", size = 20,
      color = T.dim, y = 61, h = 5 })
  end
  showOverlay("task", lines, {
    { label = "Start", keys = { "return" }, primary = true,
      fn = function() thenPrompt(function() promptFirstStep(idx, false) end, "First step for: " .. t.name) end },
    { label = "Not now", keys = { "s" }, fn = function() M.showNotNow(idx) end },
  })
end

function M.showNotNow(idx)
  local d = dayOf(loadStore(), today())
  local t = d.tasks[idx]
  if not t then return end
  local pushed = t.snoozes or 0
  local maxed = pushed >= M.maxSnoozes
  local sub = ""
  if maxed then sub = "Start it, move it to tomorrow, or drop it."
  elseif pushed > 0 then sub = "pushed " .. pushed .. "x today" end

  local lines = {
    clockLine(88, 5, 13),
    { text = maxed and ("Pushed " .. pushed .. " times already.") or "Can't right now, or don't want to?",
      key = "question", font = "title", size = 40, color = T.accent, y = 21, h = 12 },
    { text = "“" .. randomTip(M.startTips) .. "”", key = "tip", font = "body", size = 29, y = 36, h = 21 },
    { text = sub, font = "small", size = 20, color = T.dim, y = 60, h = 5 },
    { text = "", key = "wait", font = "small", size = 17, color = T.faint, y = 69, h = 4 },
  }
  local buttons = {
    { label = "Just 2 min", keys = { "return" }, primary = true,
      fn = function() thenPrompt(function() promptFirstStep(idx, true) end, "Just 2 minutes: " .. t.name) end },
  }
  if maxed then
    table.insert(buttons, { label = "Tomorrow", keys = { "t" },
      fn = function()
        thenPrompt(function() promptMove(today(), idx, function() M.showNotNow(idx) end) end,
          "Move to tomorrow: " .. t.name)
      end })
    table.insert(buttons, { label = "Drop it", keys = { "x" },
      fn = function()
        setState(today(), idx, "dropped")
        closeOverlay()
        hs.alert.show("Dropped: " .. t.name, 3)
      end })
  else
    table.insert(buttons, { label = "Busy / out", keys = { "b" },
      fn = function() thenPrompt(function() promptReason(idx) end, "Why not now: " .. t.name) end })
  end
  table.insert(buttons, { hidden = true, keys = { "escape" }, fn = function() M.showTask(idx) end })

  showOverlay("notnow", lines, buttons, { wait = M.notNowWaitSeconds })
  startWaitCountdown(M.notNowWaitSeconds)
end

function M.showSnoozePick(idx)
  local d = dayOf(loadStore(), today())
  local t = d.tasks[idx]
  if not t then return end
  local lines = {
    clockLine(110, 7, 17),
    { text = "Push it how long?", font = "title", size = 48, color = T.accent, y = 29, h = 11 },
    { text = t.name, key = "name", font = "body", size = 32, y = 42, h = 10 },
    { text = "reason: " .. (M.pendingReason or ""), font = "small", size = 20, color = T.dim, y = 57, h = 6 },
    { text = "esc = back", font = "small", size = 17, color = T.faint, y = 69, h = 4 },
  }
  local buttons = {}
  for k, mins in ipairs(M.snoozes) do
    table.insert(buttons, { label = snoozeLabel(mins), keys = { tostring(k) },
      fn = function() snooze(idx, mins, M.pendingReason) end })
  end
  local ck = #M.snoozes + 1
  table.insert(buttons, { label = "Custom", keys = { tostring(ck) },
    fn = function() thenPrompt(function() promptSnooze(idx) end, "Push: " .. t.name) end })
  table.insert(buttons, { label = "Tomorrow", keys = { "t" },
    fn = function()
      thenPrompt(function() promptMove(today(), idx, function() M.showSnoozePick(idx) end) end,
        "Move to tomorrow: " .. t.name)
    end })
  table.insert(buttons, { hidden = true, keys = { "escape" }, fn = function() M.showTask(idx) end })
  showOverlay("snooze", lines, buttons)
end

-- the planned length is up: done / still going / next step
function M.showBlockEnd(idx)
  local d = dayOf(loadStore(), today())
  local t = d.tasks[idx]
  if not t or t.state ~= "started" then return end
  local started = t.startedAt or t.due
  local lines = {
    clockLine(120, 6, 17),
    { text = string.format("BLOCK UP    ·    planned %s    ·    started %s",
        fmtLen(t.minutes or M.defaultMinutes), fmtTime(started)),
      font = "small", size = 17, color = T.faint, y = 25, h = 4 },
    { text = t.name, key = "name", font = "title", size = 56, y = 31, h = 18 },
    { text = ((t.step or "") ~= "") and ("last step:  " .. t.step) or "", font = "small", size = 20,
      color = T.dim, y = 51, h = 6 },
    { text = "How's it going?", key = "question", font = "body", size = 32, color = T.accent, y = 60, h = 8 },
  }
  showOverlay("blockend", lines, {
    { label = "Done", keys = { "d" }, primary = true, fn = function() finishTask(today(), idx) end },
    { label = "Still going", keys = { "g" }, fn = function() extendBlock(idx) end },
    { label = "Next step", keys = { "n" },
      fn = function() thenPrompt(function() promptNextStep(idx) end, "Next step for: " .. t.name) end },
  })
end

-- reward screen: pics fill the screen
function M.celebrate(date, idx)
  local d = dayOf(loadStore(), date)
  local t = d.tasks[idx]
  if not t then return end
  local spent = t.startedAt and fmtDur((t.doneAt or os.time()) - t.startedAt) or nil
  local ni = (date == today()) and nextIndex(d) or nil
  local lines = {
    { text = "✓   DONE", font = "title", size = 24, color = T.accent, y = 12, h = 5 },
    { text = t.name, key = "name", font = "title", size = 46, y = 19, h = 20 },
    { text = spent and (spent .. " of focus") or "", key = "spent", font = "body", size = 24, color = T.dim, y = 41, h = 5 },
    { text = string.format("%d of %d done today", doneCount(d), #d.tasks), key = "count", font = "small",
      size = 19, color = T.dim, y = 47, h = 4 },
    { text = randomTip(M.celebrateLines), key = "cheer", font = "body", size = 30, color = T.accent, y = 54, h = 13 },
    { text = ni and ("up next:  " .. d.tasks[ni].name .. "  at  " .. fmtTime(d.tasks[ni].due)) or "",
      font = "small", size = 18, color = T.faint, y = 69, h = 7 },
  }
  showOverlay("celebrate", lines, {
    { label = "Keep going", keys = { "return", "escape" }, primary = true, fn = closeOverlay },
  }, { layout = "gallery" })
  playSound(M.celebrateSound)
end

function M.showCheckin()
  local d = dayOf(loadStore(), today())
  local ai = activeIndex(d)
  local lines = { clockLine(150, 7, 22) }
  local buttons = {
    { label = "Close", keys = { "return", "escape" }, primary = true, fn = closeOverlay },
  }

  if ai then
    local t = d.tasks[ai]
    table.insert(lines, { text = "NOW    ·    " .. t.name:upper(), font = "small", size = 20, color = T.faint, y = 33, h = 5 })
    table.insert(lines, { text = ((t.step ~= "" and t.step) or "?"), key = "step",
      font = "title", size = 48, color = T.accent, y = 40, h = 18 })
    table.insert(buttons, { label = "Edit step", keys = { "e" },
      fn = function() thenPrompt(editStep, "Next step for: " .. t.name) end })
    table.insert(buttons, { label = "Done", keys = { "d" }, fn = markDone })
  else
    local ni = nextIndex(d)
    if ni then
      local t = d.tasks[ni]
      table.insert(lines, { text = "NEXT", font = "small", size = 20, color = T.faint, y = 33, h = 5 })
      table.insert(lines, { text = t.name, key = "step", font = "title", size = 48, color = T.accent, y = 39, h = 12 })
      table.insert(lines, { text = string.format("at %s   ·   in %s", fmtTime(t.due),
        fmtDur(t.due - os.time())), font = "body", size = 26, color = T.dim, y = 52, h = 6 })
    else
      local msg = (#d.tasks == 0) and "No plan for today" or "Nothing left for today"
      table.insert(lines, { text = msg, font = "body", size = 42, color = T.dim, y = 40, h = 12 })
    end
    table.insert(buttons, { label = "Plan day", keys = { "n" }, fn = function() M.planDay(today()) end })
  end

  if #d.tasks > 0 then
    table.insert(lines, { text = taskListText(d), key = "list", font = "small", size = 18, color = T.dim, y = 61, h = 17 })
  end
  showOverlay("checkin", lines, buttons)
end

function M.showPlanPrompt()
  showOverlay("plan", {
    clockLine(124, 9, 18),
    { text = "Plan today's tasks", font = "title", size = 58, color = T.accent, y = 36, h = 13 },
    { text = "Up to " .. M.maxTasks .. ", each with a time and a length.", font = "body", size = 26,
      color = T.dim, y = 51, h = 6 },
  }, {
    { label = "Plan now", keys = { "return" }, primary = true, fn = function() M.planDay(today()) end },
    { label = "Later", keys = { "escape" }, fn = closeOverlay },
  })
end

function M.showMorning()
  local s = loadStore()
  local td = today()
  s.morningShown = td
  local d = dayOf(s, td)
  saveStore(s)
  M.planNextAsk = os.time() + 3600

  local has = #d.tasks > 0
  local lines = {
    clockLine(112, 3, 16),
    { text = prettyDate(td):upper(), font = "small", size = 18, color = T.faint, y = 19.5, h = 4 },
    { text = "“" .. randomTip(M.morningTips) .. "”", key = "tip", font = "body", size = 26,
      color = T.accent, y = 25, h = 9 },
    { text = has and taskListText(d, "TODAY") or "No plan yet.", key = "plan",
      font = has and "body" or "title", size = has and 21 or 40, y = 36, h = 21 },
    { text = "", key = "agenda", font = "small", size = 17, color = T.dim, y = 58, h = 20 },
  }
  local buttons
  if has then
    buttons = {
      { label = "Let's go", keys = { "return" }, primary = true, fn = function()
          local s2 = loadStore()
          dayOf(s2, td).confirmed = true
          saveStore(s2)
          closeOverlay()
          local d2 = dayOf(s2, td)
          local ni = nextIndex(d2)
          hs.alert.show(ni and ("First up: " .. d2.tasks[ni].name .. " at " .. fmtTime(d2.tasks[ni].due))
            or "Plan locked in.", 4)
          syncStructured(td)
        end },
      { label = "Edit plan", keys = { "e" }, fn = function() M.planDay(td) end },
    }
  else
    buttons = {
      { label = "Plan today", keys = { "return" }, primary = true, fn = function() M.planDay(td) end },
      { label = "Later", keys = { "escape" }, fn = closeOverlay },
    }
  end
  showOverlay("morning", lines, buttons, { layout = "collage" })
  loadAgendaInto("agenda", td, "Today")
end

-- Night review. missed = it's a past day you never closed out.
function M.showReviewIntro(date, missed)
  local d = dayOf(loadStore(), date)
  local open = openCount(d)
  local nextDate = dateAdd(date, 1)
  local summary = (#d.tasks == 0) and "no tasks were planned"
    or string.format("%d of %d done", doneCount(d), #d.tasks)
  local lines = {
    clockLine(112, 3, 16),
    { text = (missed and "You didn't close out " or "Close out ") .. prettyDate(date),
      key = "title", font = "title", size = 32, color = T.accent, y = 20, h = 7 },
    { text = summary, font = "small", size = 20, color = T.dim, y = 27, h = 5 },
    { text = taskListText(d), key = "list", font = "body", size = 21, y = 34, h = 22 },
    { text = "", key = "agenda", font = "small", size = 17, color = T.dim, y = 57, h = 21 },
  }
  local buttons = {}
  if open > 0 then
    table.insert(buttons, { label = "Review " .. open .. " open", keys = { "return" }, primary = true,
      fn = function() M.reviewNext(date, missed) end })
  else
    table.insert(buttons, { label = "Done", keys = { "return" }, primary = true,
      fn = function() finishReview(date) end })
    if not missed then
      table.insert(buttons, { label = "Plan tomorrow", keys = { "n" },
        fn = function() finishReview(date); M.planDay(nextDate) end })
    end
  end
  table.insert(buttons, { label = "Later", keys = { "escape" },
    fn = function() M.reviewSnoozeUntil = os.time() + 1800; closeOverlay() end })
  showOverlay("review", lines, buttons, { layout = "collage" })
  if not missed then loadAgendaInto("agenda", nextDate, "Tomorrow") else M.setLine("agenda", "") end
end

function M.reviewNext(date, missed)
  local d = dayOf(loadStore(), date)
  for i, t in ipairs(d.tasks) do
    if t.state == "pending" or t.state == "started" then
      M.showReviewTask(date, i, missed)
      return
    end
  end
  M.showReviewEnd(date, missed)
end

function M.showReviewTask(date, idx, missed)
  local d = dayOf(loadStore(), date)
  local t = d.tasks[idx]
  if not t then M.reviewNext(date, missed) return end
  local status = (t.state == "started")
    and ("started at " .. fmtTime(t.startedAt or t.due) .. (((t.step or "") ~= "") and ("    ·    step: " .. t.step) or ""))
    or "not started"
  if (t.snoozes or 0) > 0 then status = status .. "    ·    pushed " .. t.snoozes .. "x" end
  local reasons = (type(t.reasons) == "table" and #t.reasons > 0)
    and ("why: " .. table.concat(t.reasons, ", ")) or ""

  showOverlay("review", {
    clockLine(104, 5, 15),
    { text = "Did it happen?", font = "title", size = 40, color = T.accent, y = 23, h = 9 },
    { text = t.name, key = "name", font = "title", size = 50, y = 34, h = 16 },
    { text = status, font = "small", size = 20, color = T.dim, y = 52, h = 6 },
    { text = reasons, font = "small", size = 18, color = T.faint, y = 59, h = 8 },
  }, {
    { label = "Done", keys = { "d" }, primary = true,
      fn = function() setState(date, idx, "done"); M.reviewNext(date, missed) end },
    { label = "Tomorrow", keys = { "t" },
      fn = function()
        thenPrompt(function()
          promptMove(date, idx,
            function() M.showReviewTask(date, idx, missed) end,
            function() M.reviewNext(date, missed) end)
        end, "Move to " .. prettyDate(dateAdd(date, 1)) .. ": " .. t.name)
      end },
    { label = "Drop", keys = { "x" },
      fn = function() setState(date, idx, "dropped"); M.reviewNext(date, missed) end },
  }, { layout = "collage" })
end

function M.showReviewEnd(date, missed)
  local d = dayOf(loadStore(), date)
  local nextDate = dateAdd(date, 1)
  local buttons = {
    { label = "Done", keys = { "return", "escape" }, primary = true, fn = function() finishReview(date) end },
  }
  if not missed then
    table.insert(buttons, { label = "Plan tomorrow", keys = { "n" },
      fn = function() finishReview(date); M.planDay(nextDate) end })
  end
  showOverlay("review", {
    clockLine(112, 3, 16),
    { text = "Day closed", key = "title", font = "title", size = 42, color = T.accent, y = 20, h = 9 },
    { text = string.format("%d of %d done", doneCount(d), #d.tasks), font = "small", size = 20,
      color = T.dim, y = 29, h = 5 },
    { text = taskListText(d), key = "list", font = "body", size = 21, y = 35, h = 21 },
    { text = "", key = "agenda", font = "small", size = 17, color = T.dim, y = 57, h = 21 },
  }, buttons, { layout = "collage" })
  if not missed then loadAgendaInto("agenda", nextDate, "Tomorrow") end
end

-- ---------- loop ----------
-- morning and night screens. Returns true if one was shown.
local function checkSpecial(s, td, now, quiet)
  if now >= (M.reviewSnoozeUntil or 0) then
    -- a past day you never closed out (only if it still has open tasks)
    local yd = dateAdd(td, -1)
    local y = s.days[yd]
    if y and not y.reviewed then
      if type(y.tasks) == "table" and openCount(y) > 0 then
        M.showReviewIntro(yd, true)
        return true
      end
      y.reviewed = true
      saveStore(s)
    end
    -- tonight's review
    local d = s.days[td]
    if now >= reviewTime(td) and not (d and d.reviewed) then
      M.showReviewIntro(td, false)
      return true
    end
  end
  -- morning
  if s.morningShown ~= td and not quiet and tonumber(os.date("%H", now)) >= M.morningHour
     and now < reviewTime(td) then
    M.showMorning()
    return true
  end
  return false
end

local function tick()
  local now = os.time()
  if M.pausedUntil and now >= M.pausedUntil then M.pausedUntil = nil end
  if M.pausedUntil then return end
  if now - (M.shortcutsCheckedAt or 0) > 600 then refreshShortcuts() end

  local s = loadStore()
  local td = today()
  local d = s.days[td]
  if d and type(d.tasks) ~= "table" then d = nil end
  local quiet = isQuiet(now)

  -- spoken heads-up before each task (once per task)
  if d and not quiet and M.headsUpMinutes > 0 then
    for _, t in ipairs(d.tasks) do
      if t.state == "pending" and not t.warned and now < t.due
         and now >= t.due - M.headsUpMinutes * 60 then
        t.warned = true
        saveStore(s)
        local mins = math.max(1, math.floor((t.due - now) / 60 + 0.5))
        local unit = (mins == 1) and " minute" or " minutes"
        if not M.muted then
          M.voice = M.voice or hs.speech.new()
          M.voice:speak(t.name .. " in " .. mins .. unit)
        end
        hs.alert.show(t.name .. " in " .. mins .. " min (" .. fmtTime(t.due) .. ")", 5)
        break
      end
    end
  end

  if M.mode and M.mode ~= "checkin" then return end
  if isLocked() then return end

  if checkSpecial(s, td, now, quiet) then return end
  if quiet then return end

  if d then
    -- block-end check-ins for tasks you started
    for i, t in ipairs(d.tasks) do
      if t.state == "started" and t.checkAt and now >= t.checkAt then
        M.showBlockEnd(i)
        return
      end
    end
    -- task reminders (also fires after wake if one was missed)
    for i, t in ipairs(d.tasks) do
      if t.state == "pending" and now >= t.due then
        M.showTask(i)
        return
      end
    end
  end

  -- still no plan
  if M.planPromptHour and not (d and #d.tasks > 0) and now >= M.planNextAsk
     and tonumber(os.date("%H", now)) >= M.planPromptHour then
    M.planNextAsk = now + 3600
    M.showPlanPrompt()
    return
  end

  -- check-ins
  if M.checkinMinutes > 0 then
    local stamp = os.date("%Y-%m-%d %H:%M", now)
    if tonumber(os.date("%M", now)) % M.checkinMinutes == 0 and stamp ~= M.lastCheckin then
      M.lastCheckin = stamp
      M.showCheckin()
    end
  end
end
M.tick = tick

-- ---------- hotkeys ----------
local HYPER = { "ctrl", "alt", "cmd" }
hs.hotkey.bind(HYPER, "N", function() M.planDay(today()) end)
hs.hotkey.bind({ "ctrl", "alt", "cmd", "shift" }, "N", function() M.planDay(dateAdd(today(), 1)) end)
hs.hotkey.bind(HYPER, "T", function() M.showCheckin() end)
hs.hotkey.bind(HYPER, "O", function() M.showMorning() end)
hs.hotkey.bind(HYPER, "R", function() M.showReviewIntro(today(), false) end)
hs.hotkey.bind(HYPER, "P", function()
  if M.pausedUntil then
    M.pausedUntil = nil
    hs.alert.show("Planner back on", 2)
  else
    M.pausedUntil = nextMorning()
    closeOverlay()
    hs.alert.show("Paused until " .. fmtTime(M.pausedUntil) .. ". ctrl+alt+cmd+P to resume.", 3)
  end
end)
hs.hotkey.bind(HYPER, "M", function()
  M.muted = not M.muted
  hs.settings.set("dayplan.muted", M.muted)
  if M.muted and M.voice then M.voice:stop() end
  hs.alert.show(M.muted and "Muted. Overlays still on." or "Sound on", 2)
end)

-- opening the laptop: check for the morning / night screens right away
M.watcher = hs.caffeinate.watcher.new(function(ev)
  local w = hs.caffeinate.watcher
  if ev == w.screensDidUnlock or ev == w.systemDidWake or ev == w.screensDidWake
     or ev == w.screensaverDidStop then
    M.wakeTimer = hs.timer.doAfter(3, tick)
  end
end)
M.watcher:start()

M.ticker  = hs.timer.doEvery(20, tick)
M.startup = hs.timer.doAfter(2, function() refreshShortcuts(); tick() end)
hs.alert.show("Planner loaded. ctrl+alt+cmd+N to plan today.", 3)
