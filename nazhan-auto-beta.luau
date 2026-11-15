-- Nazhan Hub beta. Standalone UI and one bounded progress worker.
local SEAS = {
    [2753915549] = 1, [85211729168715] = 1,
    [4442272183] = 2, [79091703265657] = 2,
    [7449423635] = 3, [100117331123089] = 3,
}
local CAP = 3000
local function cleanSettings(value)
    value = type(value) == "table" and value or {}
    local result = {version = 1, enabled = value.enabled == true, light = value.light ~= false, scale = "Auto", fruit = {}}
    if table.find({"Auto", "Kecil", "Besar"}, value.scale) then result.scale = value.scale end
    if type(value.fruit) == "table" then
        local count = 0
        for name, item in pairs(value.fruit) do
            if type(name) == "string" and #name <= 80 and type(item) == "table" then
                local function countValue(n, limit)
                    return type(n) == "number" and n == n and math.clamp(math.floor(n), 0, limit or 10000) or 0
                end
                result.fruit[name] = {done = countValue(item.done), expired = countValue(item.expired),
                    updated = countValue(item.updated, 100000), protected = item.protected == true}
                count += 1
                if count >= 100 then break end
            end
        end
    end
    return result
end

local function fruitLabel(item, day)
    if not item then return "Data belum cukup" end
    if item.protected then return "Dilindungi" end
    local n = item.done + item.expired
    if n < 5 or item.updated > day or day - item.updated > 14 then return "Data belum cukup" end
    if item.done / n >= 0.65 then return "Permintaan tinggi" end
    if item.done / n <= 0.30 then return "Permintaan rendah" end
    return "Permintaan menengah"
end

local function progressPhase(sea, level)
    if not sea then return "unknown" end
    if not level then return "loading" end
    if sea == 1 and level >= 700 or sea == 2 and level >= 1500 then return "unlock" end
    if sea == 3 and level >= CAP then return "complete" end
    return "quest"
end

local EXCLUDED = {MarineQuest=true, BartiloQuest=true, CitizenQuest=true, Trainees=true}
local function chooseQuest(catalog, level, sea, activeTitle, localTargets)
    local best, current
    activeTitle = string.lower(activeTitle)
    local minLevel = sea == 1 and 0 or sea == 2 and 700 or 1500
    local maxLevel = sea == 1 and 699 or sea == 2 and 1499 or CAP
    for name, tiers in pairs(catalog) do
        if type(name) == "string" and not EXCLUDED[name] and type(tiers) == "table" then
            for tier, q in pairs(tiers) do
                if type(tier) == "number" and type(q) == "table" and type(q.LevelReq) == "number"
                    and q.LevelReq >= minLevel and q.LevelReq <= math.min(level, maxLevel) and type(q.Task) == "table" then
                    for mob, count in pairs(q.Task) do
                        if type(mob) == "string" and type(count) == "number" and count > 1 then
                            local target = {group=name, tier=tier, mob=mob, level=q.LevelReq}
                            if string.find(activeTitle, string.lower(mob), 1, true)
                                and (not current or q.LevelReq > current.level) then current = target end
                            if localTargets[mob] and (not best or q.LevelReq > best.level
                                or q.LevelReq == best.level and mob < best.mob) then best = target end
                        end
                    end
                end
            end
        end
    end
    return current or best
end

-- Runtime
local players = game:GetService("Players")
local player = players.LocalPlayer
if not player then return end
local guiParent = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 6)
if not guiParent then return end

