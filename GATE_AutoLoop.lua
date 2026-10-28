--[=====[
[[SND Metadata]]
author: forgefk
version: 0.3.0
description: 金碟遊樂園 G.A.T.E. 自動循環（繁中客戶端）。每 20 分鐘找「活動解說員」問目前的 G.A.T.E.，傳送到現場、跟現場人物報名，場內交給 Saucy 自動玩。Saucy 支援：必中一閃快刀斬魔、暴風倖存者、空軍裝甲駕駛員。兩場之間可用 AutoRetainer 收雇員
plugin_dependencies:
- vnavmesh
function_chat_filters:
  OnChatMessage:
    message_regex: "主辦的活動「|舞臺活動的報名已經截止"
configs:
  JoinSlice:
    default: true
    description: 參加「必中一閃快刀斬魔」（Slice is Right）。要在 Saucy 開啟這個模組和「自動移動」，閃避需要 BossMod
  JoinWind:
    default: true
    description: 參加「暴風倖存者」（Any Way the Wind Blows）。要在 Saucy 開啟這個模組和「自動移動（vnavmesh）」
  JoinAirForce:
    default: true
    description: 參加「空軍裝甲駕駛員」（Air Force One）。要在 Saucy 開啟這個模組
  JoinLeap:
    default: false
    description: 參加「登高跳跳樂大挑戰」（Leap of Faith）。Saucy 不支援，只會站著等時間到，拿參加獎
  JoinCliff:
    default: false
    description: 參加「搶救小雛鳥大作戰」（Cliffhanger）。Saucy 不支援
  MaxGates:
    default: 0
    description: 參加幾場後停止，0 = 無限循環
    min: 0
    max: 9999
  PrepareSeconds:
    default: 60
    description: 下一場開始前幾秒走到活動解說員旁邊等
    min: 0
    max: 1200
  JoinWindow:
    default: 300
    description: 每場開始後幾秒內還會去報名（解說員說報名結束會提早放棄）
    min: 0
    max: 1200
  RetryInterval:
    default: 8
    description: 對話沒反應時，隔幾秒再跟 NPC 對話一次
    min: 1
    max: 120
  Retainers:
    default: true
    description: 兩場之間用 AutoRetainer 收雇員（金碟遊樂園乙太之光廣場的傳喚鈴）。要裝 AutoRetainer 並設定好雇員要做的事
  UseSprint:
    default: true
    description: 走路時使用衝刺
  EchoLogs:
    default: "All"
    description: 日誌層級 All / Errors / None
[[End Metadata]]
--]=====]

import("System.Numerics")

--[[
流程
  WAIT_SLOT  等下一場（:00 / :20 / :40，地球時間）。開始前 PrepareSeconds 秒走到最近的「活動解說員」。
             空檔夠長、雇員探險回來了 → RETAINERS
  RETAINERS  走到傳喚鈴、打開雇員清單、交給 AutoRetainer（/ays e），處理完關掉清單
  GO_KEEPER  走到活動解說員旁邊，等到開場
  ASK_KEEPER 跟解說員對話：「現在正在開展「X」活動！」→ 認出是哪個 G.A.T.E. →「要前往活動的舉辦地點嗎？」選是
  WARPING    等傳送完成
  JOIN       找現場報名的 NPC 對話、確認報名 → 回 WAIT_SLOT（場內由 Saucy 處理；空軍裝甲的任務確認框由 WAIT_SLOT 按）
文字都取自繁中客戶端資料（custom/002/CmnGscGATENotice_00242、GoldSaucerTextData、ENpcResident）
]]

-------------------------------------------------------------------------------
-- 1. 常數與設定
-------------------------------------------------------------------------------

local SAUCER_TERRITORY = 144
local SAUCER_AETHERYTE = 62     -- 金碟遊樂園大水晶（Aetheryte 表）
local MGP_ITEM_ID      = 29     -- 金碟幣
local SLOT_SECONDS     = 20 * 60

-- 活動解說員（ENpcResident 1011080 / 1011084 / 1011093）的位置，取自 Level 表。
-- G.A.T.E. 進行中跟他說話會問要不要直接傳送到舉辦地點
local KEEPER_NAME = "活動解說員"
local KEEPER_POSITIONS = {
    Vector3(21.55, 4.00, 39.93),
    Vector3(-12.51, 3.25, -73.15),
    Vector3(44.19, -5.00, -16.66),
}

-- 解說員的台詞（CmnGscGATENotice）
local TEXT_CLOSED     = "報名已經結束"          -- 現在正在開展「X」活動！現在報名已經結束…
local TEXT_IN_SESSION = "現在正在開展"          -- 現在正在開展「X」活動！客人您也請踴躍參加吧！
local TEXT_NEXT       = "下一次G.A.T.E.事件"     -- 下一次G.A.T.E.事件將於X點Y分（地球時間）在Z出現
local TEXT_UPCOMING   = "接下來我們將在開展"     -- 還沒開始
local TEXT_WARP       = "前往活動的舉辦地點"     -- 要前往活動的舉辦地點嗎？

-- 各 G.A.T.E. 的名稱（GoldSaucerTextData）與現場報名的 NPC（ENpcResident，稱號「G.A.T.E.事件」）
-- markers：現場 NPC 台詞／確認框裡只有這一場會出現的字（GoldSaucerTalk）。
-- 仙人掌怪導覽員同時負責空軍裝甲和登高跳跳樂，只能靠這些字或來賓接待員的公告分辨
local GATES = {
    { key = "slice", name = "必中一閃快刀斬魔", npcs = { "保鑣的小弟" }, cfg = "JoinSlice", stage = true,
      markers = { "保鑣老師" } },
    { key = "wind",  name = "暴風倖存者",       npcs = { "傲慢的咒術士" }, cfg = "JoinWind", stage = true,
      markers = { "鼻息" } },
    { key = "afo",   name = "空軍裝甲駕駛員",   npcs = { "仙人掌怪導覽員" }, cfg = "JoinAirForce",
      markers = { "特設區域", "騎乘、瞄準、射擊" } },   -- 要前往特設區域嗎？
    { key = "leap",  name = "登高跳跳樂大挑戰", npcs = { "仙人掌怪導覽員" }, cfg = "JoinLeap",
      markers = { "賽道", "跳躍比賽", "仙人掌怪獎盃" } },  -- 要前往賽道嗎？
    { key = "cliff", name = "搶救小雛鳥大作戰", npcs = { "束手無策的女性", "束手無策的少女" }, cfg = "JoinCliff",
      markers = { "小陸行鳥", "小雛鳥" } },
}

-- 來賓接待員的公告（NpcYell 2450 / 2452）
local ANNOUNCE_PATTERN = "主辦的活動「(.-)」"   -- 由金碟遊樂園主辦的活動「X」正在Y區域進行中。
local TEXT_STAGE_CLOSED = "舞臺活動的報名已經截止"

-- 傳喚鈴（EObj 2000401），位置取自金碟遊樂園的場景配置 bg/ffxiv/wil_w1/evt/w1eb/level/planlive.lgb
local BELL_NAME = "傳喚鈴"
local BELL_POSITIONS = {
    Vector3(0.13, 0.00, 14.37),
    Vector3(-0.36, 0.00, -14.25),
}

local Cond = {
    occupiedInEvent = 31,
    boundByDuty     = 34,
    betweenAreas    = 45,
    summoningBell   = 50,
}

local GA_SPRINT = 4

local Cfg = {
    JoinSlice      = Config.Get("JoinSlice"),
    JoinWind       = Config.Get("JoinWind"),
    JoinAirForce   = Config.Get("JoinAirForce"),
    JoinLeap       = Config.Get("JoinLeap"),
    JoinCliff      = Config.Get("JoinCliff"),
    MaxGates       = Config.Get("MaxGates"),
    PrepareSeconds = Config.Get("PrepareSeconds"),
    JoinWindow     = Config.Get("JoinWindow"),
    RetryInterval  = Config.Get("RetryInterval"),
    Retainers      = Config.Get("Retainers"),
    UseSprint      = Config.Get("UseSprint"),
    EchoLogs       = Config.Get("EchoLogs"),
}

local START_DELAY     = 3     -- 開場後幾秒才去問（太早問會聽到「下一次…」）
local TALK_RANGE      = 3.5   -- 離 NPC 多近可以對話
local JOIN_NPC_RANGE  = 40    -- 傳送後在多遠內找現場 NPC
local JOIN_TRIES      = 4
local WARP_TIMEOUT    = 20
local GO_KEEPER_STUCK = 90
local RETAINER_BUDGET    = 240   -- 離下一場還有 PrepareSeconds + 這麼多秒才去收雇員
local RETAINER_CHECK     = 30    -- 每幾秒問一次 AutoRetainer 有沒有雇員回來
local RETAINER_TIMEOUT   = 600
local GATE_BUSY_SECONDS  = 12 * 60   -- 報名後這段時間內還在場上（快刀斬魔、暴風倖存者），不去收雇員

-------------------------------------------------------------------------------
-- 2. Api 轉接層
-------------------------------------------------------------------------------

local Log, LogError

local Api = {}

-- NLua 的 tostring(列舉) 是「Text: 3」，只取冒號前的名稱
local function EnumName(v)
    local s = tostring(v)
    return s:match("^([%w_]+)") or s