local store = (getgenv and getgenv()) or shared or _G
local ownerKey = "NazhanHubAutoBeta"
local previous = store[ownerKey]
if type(previous) == "table" and type(previous.close) == "function" then previous.close() end
local oldGui = guiParent:FindFirstChild(ownerKey)
if oldGui then oldGui:Destroy() end
local owner = {}
store[ownerKey] = owner
local alive, enabled, paused = true, false, false
local movedCharacter
local links = {}
local http = game:GetService("HttpService")
local replicated = game:GetService("ReplicatedStorage")
local sea = SEAS[game.PlaceId]
local storagePath = "nazhan-hub-auto-v1.json"
local diskAvailable = type(readfile) == "function" and type(writefile) == "function"
local saveStatus = diskAvailable and "Default dimuat" or "Penyimpanan lokal tidak tersedia"
local function readSettings(file)
    if not diskAvailable then return nil end
    local ok, result = pcall(function()
        if type(isfile) == "function" and not isfile(file) then return nil end
        return http:JSONDecode(readfile(file))
    end)
    return ok and type(result) == "table" and result.version == 1 and result or nil
end
local loaded = readSettings(storagePath)
local backup = not loaded and readSettings(storagePath..".bak") or nil
if loaded or backup then saveStatus = loaded and "Setelan dipulihkan" or "Cadangan dipulihkan" end
local settings = cleanSettings(loaded or backup)
local saveGeneration = 0
local lightEffects = {}
local pendingSave = false
local function flushSettings()
    if not pendingSave or not diskAvailable then return end
    local valid = readSettings(storagePath)
    local ok = pcall(function()
        if valid then writefile(storagePath..".bak", http:JSONEncode(valid)) end
        writefile(storagePath, http:JSONEncode(settings))
    end)
    pendingSave = not ok
    saveStatus = ok and "Setelan tersimpan" or "Gagal menyimpan setelan"
end
local function saveLater(immediate)
    pendingSave = true
    saveGeneration += 1
    local request = saveGeneration
    if immediate then flushSettings(); return end
    task.delay(0.25, function()
        if alive and request == saveGeneration then flushSettings() end
    end)
end

local color = {background=Color3.fromRGB(20,24,30), panel=Color3.fromRGB(34,41,50),
    text=Color3.fromRGB(238,242,245), dim=Color3.fromRGB(182,194,205), accent=Color3.fromRGB(111,221,189)}
local function make(class, parent, props)
    local object = Instance.new(class)
    for k,v in pairs(props) do object[k] = v end
    object.Parent = parent
    return object
end
local function listen(signal, callback)
    local link = signal:Connect(callback)
    table.insert(links, link)
    return link
end
local gui = make("ScreenGui", guiParent, {Name=ownerKey, ResetOnSpawn=false, DisplayOrder=20})
local area = make("Frame", gui, {Size=UDim2.fromScale(1,1), BackgroundTransparency=1})
local window = make("Frame", area, {Position=UDim2.fromScale(0.5,0.5), AnchorPoint=Vector2.new(.5,.5),
    BackgroundColor3=color.background, BorderSizePixel=0, ClipsDescendants=true})
make("UICorner", window, {CornerRadius=UDim.new(0,12)})
local function label(parent, value, height)
    return make("TextLabel", parent, {Size=UDim2.new(1,0,0,height), BackgroundTransparency=1,
        Text=value, TextColor3=color.text, Font=Enum.Font.Gotham, TextSize=15, TextWrapped=true,
        TextXAlignment=Enum.TextXAlignment.Left})
end
local function button(parent, value, callback)
    local item = make("TextButton", parent, {Size=UDim2.new(1,0,0,44), BackgroundColor3=color.panel,
        BorderSizePixel=0, Text=value, TextColor3=color.text, Font=Enum.Font.GothamBold, TextSize=14})
    make("UICorner", item, {CornerRadius=UDim.new(0,8)})
    listen(item.Activated, callback)
    return item
end
local title = label(window,"Nazhan Hub",52)
title.Position = UDim2.fromOffset(16,0)
title.Size = UDim2.new(1,-130,0,52)
title.Font, title.TextSize = Enum.Font.GothamBold, 22
local body = make("ScrollingFrame", window, {Position=UDim2.fromOffset(12,104), Size=UDim2.new(1,-24,1,-116),
    AutomaticCanvasSize=Enum.AutomaticSize.Y, CanvasSize=UDim2.new(), ScrollBarThickness=4, BackgroundTransparency=1})