end

function Api.Condition(id)
    return Svc.Condition[id] == true
end

function Api.PluginInstalled(internalName)
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        if plugin.InternalName == internalName and plugin.IsLoaded then
            return true
        end
    end
    return false
end

function Api.Territory()
    return Svc.ClientState.TerritoryType
end

function Api.PlayerPos()
    return Entity.Player.Position
end

function Api.PlayerReady()
    local ok, ready = pcall(function() return Player.Available and not Player.IsBusy end)
    return ok and ready == true
end

function Api.Mgp()
    local ok, n = pcall(function() return Inventory.GetItemCount(MGP_ITEM_ID) end)
    if ok and n ~= nil then return n end
    return 0
end

function Api.AddonReady(name)
    local ok, ready = pcall(function()
        local a = Addons.GetAddon(name)
        return a ~= nil and a.Ready
    end)
    return ok and ready == true
end

-- SND 包裝的 IEnumerable（AddonWrapper.Nodes / AtkValues）先複製成 List 再轉 Lua 陣列（luanet.each 會失敗）
function Api.ToLuaList(enumerable)
    local ok, items = pcall(function()
        local ListType = luanet.import_type("System.Collections.Generic.List`1[System.Object]")
        local list = ListType(enumerable)
        local out = {}
        for i = 0, list.Count - 1 do
            local item = list[i]
            if item == nil then item = list:get_Item(i) end
            out[#out + 1] = item
        end
        return out
    end)
    if ok then return items end
    return nil
end

-- 視窗上所有看得到的文字（Talk 的台詞、SelectYesno 的問題、SelectString 的選項）。
-- 讀不到節點時改讀 AtkValues
function Api.AddonText(name)
    local parts = {}
    pcall(function()
        local a = Addons.GetAddon(name)
        for _, node in ipairs(Api.ToLuaList(a.Nodes) or {}) do
            if EnumName(node.NodeType) == "Text" and node.IsVisible then
                local t = tostring(node.Text)
                if t ~= "" and t ~= "nil" then parts[#parts + 1] = t end
            end
        end
    end)
    if #parts == 0 then
        pcall(function()
            local a = Addons.GetAddon(name)
            for _, v in ipairs(Api.ToLuaList(a.AtkValues) or {}) do
                local s = tostring(v.ValueString)
                if s ~= "" and s ~= "nil" and s ~= "0" then parts[#parts + 1] = s end
            end
        end)
    end
    return table.concat(parts, " ")
end

-- 名稱在 names 裡、可選取、maxDist 內最近的物件
function Api.NearestByNames(names, maxDist)
    local ok, obj, dist = pcall(function()
        local me = Api.PlayerPos()
        local objs = Svc.Objects
        local best, bestDist = nil, math.huge
        for i = 0, objs.Length - 1 do
            local o = objs[i]
            if o ~= nil and o.IsTargetable then
                local n = o.Name.TextValue
                for _, want in ipairs(names) do
                    if n == want then
                        local dx, dy, dz = o.Position.X - me.X, o.Position.Y - me.Y, o.Position.Z - me.Z
                        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
                        if d < bestDist then best, bestDist = o, d end
                        break
                    end
                end
            end
        end
        return best, bestDist
    end)
    if not ok or obj == nil then return nil, nil end
    if maxDist ~= nil and dist > maxDist then return nil, nil end
    return obj, dist
end

function Api.TargetAndInteract(obj)
    local ok = pcall(function() Svc.Targets.Target = obj end)
    if not ok then return false end
    local t = Entity.Target
    if t == nil then return false end
    t:Interact()
    return true
end

function Api.NavReady()
    local ok, r = pcall(function() return IPC.vnavmesh.IsReady() end)
    return ok and r == true
end

function Api.NavRunning()
    local ok, r = pcall(function() return IPC.vnavmesh.IsRunning() or IPC.vnavmesh.PathfindInProgress() end)
    return ok and r == true
end

function Api.NavMoveTo(pos)
    IPC.vnavmesh.PathfindAndMoveTo(pos, false)
end

function Api.NavStop()
    if Api.NavRunning() then IPC.vnavmesh.Stop() end
end

function Api.Sprint()
    pcall(function() Actions.ExecuteGeneralAction(GA_SPRINT) end)
end

function Api.TeleportToSaucer()
    return pcall(function() Actions.Teleport(SAUCER_AETHERYTE) end)
end

function Api.ClickTalk()
    yield("/click Talk Click")
end

-- /click 沒反應時的保底：送遊戲的確認鍵（預設小鍵盤 0）
function Api.ConfirmKey()
    yield("/send NUMPAD0")
end

function Api.Yes()
    yield("/callback SelectYesno true 0")
end

function Api.No()
    yield("/callback SelectYesno true 1")
end

function Api.SelectString(index)
    yield("/callback SelectString true " .. index)
end

-- AutoRetainer：這個角色有沒有探險完成的雇員、是否正在處理
function Api.RetainersReady()
    local ok, r = pcall(function() return IPC.AutoRetainer.AreAnyRetainersAvailableForCurrentChara() end)
    return ok and r == true
end

function Api.AutoRetainerBusy()
    local ok, r = pcall(function() return IPC.AutoRetainer.IsBusy() end)
    return ok and r == true
end

-- 空軍裝甲 / 登高跳跳樂是副本型 G.A.T.E.，開始時會跳任務確認框
function Api.CommenceDuty()
    if Api.AddonReady("ContentsFinderConfirm") then
        yield("/callback ContentsFinderConfirm true 8")
        return true
    end
    return false
end

-------------------------------------------------------------------------------
-- 3. 工具函式
-------------------------------------------------------------------------------

State = {
    current     = "INIT",
    enteredAt   = os.clock(),
    lastSlot    = nil,    -- 已經處理過（參加或放棄）的場次開始時間
    targetSlot  = nil,    -- 這次要參加的場次開始時間
    gate        = nil,    -- 這次的 G.A.T.E.（GATES 的一筆）
    gatesJoined = 0,
    retainerRuns = 0,
    joined      = nil,    -- { gate, slot, mgp }：最近一次報名，用來算這場拿了多少金碟幣
    mgpStart    = 0,
    errors      = 0,
}

-- 聊天訊息不能有換行（\r、\n 會讓 SND 直接中止巨集），遊戲文字裡的控制字元一律換成空白；太長的截斷（不切到 UTF-8 字元中間）
local ECHO_MAX_BYTES = 400
local function ChatSafe(msg)
    local s = tostring(msg):gsub("%c", " ")
    s = s:gsub("  +", " ")
    if #s > ECHO_MAX_BYTES then
        local cut = ECHO_MAX_BYTES
        while cut > 0 and (s:byte(cut + 1) or 0) >= 0x80 and (s:byte(cut + 1) or 0) < 0xC0 do cut = cut - 1 end
        s = s:sub(1, cut) .. "…"
    end
    return s
end

function Log(msg)
    if Cfg.EchoLogs == "All" then yield("/echo [GATE] " .. ChatSafe(msg)) end
end

function LogError(msg)
    if Cfg.EchoLogs ~= "None" then yield("/echo [GATE][錯誤] " .. ChatSafe(msg)) end
end

local function Elapsed()
    return os.clock() - State.enteredAt
end

local function Distance(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- 這一場的開始時間（:00 / :20 / :40，本機時間；台灣時區是整點偏移，分秒跟地球時間一致）
local function SlotStart(t)
    t = t or os.time()
    local d = os.date("*t", t)
    return t - ((d.min % 20) * 60 + d.sec)
end

local function SlotLabel(slot)
    return os.date("%H:%M", slot)
end

local function GateEnabled(gate)
    return gate ~= nil and Cfg[gate.cfg] == true
end

local function GateFromText(text)
    if text == nil then return nil end
    for _, g in ipairs(GATES) do
        if text:find(g.name, 1, true) then return g end
    end
    for _, g in ipairs(GATES) do
        for _, m in ipairs(g.markers) do
            if text:find(m, 1, true) then return g end
        end
    end
    return nil
end

-- 這個 NPC 負責的所有 G.A.T.E.（仙人掌怪導覽員有兩個）
local function GatesForNpc(name)
    local list = {}
    for _, g in ipairs(GATES) do
        for _, n in ipairs(g.npcs) do
            if n == name then list[#list + 1] = g end
        end
    end
    return list
end

local function GateNames(list)
    local names = {}
    for _, g in ipairs(list) do names[#names + 1] = g.name end
    return table.concat(names, "／")
end

-- 這一場開始前後收到的來賓接待員公告
local function AnnouncedGate()
    local a = State.announce
    if a == nil or State.targetSlot == nil or a.at < State.targetSlot - 60 then return nil end
    return a.gate
end

-- 舞臺型（快刀斬魔、暴風倖存者）這一場的報名已經截止
local function StageClosed(gate)
    return gate ~= nil and gate.stage and State.stageClosedAt ~= nil and State.targetSlot ~= nil
        and State.stageClosedAt >= State.targetSlot
end

-- 聊天訊息觸發（開頭 function_chat_filters 只放行公告）：只記錄，不做別的事
function OnChatMessage()
    local ok, msg = pcall(function() return tostring(TriggerData.message) end)
    if not ok or msg == nil then return end
    local name = msg:match(ANNOUNCE_PATTERN)
    if name ~= nil then
        State.announce = { gate = GateFromText(name), name = name, at = os.time() }
    elseif msg:find(TEXT_STAGE_CLOSED, 1, true) then
        State.stageClosedAt = os.time()
    end
end

local function AllJoinNpcNames()
    local names = {}
    for _, g in ipairs(GATES) do
        for _, n in ipairs(g.npcs) do names[#names + 1] = n end
    end
    return names
end

local function NearestPos(list)
    local me = Api.PlayerPos()
    local best, bestDist = list[1], math.huge
    for _, p in ipairs(list) do
        local d = Distance(me, p)
        if d < bestDist then best, bestDist = p, d end
    end
    return best
end

-- 上一場的金碟幣結算（下一場要開始前報一次）
local function ReportLastGate()
    if State.joined == nil then return end
    local gained = Api.Mgp() - State.joined.mgp
    Log(string.format("%s 那場「%s」：金碟幣 %+d", SlotLabel(State.joined.slot), State.joined.gate.name, gained))
    State.joined = nil
end

local function FinishSlot(reason)
    if reason ~= nil then Log(reason) end
    State.lastSlot = State.targetSlot
    return "WAIT_SLOT"
end

-- 對話框（Talk）先讀再點掉，不需要 TextAdvance。回傳讀到的台詞（沒有 Talk 時回 nil）。
-- 主迴圈每一輪都會呼叫；ASK_KEEPER / JOIN 要看台詞判斷是哪一場，由它們自己呼叫
local TALK_CLICK_DELAY = 0.5
local TALK_CLICKS_BEFORE_KEY = 3
local function HandleTalk()
    if not Api.AddonReady("Talk") then
        State.talkSeenAt, State.talkClicks = nil, 0
        return nil
    end
    local text = Api.AddonText("Talk")
    if text ~= State.lastTalk then
        State.lastTalk, State.talkClicks = text, 0
        Log("對話：" .. text)
    end
    -- 0.5 秒後點掉（TextAdvance 開著的話它會先點）；同一句點了 3 次還在就改按確認鍵
    State.talkSeenAt = State.talkSeenAt or os.clock()
    if os.clock() - State.talkSeenAt > TALK_CLICK_DELAY then
        State.talkClicks = (State.talkClicks or 0) + 1
        if State.talkClicks > TALK_CLICKS_BEFORE_KEY then
            Api.ConfirmKey()
        else
            Api.ClickTalk()
        end
        State.talkSeenAt = os.clock()
    end
    return text
end

-------------------------------------------------------------------------------
-- 4. 狀態處理函式
-------------------------------------------------------------------------------

local Handlers = {}

function Handlers.INIT()
    if not Api.PluginInstalled("vnavmesh") then
        LogError("需要 vnavmesh")
        return "END"
    end
    if not Api.PluginInstalled("Saucy") then
        LogError("沒有載入 Saucy：只會幫你報名，場內不會自動玩")
    end
    local on = {}
    for _, g in ipairs(GATES) do
        if GateEnabled(g) then on[#on + 1] = g.name end
    end
    if #on == 0 then
        LogError("設定裡沒有開任何一個 G.A.T.E.")
        return "END"
    end
    State.arLoaded = Cfg.Retainers == true and Api.PluginInstalled("AutoRetainer")
    if Cfg.Retainers and not State.arLoaded then
        LogError("沒有載入 AutoRetainer，不會收雇員")
    end
    State.mgpStart = Api.Mgp()
    Log("要參加：" .. table.concat(on, "、"))
    Log("記得在 Saucy 開啟對應模組（快刀斬魔、暴風倖存者要勾自動移動）")
    return "GO_SAUCER"
end

function Handlers.GO_SAUCER()
    if Api.Territory() == SAUCER_TERRITORY and not Api.Condition(Cond.betweenAreas) then
        return "WAIT_SLOT"
    end
    if Api.Condition(Cond.betweenAreas) or Api.Condition(Cond.boundByDuty) then
        return nil
    end
    if not State.sent or Elapsed() > 30 then
        if Api.PlayerReady() then
            Log("傳送到金碟遊樂園")
            Api.TeleportToSaucer()
            State.sent = true
            State.enteredAt = os.clock()
        end
    end
    return nil
end

function Handlers.WAIT_SLOT()
    Api.CommenceDuty()

    if Api.Territory() ~= SAUCER_TERRITORY then
        -- 空軍裝甲 / 登高跳跳樂在副本裡，等它結束
        if Api.Condition(Cond.boundByDuty) or Api.Condition(Cond.betweenAreas) then return nil end
        return "GO_SAUCER"
    end
    if Api.Condition(Cond.betweenAreas) then return nil end

    local now = os.time()
    local slot = SlotStart(now)
    local nextSlot = slot + SLOT_SECONDS

    -- 這一場還沒處理、還在報名時間內
    if State.lastSlot ~= slot and now - slot < Cfg.JoinWindow then
        if Cfg.MaxGates > 0 and State.gatesJoined >= Cfg.MaxGates then return "END" end
        ReportLastGate()
        State.targetSlot = slot
        return "GO_KEEPER"
    end

    -- 下一場快開始了，先走過去
    if nextSlot - now <= Cfg.PrepareSeconds then
        if Cfg.MaxGates > 0 and State.gatesJoined >= Cfg.MaxGates then
            ReportLastGate()
            return "END"
        end
        ReportLastGate()
        State.targetSlot = nextSlot
        return "GO_KEEPER"
    end

    -- 空檔收雇員：離下一場夠久、不在 G.A.T.E. 場上
    local onStage = State.joined ~= nil and now - State.joined.slot < GATE_BUSY_SECONDS
    if State.arLoaded and not onStage and nextSlot - now > Cfg.PrepareSeconds + RETAINER_BUDGET
        and not Api.Condition(Cond.occupiedInEvent) then
        if State.lastArCheck == nil or os.clock() - State.lastArCheck > RETAINER_CHECK then
            State.lastArCheck = os.clock()
            if Api.RetainersReady() then return "RETAINERS" end
        end
    end

    if not State.waitLogged then
        Log(string.format("等下一場 %s", SlotLabel(nextSlot)))
        State.waitLogged = true
    end
    return nil
end

function Handlers.GO_KEEPER()
    Api.CommenceDuty()
    if Api.Territory() ~= SAUCER_TERRITORY then return "WAIT_SLOT" end
    if Api.Condition(Cond.betweenAreas) or Api.Condition(Cond.occupiedInEvent) then return nil end

    local keeper, dist = Api.NearestByNames({ KEEPER_NAME }, nil)
    if keeper ~= nil and dist <= TALK_RANGE then
        Api.NavStop()
        local wait = State.targetSlot + START_DELAY - os.time()
        if wait <= 0 then return "ASK_KEEPER" end
        if not State.arrivedLogged then
            Log(string.format("在活動解說員旁邊等 %d 秒", wait))
            State.arrivedLogged = true
        end
        return nil
    end

    if not Api.NavReady() then return nil end
    if not Api.NavRunning() then
        local dest = keeper ~= nil and keeper.Position or NearestPos(KEEPER_POSITIONS)
        Api.NavMoveTo(dest)
        if Cfg.UseSprint then Api.Sprint() end
        State.navTries = (State.navTries or 0) + 1
    end
    if Elapsed() > GO_KEEPER_STUCK then
        LogError("走不到活動解說員，換一個試試")
        table.insert(KEEPER_POSITIONS, table.remove(KEEPER_POSITIONS, 1))
        Api.NavStop()
        State.enteredAt = os.clock()
        State.errors = State.errors + 1
        if State.errors >= 3 then return "END" end
    end
    return nil
end

function Handlers.ASK_KEEPER()
    Api.CommenceDuty()
    if os.time() - State.targetSlot > Cfg.JoinWindow then
        return FinishSlot("報名時間已過，等下一場")
    end

    if Api.AddonReady("SelectYesno") then
        local q = Api.AddonText("SelectYesno")
        if q:find(TEXT_WARP, 1, true) then
            State.gate = State.gate or AnnouncedGate()
            if StageClosed(State.gate) then
                Api.No()
                return FinishSlot("「" .. State.gate.name .. "」報名已經截止")
            end
            if State.gate ~= nil and not GateEnabled(State.gate) then
                Api.No()
                return FinishSlot("這場是「" .. State.gate.name .. "」，設定不參加")
            end
            Log("傳送到舉辦地點" .. (State.gate and ("（" .. State.gate.name .. "）") or "（沒讀到是哪一場，到現場再判斷）"))
            Api.Yes()
            return "WARPING"
        end
        Log("沒預期的確認框，選否：" .. q)
        Api.No()
        return nil
    end

    local talk = HandleTalk()
    if talk ~= nil then
        if talk:find(TEXT_CLOSED, 1, true) then
            State.closed = true
        elseif talk:find(TEXT_IN_SESSION, 1, true) then
            State.gate = GateFromText(talk) or State.gate
        elseif talk:find(TEXT_NEXT, 1, true) or talk:find(TEXT_UPCOMING, 1, true) then
            State.notYet = true
        end
        return nil
    end

    if Api.AddonReady("SelectString") then
        local opts = Api.AddonText("SelectString")
        Log("選單：" .. opts .. " → 選第 1 項")
        Api.SelectString(0)
        return nil
    end

    if Api.Condition(Cond.occupiedInEvent) then return nil end

    -- 對話已結束
    if State.closed then
        return FinishSlot("報名已經結束" .. (State.gate and ("（" .. State.gate.name .. "）") or ""))
    end

    if State.lastInteract == nil or os.clock() - State.lastInteract > Cfg.RetryInterval then
        if State.notYet then
            Log("還沒開始，稍後再問")
            State.notYet = false
        end
        local keeper, dist = Api.NearestByNames({ KEEPER_NAME }, nil)
        if keeper == nil or dist > TALK_RANGE then return "GO_KEEPER" end
        Api.TargetAndInteract(keeper)
        State.lastInteract = os.clock()
    end
    return nil
end

function Handlers.WARPING()
    if Api.Condition(Cond.betweenAreas) then
        State.warpSeen = true
        return nil
    end
    -- 同地區傳送不一定有讀取畫面：看到讀取並結束，或 3 秒後就算到了
    if (State.warpSeen or Elapsed() > 3) and Api.PlayerReady() then return "JOIN" end
    if Elapsed() > WARP_TIMEOUT then return "JOIN" end
    return nil
end

function Handlers.JOIN()
    Api.CommenceDuty()
    if Elapsed() > 90 then
        return FinishSlot("報名逾時，等下一場")
    end

    State.gate = State.gate or AnnouncedGate()
    if StageClosed(State.gate) then
        return FinishSlot("「" .. State.gate.name .. "」報名已經截止")
    end

    -- 確認框：報名
    if Api.AddonReady("SelectYesno") then
        local q = Api.AddonText("SelectYesno")
        local g = GateFromText(q)
        if g ~= nil then State.gate = g end
        -- 還分不出是哪一場（仙人掌怪導覽員）：候選裡有不參加的就不冒險
        if State.gate == nil and State.candidates ~= nil then
            for _, c in ipairs(State.candidates) do
                if not GateEnabled(c) then
                    Api.No()
                    return FinishSlot("分不出是" .. GateNames(State.candidates) .. "哪一場（確認框：" .. q .. "），不報名")
                end
            end
        end
        if State.gate ~= nil and not GateEnabled(State.gate) then
            Api.No()
            return FinishSlot("這場是「" .. State.gate.name .. "」，設定不參加")
        end
        Log("確認報名：" .. q)
        local mgpBefore = Api.Mgp()
        Api.Yes()
        State.gatesJoined = State.gatesJoined + 1
        State.joined = { gate = State.gate or { name = "？" }, slot = State.targetSlot, mgp = mgpBefore }
        return FinishSlot(string.format("已報名（第 %d 場），交給 Saucy", State.gatesJoined))
    end

    local talk = HandleTalk()
    if talk ~= nil then
        local g = GateFromText(talk)
        if g ~= nil then State.gate = g end
        return nil
    end

    if Api.AddonReady("SelectString") then
        local opts = Api.AddonText("SelectString")
        Log("選單：" .. opts .. " → 選第 1 項")
        Api.SelectString(0)
        return nil
    end

    if Api.Condition(Cond.occupiedInEvent) or Api.Condition(Cond.betweenAreas) then return nil end

    -- 找現場報名的 NPC
    local names = State.gate and State.gate.npcs or AllJoinNpcNames()
    local npc, dist = Api.NearestByNames(names, JOIN_NPC_RANGE)
    if npc == nil then
        if Elapsed() > 15 then return FinishSlot("附近找不到報名的 NPC，等下一場") end
        return nil
    end
    if State.gate == nil and State.candidates == nil then
        local list = GatesForNpc(npc.Name.TextValue)
        if #list == 1 then
            State.gate = list[1]
            Log("從現場 NPC 判斷是「" .. State.gate.name .. "」")
        elseif #list > 1 then
            State.candidates = list
            local anyEnabled = false
            for _, c in ipairs(list) do anyEnabled = anyEnabled or GateEnabled(c) end
            if not anyEnabled then return FinishSlot(GateNames(list) .. "都設定不參加") end
            Log("現場 NPC 負責" .. GateNames(list) .. "，看對話或確認框再決定")
        end
    end
    if State.gate ~= nil and not GateEnabled(State.gate) then
        return FinishSlot("這場是「" .. State.gate.name .. "」，設定不參加")
    end

    if dist > TALK_RANGE then
        if not Api.NavRunning() and Api.NavReady() then Api.NavMoveTo(npc.Position) end
        return nil
    end
    Api.NavStop()
    if State.lastInteract == nil or os.clock() - State.lastInteract > Cfg.RetryInterval then
        State.joinTries = (State.joinTries or 0) + 1
        if State.joinTries > JOIN_TRIES then
            return FinishSlot("跟報名 NPC 對話沒反應，等下一場")
        end
        Api.TargetAndInteract(npc)
        State.lastInteract = os.clock()
    end
    return nil
end

-- 走到傳喚鈴 → 打開雇員清單 → /ays e 讓 AutoRetainer 處理 → 不忙了就關清單
function Handlers.RETAINERS()
    if Api.Territory() ~= SAUCER_TERRITORY then return "WAIT_SLOT" end
    if Elapsed() > RETAINER_TIMEOUT + 30 then return "WAIT_SLOT" end
    if Elapsed() > RETAINER_TIMEOUT and State.arPhase ~= "close" then
        LogError("收雇員逾時，關掉清單")
        State.arPhase = "close"
    end
    State.arPhase = State.arPhase or "walk"

    if State.arPhase == "walk" then
        if Api.AddonReady("RetainerList") then
            Log("雇員清單已開，交給 AutoRetainer")
            yield("/ays e")
            State.arPhase, State.arStart, State.arBusyAt = "process", os.clock(), os.clock()
            return nil
        end
        if Api.Condition(Cond.betweenAreas) or Api.Condition(Cond.occupiedInEvent) then return nil end
        local bell, dist = Api.NearestByNames({ BELL_NAME }, nil)
        if bell ~= nil and dist <= TALK_RANGE then
            Api.NavStop()
            if State.lastInteract == nil or os.clock() - State.lastInteract > Cfg.RetryInterval then
                State.joinTries = (State.joinTries or 0) + 1
                if State.joinTries > JOIN_TRIES then
                    LogError("打不開傳喚鈴")
                    return "WAIT_SLOT"
                end
                Api.TargetAndInteract(bell)
                State.lastInteract = os.clock()
            end
            return nil
        end
        if Api.NavReady() and not Api.NavRunning() then
            Log("去傳喚鈴收雇員")
            Api.NavMoveTo(bell ~= nil and bell.Position or NearestPos(BELL_POSITIONS))
            if Cfg.UseSprint then Api.Sprint() end
        end
        return nil
    end

    if State.arPhase == "process" then
        if Api.AutoRetainerBusy() then State.arBusyAt = os.clock() end
        -- 至少給 5 秒啟動，之後連續 3 秒不忙就算處理完
        if os.clock() - State.arStart > 5 and os.clock() - State.arBusyAt > 3 then
            State.arPhase = "close"
        end
        return nil
    end

    -- close
    if Api.AddonReady("RetainerList") then
        if State.lastClose == nil or os.clock() - State.lastClose > 1 then
            yield("/callback RetainerList true -1")
            State.lastClose = os.clock()
        end
        return nil
    end
    if Api.Condition(Cond.summoningBell) or Api.Condition(Cond.occupiedInEvent) then return nil end
    State.retainerRuns = State.retainerRuns + 1
    State.lastArCheck = os.clock()
    Log("雇員處理完畢")
    return "WAIT_SLOT"
end

function Handlers.END()
    Api.NavStop()
    ReportLastGate()
    yield(string.format("/echo [GATE] 結束：報名 %d 場，金碟幣 %+d，收雇員 %d 次", State.gatesJoined, Api.Mgp() - State.mgpStart, State.retainerRuns))
    return nil
end

-------------------------------------------------------------------------------
-- 5. 主迴圈
-------------------------------------------------------------------------------

local function Transition(next)
    if next == nil or next == State.current then return end
    Log(State.current .. " → " .. next)
    if next == "GO_KEEPER" or next == "WAIT_SLOT" then
        State.gate, State.candidates = nil, nil
    end
    State.current = next
    State.enteredAt = os.clock()
    State.sent, State.waitLogged, State.arrivedLogged = false, false, false
    State.navTries, State.joinTries, State.lastInteract = 0, 0, nil
    State.closed, State.notYet, State.warpSeen = false, false, false
    State.lastTalk, State.talkSeenAt = nil, nil
    State.arPhase, State.arStart, State.arBusyAt, State.lastClose = nil, nil, nil, nil
end

-- 這兩個狀態要先讀台詞，對話框由它們自己處理
local READS_TALK = { ASK_KEEPER = true, JOIN = true }

while true do
    if State.current == "END" then
        Handlers.END()
        break
    end
    if not READS_TALK[State.current] then pcall(HandleTalk) end
    local ok, result = pcall(Handlers[State.current])
    if not ok then
        LogError("例外：" .. tostring(result))
        State.errors = State.errors + 1
        if State.errors >= 5 then
            result = "END"
        else
            yield("/wait 2")
            result = "WAIT_SLOT"
        end
    end
    Transition(result)
    yield("/wait 0.3")
end