local pages, current = {}, nil
local nav = make("Frame",window,{Position=UDim2.fromOffset(12,50),Size=UDim2.new(1,-24,0,44),BackgroundTransparency=1})
make("UIListLayout", nav, {FillDirection=Enum.FillDirection.Horizontal, Padding=UDim.new(0,4)})
local function openPage(name)
    if current then current.Parent = nil end
    current = pages[name]
    current.Parent = body
    body.CanvasPosition = Vector2.zero
end
for _, name in ipairs({"Auto","Fruit","Events","Settings"}) do
    local page = make("Frame", nil, {Size=UDim2.new(1,-6,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1})
    make("UIListLayout",page,{Padding=UDim.new(0,7)})
    pages[name] = page
    local tab = button(nav,name,function() openPage(name) end)
    tab.Size = UDim2.new(.25,-3,1,0)
end

local function resize()
    local bounds = area.AbsoluteSize
    if bounds.X < 60 or bounds.Y < 60 then return end
    local width = settings.scale == "Kecil" and 420 or settings.scale == "Besar" and 660 or 540
    window.Size = UDim2.fromOffset(math.min(bounds.X-20, width), math.min(bounds.Y-20, 510))
end
listen(area:GetPropertyChangedSignal("AbsoluteSize"), resize)
resize()
window.Size = window.Size.X.Offset > 0 and window.Size or UDim2.fromScale(.92,.86)

local status = label(pages.Auto,"Menyiapkan Nazhan Hub…",68)
status.TextColor3 = color.accent
local function show(value)
    local text = "Sea "..(sea or "?").."  ·  "..value
    if status.Text ~= text then status.Text = text end
end
local function stopMovement()
    local character = movedCharacter
    movedCharacter = nil
    if character ~= player.Character then return end
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if humanoid and root then humanoid:MoveTo(root.Position) end
end
button(pages.Auto,"Mulai / Lanjut",function()
    if not sea then show("Place belum didukung"); return end
    enabled, paused, settings.enabled = true, false, true
    show("Mengecek quest dan karakter…")
    saveLater()
end)
button(pages.Auto,"Jeda sesi ini",function()
    paused = true
    stopMovement()
    show("Dijeda. Tekan Mulai / Lanjut untuk melanjutkan.")
end)
button(pages.Auto,"Stop dan simpan",function()
    enabled, paused, settings.enabled = false, false, false
    stopMovement()
    show("Auto berhenti")
    saveLater(true)
end)

local remoteBusy, nextRemote = false, 0
local function request(command, ...)
    if remoteBusy or os.clock() < nextRemote then return false end
    local folder = replicated:FindFirstChild("Remotes")
    local remote = folder and folder:FindFirstChild("CommF_")
    if not remote or not remote:IsA("RemoteFunction") then return false end
    nextRemote, remoteBusy = os.clock()+2, true
    local ok, value = pcall(remote.InvokeServer,remote,command,...)
    remoteBusy = false
    if not alive then return false end
    if not ok then nextRemote = os.clock()+6 end
    return ok, value
end

local fruitPage = pages.Fruit
local stock = label(fruitPage,"Inventaris dimuat saat kamu menekan Muat inventaris.",95)
button(fruitPage,"Muat inventaris",function()
    if not sea then stock.Text = "Inventaris Blox Fruits tidak tersedia di place ini."; return end
    local ok, inventory = request("getInventory")
    if not alive then return end
    if not ok or type(inventory) ~= "table" then stock.Text = "Inventaris belum tersedia. Coba lagi beberapa detik."; return end
    local rows, day = {}, math.floor(os.time()/86400)
    for _, item in pairs(inventory) do
        if type(item) == "table" and (item.Type == "Blox Fruit" or item.Type == "Fruit") and type(item.Name) == "string" then
            table.insert(rows,item.Name.." · "..fruitLabel(settings.fruit[item.Name],day))
        end
    end
    table.sort(rows)
    stock.Size = UDim2.new(1,0,0,math.clamp(#rows*26,70,800))
    stock.Text = #rows > 0 and table.concat(rows,"\n") or "Respons inventaris tidak memuat fruit tersimpan."
end)
local fruitName = make("TextBox",fruitPage,{Size=UDim2.new(1,0,0,44),BackgroundColor3=color.panel,
    TextColor3=color.text,PlaceholderText="Nama fruit persis di inventaris", Text="",TextSize=14,ClearTextOnFocus=false})
local fruitStatus = label(fruitPage,"Catatan lokal trade dalam game, per nama fruit.",58)
local function record(field)
    local name = string.match(fruitName.Text,"^%s*(.-)%s*$")
    if not name or #name == 0 or #name > 80 then fruitStatus.Text = "Masukkan nama fruit dari inventaris."; return end
    if not settings.fruit[name] then
        local n = 0
        for _ in pairs(settings.fruit) do n += 1 end
        if n >= 100 then fruitStatus.Text = "Batas 100 catatan fruit tercapai."; return end
        settings.fruit[name] = {done=0,expired=0,updated=0,protected=false}
    end
    local item = settings.fruit[name]
    local day = math.floor(os.time()/86400)
    if field == "protected" then
        item.protected = not item.protected
    else
        if item.updated > day or day-item.updated > 14 then item.done,item.expired = 0,0 end
        item.updated = day
        item[field] = math.min(10000,item[field]+1)
    end
    fruitStatus.Text = fruitLabel(item,day).." · "..item.done.." selesai / "..item.expired.." tidak selesai"
    saveLater()
end
button(fruitPage,"Catat trade selesai",function() record("done") end)
button(fruitPage,"Catat penawaran tidak selesai",function() record("expired") end)
button(fruitPage,"Lindungi / buka proteksi",function() record("protected") end)

local eventLabel = label(pages.Events,
    "Halloween · Status belum diketahui\nGunakan menu event dalam game untuk memastikan event tersedia di server ini.",104)
eventLabel.TextColor3 = color.dim

local stateLabel = label(pages.Settings,saveStatus,44)
local lighting = game:GetService("Lighting")
local function applyLight()
    if not sea then return end
    if settings.light then
        for _, effect in ipairs(lighting:GetChildren()) do
            if effect:IsA("BloomEffect") or effect:IsA("DepthOfFieldEffect") or effect:IsA("SunRaysEffect") then
                if lightEffects[effect] == nil then lightEffects[effect] = effect.Enabled end
                effect.Enabled = false
            end
        end
    else
        for effect, old in pairs(lightEffects) do if effect.Parent then effect.Enabled = old end end
        table.clear(lightEffects)
    end
end
local mode
mode = button(pages.Settings, "Mode Ringan: "..(settings.light and "Aktif" or "Mati"),function()
    settings.light = not settings.light
    mode.Text = "Mode Ringan: "..(settings.light and "Aktif" or "Mati")
    applyLight()
    saveLater()
end)
local scale
scale = button(pages.Settings, "Ukuran UI: "..settings.scale,function()
    settings.scale = settings.scale == "Auto" and "Kecil" or settings.scale == "Kecil" and "Besar" or "Auto"
    scale.Text = "Ukuran UI: "..settings.scale
    resize()
    saveLater()
end)
local resetAt = 0
button(pages.Settings,"Reset pengaturan",function()
    if os.clock() >= resetAt then
        resetAt = os.clock()+5
        stateLabel.Text = "Tekan Reset lagi dalam 5 detik. Catatan fruit dipertahankan."
        return
    end
    resetAt = 0
    local fruit = settings.fruit
    settings = cleanSettings()
    settings.fruit = fruit
    enabled, paused = false, false
    stopMovement()
    mode.Text, scale.Text = "Mode Ringan: Aktif","Ukuran UI: Auto"
    applyLight()
    resize()
    show("Setelan direset. Auto berhenti.")
    saveLater(true)
end)
button(pages.Settings,"Tutup hub",function() if owner.close then owner.close() end end)
openPage("Auto")
local hidden = button(area,"Buka Nazhan Hub",function()
    window.Visible = true
    area.OpenHub.Visible = false
end)
hidden.Name, hidden.Visible = "OpenHub", false
hidden.Size, hidden.Position = UDim2.fromOffset(150,44),UDim2.fromOffset(10,10)
local minimize = button(window,"Minimalkan",function()
    window.Visible = false
    hidden.Visible = true
end)
minimize.Size, minimize.Position = UDim2.fromOffset(102,44), UDim2.new(1,-114,0,4)
if sea then applyLight() end

local questCatalog, guide
local lastQuestAttempt, nextAttack, nextMove = -10,0,0
local lastScan, targets, selected = -10,{},nil
local lastLevel, lastTitle
local triedTravel = false
local function child(parent, name)
    return parent and parent:FindFirstChild(name)
end
local function questText()
    local quest = child(child(guiParent,"Main"),"Quest")
    if quest and quest.Visible then
        local node = child(child(child(quest,"Container"),"QuestTitle"),"Title")
        return true, node and node.Text or ""
    end
    local tracked = child(guiParent,"TrackedQuestFrame")
    local frame = child(tracked,"Frame")
    if tracked and tracked.Enabled and frame and frame.Visible then
        local node = child(child(frame,"header"),"textLabel")
        if node and not node:IsA("TextLabel") then node = child(node,"textLabel") end
        return true, node and node:IsA("TextLabel") and node.Text or ""
    end
    return false,""
end
local function move(humanoid, point)
    if os.clock() >= nextMove then
        nextMove = os.clock()+1
        movedCharacter = player.Character
        humanoid:MoveTo(point)
    end
end
local function tickProgress()
    if not enabled or paused then return end
    local levelObject = child(child(player,"Data"),"Level")
    local level = levelObject and tonumber(levelObject.Value)
    local phase = progressPhase(sea,level)
    if phase == "unknown" then show("Place belum didukung"); return end
    if phase == "loading" then show("Menunggu data level"); return end
    if phase == "unlock" then
        stopMovement()
        if not triedTravel and not remoteBusy and os.clock() >= nextRemote then
            triedTravel = true
            flushSettings()
            show("Memeriksa perjalanan ke Sea "..(sea+1))
            request(sea == 1 and "TravelDressrosa" or "TravelZou")
            if not alive or not enabled or paused then return end
        end
        show("Sea berikutnya · jika belum pindah, selesaikan syarat unlock di game.")
        return
    end
    if phase == "complete" then
        enabled, settings.enabled = false, false
        stopMovement()
        show("Progres utama selesai · level "..level)
        saveLater(true)
        return
    end
    local character = player.Character
    local root = child(character,"HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then
        movedCharacter = nil
        show("Menunggu respawn")
        return
    end
    if not questCatalog then
        local source = child(replicated,"Quests")
        if source and source:IsA("ModuleScript") then
            local ok, result = pcall(require,source)
            if ok and type(result) == "table" then questCatalog = result end
        end
        if not questCatalog then show("Daftar quest belum tersedia"); return end
    end
    local active,titleText = questText()
    local enemies = child(workspace,"Enemies")
    local now = os.clock()
    if now-lastScan >= 2.5 then
        lastScan = now
        targets = {}
        for _,enemy in ipairs(enemies and enemies:GetChildren() or {}) do
            local body,health = child(enemy,"HumanoidRootPart"),enemy:FindFirstChildOfClass("Humanoid")
            if body and health and health.Health > 0 then
                local name = string.match(enemy.Name,"^(.-)%s*%[") or enemy.Name
                local distance = (root.Position-body.Position).Magnitude
                if not targets[name] or distance < targets[name].distance then
                    targets[name] = {model=enemy,body=body,distance=distance}
                end
            end
        end
        selected = chooseQuest(questCatalog,level,sea,titleText,targets)
    elseif level ~= lastLevel or titleText ~= lastTitle then
        selected = chooseQuest(questCatalog,level,sea,titleText,targets)
    end
    lastLevel,lastTitle = level,titleText
    if not selected then stopMovement(); show("Quest atau target belum terdeteksi"); return end
    if active then
        if not string.find(string.lower(titleText),string.lower(selected.mob),1,true) then
            stopMovement()
            show("Quest aktif belum cocok · selesaikan atau ganti quest di game")
            return
        end
        local target = targets[selected.mob]
        if not target or not target.model.Parent then stopMovement(); show("Menunggu "..selected.mob); return end
        local distance = (root.Position-target.body.Position).Magnitude
        if distance > 9 then move(humanoid,target.body.Position)
        elseif now >= nextAttack then
            stopMovement()
            nextAttack = now+.75
            local tool = character:FindFirstChildOfClass("Tool")
            if tool and (tool.ToolTip == "Melee" or tool.ToolTip == "Sword" or tool.ToolTip == "Gun") then
                tool:Activate()
            else
                local backpack = child(player,"Backpack")
                for _, candidate in ipairs(backpack and backpack:GetChildren() or {}) do
                    if candidate:IsA("Tool") and (candidate.ToolTip == "Melee" or candidate.ToolTip == "Sword") then
                        humanoid:EquipTool(candidate)
                        show("Menyiapkan "..candidate.Name)
                        return
                    end
                end
                show("Senjata Melee atau Sword belum tersedia")
                return
            end
        end
        show("Quest · "..selected.mob)
        return
    end
    if not guide then
        local source = child(replicated,"GuideModule")
        if source and source:IsA("ModuleScript") then
            local ok,data = pcall(require,source)
            if ok and type(data) == "table" then guide = data end
        end
    end
    local npcName = guide and guide.Data and guide.Data.LastClosestNPC
    local npc = type(npcName) == "string" and child(child(workspace,"NPCs"),npcName)
    local npcRoot = npc and child(npc,"HumanoidRootPart")
    if not npcRoot then
        stopMovement()
        show("Dekati NPC pemberi quest untuk "..selected.mob)
        return
    end
    if (root.Position-npcRoot.Position).Magnitude > 12 then
        move(humanoid,npcRoot.Position)
        show("Menuju NPC untuk "..selected.mob)
        return
    end
    stopMovement()
    if now-lastQuestAttempt >= 8 then
        lastQuestAttempt = now
        local ok = request("StartQuest",selected.group,selected.tier)
        if not alive or not enabled or paused then return end
        show(ok and "Menunggu konfirmasi quest "..selected.mob or "Quest belum bisa dimulai")
    end
end

local runner
owner.close = function()
    if not alive then return end
    flushSettings()
    alive = false
    for _, link in ipairs(links) do link:Disconnect() end
    stopMovement()
    if runner then pcall(task.cancel,runner) end
    for effect, old in pairs(lightEffects) do if effect.Parent then effect.Enabled = old end end
    for _, page in pairs(pages) do page:Destroy() end
    gui:Destroy()
    if store[ownerKey] == owner then store[ownerKey] = nil end
end
enabled = sea ~= nil and settings.enabled
show(enabled and "Memulihkan Auto Progress…" or "Auto siap · pilih Mulai")
runner = task.spawn(function()
    while alive do
        if resetAt == 0 or os.clock() >= resetAt then
            if stateLabel.Text ~= saveStatus then stateLabel.Text = saveStatus end
        end
        local ok = pcall(tickProgress)
        if not ok and alive then
            paused = true
            stopMovement()
            show("Dijeda · struktur data game berubah")
        end
        task.wait(enabled and not paused and 0.65 or 1.5)
    end
end)
