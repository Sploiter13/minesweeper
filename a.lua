--!native
--!optimize 2

---- environment ----
local loadSuccess = pcall(function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Sploiter13/severefuncs/refs/heads/main/merge2.lua"))()
end)

task.wait(3)

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local MathFloor = math.floor
local MathSqrt = math.sqrt
local MathAbs = math.abs
local MathMax = math.max
local MathMin = math.min
local MathPow = math.pow
local MathHuge = math.huge
local MathLog = math.log
local MathExp = math.exp

local TableCreate = table.create
local TableClear = table.clear
local TableInsert = table.insert
local TableRemove = table.remove
local TableSort = table.sort
local TableConcat = table.concat
local TableFind = table.find

local StringLower = string.lower
local StringFind = string.find
local StringByte = string.byte
local StringUpper = string.upper

local OsClock = os.clock

local VectorCreate = vector.create
local VectorMagnitude = vector.magnitude

local Pcall = pcall

---- constants ----
local FLAG_NAME: string = "Flag"
local PARTS_NAME: string = "Parts"
local SAFE_TEXT: string = ""
local MINE_COLOR: Color3 = Color3.fromRGB(205, 142, 100)
local SPACING: number = 5
local ORIGIN_X: number = 0
local ORIGIN_Y: number = 70
local ORIGIN_Z: number = 0

local LOGIC_INTERVAL: number = 0.01
local SCAN_INTERVAL: number = 0.5
local SCAN_TICKS: number = MathMax(1, MathFloor(SCAN_INTERVAL / LOGIC_INTERVAL))

local AUTOFLAG_TOGGLE_KEY: string = "X"
local AUTOFLAG_MAX_RANGE: number = 17
local AUTOFLAG_CLICK_DELAY: number = 0.12
local AUTOFLAG_VERIFY_DELAY: number = 0.15
local AUTOFLAG_SMOOTHNESS: number = 0.6
local AUTOFLAG_CLICK_TOLERANCE: number = 6

local NEIGHBOR_OFFSETS: {{number}} = {
    {-1, -1}, {-1, 0}, {-1, 1},
    {0, -1},           {0, 1},
    {1, -1},  {1, 0},  {1, 1}
}

local DENSITY: number = 0.207
local DENSITY_RATIO: number = DENSITY / (1 - DENSITY)
local HARD_EQ_CAP: number = 512
local MAX_CLUSTER_VARS: number = 22
local MAX_BACKTRACK_SOLUTIONS: number = 50000

local RISK_EPSILON: number = 1e-9
local FALLBACK_RISK: number = 0.5
local MAX_ENTROPY_CANDIDATES: number = 10
local MAX_LOOKAHEAD_VARS: number = 22
local MAX_LOOKAHEAD_CANDIDATES: number = 6
local USE_ENTROPY_TIEBREAK: boolean = true
local LOOKAHEAD_ENABLED: boolean = true

local COLOR_MINE: Color3 = Color3.fromRGB(255, 40, 40)
local COLOR_SAFE: Color3 = Color3.fromRGB(50, 255, 50)
local COLOR_BEST: Color3 = Color3.fromRGB(0, 255, 255)
local COLOR_STATUS_ON: Color3 = Color3.fromRGB(60, 255, 60)
local COLOR_STATUS_OFF: Color3 = Color3.fromRGB(255, 60, 60)

local PROB_COLORS: {[number]: Color3} = TableCreate(101)
local PROB_TEXTS: {[number]: string} = TableCreate(101)

for pct = 0, 100 do
    local p: number = pct / 100
    local hue: number = 0.33 * (1 - p)
    local r, g, b: number, number, number = 0, 0, 0
    local h: number = hue * 6
    local c: number = 1
    local x: number = 1 - MathAbs(h % 2 - 1)
    
    if h < 1 then r, g, b = c, x, 0
    elseif h < 2 then r, g, b = x, c, 0
    elseif h < 3 then r, g, b = 0, c, x
    elseif h < 4 then r, g, b = 0, x, c
    elseif h < 5 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end
    
    PROB_COLORS[pct] = Color3.fromRGB(MathFloor(r * 255), MathFloor(g * 255), MathFloor(b * 255))
    PROB_TEXTS[pct] = tostring(pct) .. "%"
end

local WEIGHT_TABLE: {[number]: number} = TableCreate(51)
for k = 0, 50 do
    WEIGHT_TABLE[k] = MathPow(DENSITY_RATIO, k)
end

---- types ----
export type TileData = {
    part: BasePart?,
    gx: number,
    gz: number,
    tileType: string,
    number: number?,
    predicted: string | boolean,
    flagged: boolean,
    probability: number?,
    hasRevealedNeighbor: boolean?,
    constraintCount: number?,
    storedPos: Vector3?
}

export type AutoFlagEntry = {
    tile: TileData,
    time: number
}

export type CandidateData = {
    tile: TileData,
    distance: number,
    position: vector
}

export type Equation = {
    needed: number,
    vars: {number}
}

export type TankSystem = {
    unknownMap: {[TileData]: number},
    unknownList: {TileData},
    equations: {Equation},
    varToEqIndex: {{number}}
}

---- variables ----
_G.MS_RUN = true
_G.MS_AUTOFLAG = false

local Camera: Camera? = nil
local LocalPlayer: Player? = nil
local HumanoidRootPart: BasePart? = nil

local Tiles: {TileData} = TableCreate(625)
local Grid: {[string]: TileData} = {}
local TileCount: number = 0

local TablePool: {{any}} = TableCreate(64)
local QueuePool: {{any}} = TableCreate(32)
local InQueuePool: {{[number]: boolean}} = TableCreate(32)

local NeighborCache: {TileData} = TableCreate(8)

local PendingVerifications: {AutoFlagEntry} = TableCreate(20)
local LastClickTime: number = 0
local LockedTarget: CandidateData? = nil

local TickCount: number = 0
local LastChildCount: number = 0
local SolverChanged: boolean = false
local WasKeyPressed: boolean = false

local MS: Instance? = nil
local FLAG: Instance? = nil

local RenderData: {TileData} = TableCreate(625)
local RenderCount: number = 0

local FrontierTiles: {TileData} = TableCreate(200)
local FrontierCount: number = 0

local BestMove: TileData? = nil
local BestMoveRisk: number = 1
local LastTankSystem: TankSystem? = nil

---- helper functions ----

local function AcquireTable(): {any}
    local poolSize: number = #TablePool
    if poolSize > 0 then
        local t: {any} = TablePool[poolSize]
        TablePool[poolSize] = nil
        return t
    end
    return {}
end

local function ReleaseTable(t: {any}): ()
    TableClear(t)
    TablePool[#TablePool + 1] = t
end

local function AcquireQueues(): ({any}, {[number]: boolean})
    local qSize: number = #QueuePool
    local inqSize: number = #InQueuePool
    
    local q: {any}
    local inq: {[number]: boolean}
    
    if qSize > 0 then
        q = QueuePool[qSize]
        QueuePool[qSize] = nil
    else
        q = TableCreate(100)
    end
    
    if inqSize > 0 then
        inq = InQueuePool[inqSize]
        InQueuePool[inqSize] = nil
    else
        inq = {}
    end
    
    return q, inq
end

local function ReleaseQueues(q: {any}, inq: {[number]: boolean}): ()
    TableClear(q)
    TableClear(inq)
    QueuePool[#QueuePool + 1] = q
    InQueuePool[#InQueuePool + 1] = inq
end

local function SafeGetChildren(instance: Instance?): (boolean, {Instance}?)
    if not instance then return false, nil end
    
    local success: boolean, result: {Instance}? = Pcall(function()
        return instance:GetChildren()
    end)
    
    return success, result
end

local function SafeGetProperty<T>(instance: Instance?, propertyName: string): (boolean, T?)
    if not instance then return false, nil end
    
    local success: boolean, result: T? = Pcall(function()
        return (instance :: any)[propertyName]
    end)
    
    return success, result
end

local function SafeFindFirstChild(instance: Instance?, name: string): Instance?
    if not instance then return nil end
    
    local success: boolean, result: Instance? = Pcall(function()
        return instance:FindFirstChild(name)
    end)
    
    if success then
        return result
    end
    return nil
end

local function ValidateParent(instance: Instance?): boolean
    if not instance then return false end
    
    local success: boolean, parent: Instance? = SafeGetProperty(instance, "Parent")
    return success and parent ~= nil
end

local function SafeWorldToScreen(camera: Camera?, position: Vector3): (vector?, boolean)
    if not camera then return nil, false end
    
    local success: boolean, screenPos: Vector3?, onScreen: boolean? = Pcall(function()
        local sp, os = camera:WorldToScreenPoint(position)
        return sp, os
    end)
    
    if success and screenPos then
        return VectorCreate(screenPos.X, screenPos.Y, screenPos.Z), onScreen or false
    end
    
    return nil, false
end

local function SafeGetMousePosition(): vector?
    local success: boolean, pos: any = Pcall(function()
        return getmouseposition()
    end)
    
    if success and pos then
        return pos
    end
    
    return nil
end

local function SafeMouseMoveAbs(x: number, y: number): boolean
    local success: boolean = Pcall(function()
        mousemoveabs(x, y)
    end)
    
    return success
end

local function SafeMouse1Click(): boolean
    local success: boolean = Pcall(function()
        mouse1click()
    end)
    
    return success
end

local function GetDistance3D(pos1: vector, pos2: vector): number
    local diff: vector = pos1 - pos2
    return VectorMagnitude(diff)
end

local function GetDistance2D(x1: number, y1: number, x2: number, y2: number): number
    local dx: number = x1 - x2
    local dy: number = y1 - y2
    return MathSqrt(dx * dx + dy * dy)
end

local function GetRefPosition(): Vector3?
    if HumanoidRootPart and ValidateParent(HumanoidRootPart) then
        local success: boolean, pos: Vector3? = SafeGetProperty(HumanoidRootPart, "Position")
        if success and pos then
            return pos
        end
    end
    
    if Camera then
        local success: boolean, pos: Vector3? = SafeGetProperty(Camera, "Position")
        if success and pos then
            return pos
        end
    end
    
    return Vector3.new(0, 0, 0)
end

local function PosToKey(part: BasePart?): (string?, number?, number?)
    if not ValidateParent(part) then return nil, nil, nil end
    
    local success: boolean, pos: Vector3? = SafeGetProperty(part, "Position")
    if not success or not pos then return nil, nil, nil end
    
    local gx: number = MathFloor((pos.X - ORIGIN_X) / SPACING + 0.5)
    local gz: number = MathFloor((pos.Z - ORIGIN_Z) / SPACING + 0.5)
    
    return gx .. "|" .. gz, gx, gz
end

local function ClassifyTile(part: BasePart?): (string, number?)
    if not ValidateParent(part) then
        return "deleted", nil
    end
    
    local numberGui: Instance? = SafeFindFirstChild(part, "NumberGui")
    if numberGui then
        local label: Instance? = SafeFindFirstChild(numberGui, "TextLabel")
        if label then
            local success: boolean, text: string? = SafeGetProperty(label, "Text")
            if success and text and type(text) == "string" then
                if text == SAFE_TEXT or text == "" or text == " " then
                    return "empty", 0
                end
                local n: number? = tonumber(text)
                if n then
                    return "number", n
                end
            end
        end
    end
    
    local success: boolean, col: Color3? = SafeGetProperty(part, "Color")
    if success and col == MINE_COLOR then
        return "mine", nil
    end
    
    return "unknown", nil
end

local function GetNeighbors(t: TileData): {TileData}
    TableClear(NeighborCache)
    local count: number = 0
    
    for i = 1, 8 do
        local offset: {number} = NEIGHBOR_OFFSETS[i]
        local key: string = (t.gx + offset[1]) .. "|" .. (t.gz + offset[2])
        local neighbor: TileData? = Grid[key]
        if neighbor then
            count = count + 1
            NeighborCache[count] = neighbor
        end
    end
    
    return NeighborCache
end

local function GetNeighborsCopy(t: TileData): {TileData}
    local result: {TileData} = TableCreate(8)
    local count: number = 0
    
    for i = 1, 8 do
        local offset: {number} = NEIGHBOR_OFFSETS[i]
        local key: string = (t.gx + offset[1]) .. "|" .. (t.gz + offset[2])
        local neighbor: TileData? = Grid[key]
        if neighbor then
            count = count + 1
            result[count] = neighbor
        end
    end
    
    return result
end

local function IsAlreadyFlagged(part: BasePart?): boolean
    if not ValidateParent(part) then return false end
    
    if SafeFindFirstChild(part, "Flag") then return true end
    
    local success: boolean, transparency: number? = SafeGetProperty(part, "Transparency")
    if success and transparency and transparency > 0.9 then return true end
    
    local childSuccess: boolean, children: {Instance}? = SafeGetChildren(part)
    if childSuccess and children then
        for i = 1, #children do
            local child: Instance = children[i]
            local nameSuccess: boolean, name: string? = SafeGetProperty(child, "Name")
            if nameSuccess and name and type(name) == "string" then
                local nameLower: string = StringLower(name)
                if StringFind(nameLower, "flag") or StringFind(nameLower, "marker") then
                    return true
                end
            end
        end
    end
    
    return false
end

local function GenerateTile(part: BasePart): ()
    if not ValidateParent(part) then return end
    
    local key: string?, gx: number?, gz: number? = PosToKey(part)
    if not key or not gx or not gz then return end
    
    if Grid[key] then
        if Grid[key].part == part then return end
    end
    
    local tileType: string, val: number? = ClassifyTile(part)
    
    local posSuccess: boolean, pos: Vector3? = SafeGetProperty(part, "Position")
    
    local t: TileData = {
        part = part,
        gx = gx,
        gz = gz,
        tileType = tileType,
        number = val,
        predicted = false,
        flagged = false,
        probability = nil,
        hasRevealedNeighbor = nil,
        constraintCount = 0,
        storedPos = posSuccess and pos or nil
    }
    
    TileCount = TileCount + 1
    Tiles[TileCount] = t
    Grid[key] = t
end

local function RemoveTile(index: number): ()
    local t: TileData = Tiles[index]
    if t and t.gx and t.gz then
        Grid[t.gx .. "|" .. t.gz] = nil
    end
    
    Tiles[index] = Tiles[TileCount]
    Tiles[TileCount] = nil
    TileCount = TileCount - 1
end

local function SortAndUniq(vars: {number}): {number}
    TableSort(vars)
    local out: {number} = AcquireTable()
    local last: number? = nil
    
    for i = 1, #vars do
        local v: number = vars[i]
        if v ~= last then
            out[#out + 1] = v
            last = v
        end
    end
    
    return out
end

local function JoinNums(arr: {number}): string
    local out: {string} = AcquireTable()
    for i = 1, #arr do
        out[i] = tostring(arr[i])
    end
    local result: string = TableConcat(out, ",")
    ReleaseTable(out)
    return result
end

local function EqKey(eq: Equation): string
    return tostring(eq.needed) .. ":" .. JoinNums(eq.vars)
end

local function IsSubset(smaller: {number}, bigger: {number}): boolean
    local i: number, j: number = 1, 1
    while i <= #smaller and j <= #bigger do
        local a: number, b: number = smaller[i], bigger[j]
        if a == b then
            i = i + 1
            j = j + 1
        elseif a > b then
            j = j + 1
        else
            return false
        end
    end
    return i > #smaller
end

local function DiffVars(bigger: {number}, smaller: {number}): {number}
    local out: {number} = AcquireTable()
    local i: number, j: number = 1, 1
    
    while i <= #bigger do
        local b: number = bigger[i]
        local s: number? = smaller[j]
        
        if s == nil then
            out[#out + 1] = b
            i = i + 1
        elseif b == s then
            i = i + 1
            j = j + 1
        elseif b < s then
            out[#out + 1] = b
            i = i + 1
        else
            j = j + 1
        end
    end
    
    return out
end

local function ReduceEquations(localEqs: {Equation}): ({Equation}?, string)
    local normalized: {Equation} = TableCreate(#localEqs)
    local byVarSet: {[string]: number} = {}
    
    for i = 1, #localEqs do
        local eq: Equation = localEqs[i]
        local vars: {number} = SortAndUniq(eq.vars)
        local needed: number = eq.needed
        
        if needed < 0 or needed > #vars then
            ReleaseTable(vars)
            return nil, "contradiction"
        end
        
        local varSetKey: string = JoinNums(vars)
        local existing: number? = byVarSet[varSetKey]
        
        if existing == nil then
            byVarSet[varSetKey] = needed
            normalized[#normalized + 1] = { needed = needed, vars = vars }
        else
            if existing ~= needed then
                ReleaseTable(vars)
                return nil, "contradiction"
            end
            ReleaseTable(vars)
        end
    end
    
    local seen: {[string]: boolean} = {}
    for i = 1, #normalized do
        seen[EqKey(normalized[i])] = true
    end
    
    local changed: boolean = true
    local iterations: number = 0
    
    while changed and iterations < 100 do
        changed = false
        iterations = iterations + 1
        local normCount: number = #normalized
        
        for i = 1, normCount do
            local A: Equation = normalized[i]
            
            for j = 1, normCount do
                if i ~= j then
                    local B: Equation = normalized[j]
                    
                    if #A.vars > 0 and #A.vars < #B.vars then
                        if IsSubset(A.vars, B.vars) then
                            local diffNeeded: number = B.needed - A.needed
                            local diffVars: {number} = DiffVars(B.vars, A.vars)
                            
                            if diffNeeded < 0 or diffNeeded > #diffVars then
                                ReleaseTable(diffVars)
                                return nil, "contradiction"
                            end
                            
                            if #diffVars == 0 then
                                if diffNeeded ~= 0 then
                                    ReleaseTable(diffVars)
                                    return nil, "contradiction"
                                end
                                ReleaseTable(diffVars)
                            else
                                local newEq: Equation = { needed = diffNeeded, vars = diffVars }
                                local k: string = EqKey(newEq)
                                
                                if not seen[k] then
                                    seen[k] = true
                                    normalized[#normalized + 1] = newEq
                                    changed = true
                                    
                                    if #normalized > HARD_EQ_CAP then
                                        return normalized, "cap_hit"
                                    end
                                else
                                    ReleaseTable(diffVars)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    return normalized, "ok"
end

local function AnalyzeNeighbors(t: TileData): (number, {TileData})
    local adj: {TileData} = GetNeighbors(t)
    local knownMines: number = 0
    local unknowns: {TileData} = TableCreate(8)
    local unknownCount: number = 0
    
    for i = 1, #adj do
        local n: TileData = adj[i]
        if n.tileType == "mine" then
            knownMines = knownMines + 1
        elseif n.predicted == "mine" then
            knownMines = knownMines + 1
        elseif n.predicted == "safe" then
            -- Skip
        elseif n.tileType == "unknown" then
            unknownCount = unknownCount + 1
            unknowns[unknownCount] = n
        end
    end
    
    return knownMines, unknowns
end

local function RunTrivialPass(): boolean
    local progress: boolean = false
    
    for i = 1, TileCount do
        local tile: TileData = Tiles[i]
        
        if tile.tileType == "number" and tile.number then
            local knownMines: number, unknowns: {TileData} = AnalyzeNeighbors(tile)
            local need: number = tile.number - knownMines
            local unknownCount: number = #unknowns
            
            if unknownCount > 0 and need >= 0 then
                if need == 0 then
                    for j = 1, unknownCount do
                        local u: TileData = unknowns[j]
                        if u.predicted ~= "safe" then
                            u.predicted = "safe"
                            progress = true
                        end
                    end
                elseif need == unknownCount then
                    for j = 1, unknownCount do
                        local u: TileData = unknowns[j]
                        if u.predicted ~= "mine" then
                            u.predicted = "mine"
                            progress = true
                        end
                    end
                end
            end
        end
    end
    
    return progress
end

local function RunPairwiseAnalysis(): boolean
    local progress: boolean = false
    
    for i = 1, TileCount do
        local tileA: TileData = Tiles[i]
        
        if tileA.tileType == "number" and tileA.number then
            local minesA: number, unknownsA: {TileData} = AnalyzeNeighbors(tileA)
            local needA: number = tileA.number - minesA
            local countA: number = #unknownsA
            
            if countA > 0 and needA > 0 and needA < countA then
                local neighborsOfA: {TileData} = GetNeighborsCopy(tileA)
                
                for j = 1, #neighborsOfA do
                    local tileB: TileData = neighborsOfA[j]
                    
                    if tileB.tileType == "number" and tileB.number then
                        local minesB: number, unknownsB: {TileData} = AnalyzeNeighbors(tileB)
                        local needB: number = tileB.number - minesB
                        local countB: number = #unknownsB
                        
                        if countB > 0 and needB > 0 and needB < countB then
                            local setA: {[TileData]: boolean} = {}
                            for k = 1, countA do
                                setA[unknownsA[k]] = true
                            end
                            
                            local shared: {TileData} = TableCreate(8)
                            local sharedCount: number = 0
                            local onlyB: {TileData} = TableCreate(8)
                            local onlyBCount: number = 0
                            
                            for k = 1, countB do
                                local u: TileData = unknownsB[k]
                                if setA[u] then
                                    sharedCount = sharedCount + 1
                                    shared[sharedCount] = u
                                else
                                    onlyBCount = onlyBCount + 1
                                    onlyB[onlyBCount] = u
                                end
                            end
                            
                            if sharedCount > 0 and onlyBCount > 0 then
                                local minSharedMines: number = MathMax(0, needA - (countA - sharedCount))
                                local maxSharedMines: number = MathMin(needA, sharedCount)
                                
                                local minOnlyBMines: number = needB - maxSharedMines
                                local maxOnlyBMines: number = needB - minSharedMines
                                
                                if minOnlyBMines == onlyBCount then
                                    for k = 1, onlyBCount do
                                        local u: TileData = onlyB[k]
                                        if u.predicted ~= "mine" then
                                            u.predicted = "mine"
                                            progress = true
                                        end
                                    end
                                elseif maxOnlyBMines == 0 then
                                    for k = 1, onlyBCount do
                                        local u: TileData = onlyB[k]
                                        if u.predicted ~= "safe" then
                                            u.predicted = "safe"
                                            progress = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    return progress
end

local function BuildFrontier(): ()
    FrontierCount = 0
    
    for i = 1, TileCount do
        local t: TileData = Tiles[i]
        t.hasRevealedNeighbor = nil
        t.constraintCount = 0
        
        if t.tileType == "unknown" and t.predicted == false then
            local neighbors: {TileData} = GetNeighbors(t)
            local hasRevealed: boolean = false
            local constraints: number = 0
            
            for j = 1, #neighbors do
                local n: TileData = neighbors[j]
                if n.tileType == "number" then
                    hasRevealed = true
                    constraints = constraints + 1
                elseif n.tileType == "empty" then
                    hasRevealed = true
                end
            end
            
            t.hasRevealedNeighbor = hasRevealed
            t.constraintCount = constraints
            
            if hasRevealed then
                FrontierCount = FrontierCount + 1
                FrontierTiles[FrontierCount] = t
            end
        end
    end
end

local function GetTileRisk(tile: TileData): number
    if tile.predicted == "mine" then return 1 end
    if tile.predicted == "safe" then return 0 end
    if tile.probability ~= nil then return tile.probability end
    return FALLBACK_RISK
end

local function Entropy(dist: {number}): number
    local h: number = 0
    for i = 1, #dist do
        local p: number = dist[i]
        if p and p > 0 then
            h = h - (p * MathLog(p))
        end
    end
    return h
end

local function EstimateNeighborMineCountDist(tile: TileData): {number}
    local neighbors: {TileData} = GetNeighborsCopy(tile)
    local baseMines: number = 0
    local probs: {number} = TableCreate(8)
    local probCount: number = 0
    
    for i = 1, #neighbors do
        local n: TileData = neighbors[i]
        if n.tileType == "mine" or n.predicted == "mine" then
            baseMines = baseMines + 1
        elseif n.tileType == "unknown" and n.predicted ~= "safe" then
            probCount = probCount + 1
            probs[probCount] = GetTileRisk(n)
        end
    end
    
    local dist: {[number]: number} = { [0] = 1 }
    
    for i = 1, probCount do
        local p: number = probs[i]
        local nextDist: {[number]: number} = {}
        
        for k, v in pairs(dist) do
            nextDist[k] = (nextDist[k] or 0) + v * (1 - p)
            nextDist[k + 1] = (nextDist[k + 1] or 0) + v * p
        end
        
        dist = nextDist
    end
    
    local out: {number} = TableCreate(9)
    for k = 0, 8 do
        out[k + 1] = 0
    end
    
    for k, v in pairs(dist) do
        local kk: number = k + baseMines
        if kk >= 0 and kk <= 8 then
            out[kk + 1] = out[kk + 1] + v
        end
    end
    
    local s: number = 0
    for i = 1, #out do
        s = s + out[i]
    end
    
    if s > 0 then
        for i = 1, #out do
            out[i] = out[i] / s
        end
    end
    
    return out
end

local function PickBestMove(): (TileData?, number)
    local bestRisk: number = 2
    local candidates: {TileData} = TableCreate(100)
    local candidateCount: number = 0
    
    for i = 1, TileCount do
        local t: TileData = Tiles[i]
        
        if t.tileType == "unknown" and t.predicted ~= "mine" then
            local r: number = t.probability or FALLBACK_RISK
            if t.predicted == "safe" then r = 0 end
            
            if r < bestRisk - RISK_EPSILON then
                bestRisk = r
                candidateCount = 1
                candidates[1] = t
            elseif MathAbs(r - bestRisk) <= RISK_EPSILON then
                candidateCount = candidateCount + 1
                candidates[candidateCount] = t
            end
        end
    end
    
    if candidateCount == 0 then
        return nil, 1
    end
    
    local refPos: Vector3? = GetRefPosition()
    
    if candidateCount > 1 and refPos then
        TableSort(candidates, function(a: TileData, b: TileData): boolean
            local posA: Vector3? = a.storedPos
            local posB: Vector3? = b.storedPos
            
            if not posA then return false end
            if not posB then return true end
            
            local distA: number = (posA - refPos).Magnitude
            local distB: number = (posB - refPos).Magnitude
            
            return distA < distB
        end)
    end
    
    if bestRisk == 0 then
        return candidates[1], 0
    end
    
    local bestTile: TileData = candidates[1]
    local bestScore: number = -1
    local maxC: number = MathMin(candidateCount, MAX_LOOKAHEAD_CANDIDATES)
    
    for i = 1, maxC do
        local t: TileData = candidates[i]
        local s: number? = nil
        
        if USE_ENTROPY_TIEBREAK then
            local dist: {number} = EstimateNeighborMineCountDist(t)
            local risk: number = t.probability or FALLBACK_RISK
            s = (1 - risk) * Entropy(dist)
        end
        
        if not s then
            local open: number = 0
            local neighbors: {TileData} = GetNeighborsCopy(t)
            
            for j = 1, #neighbors do
                local n: TileData = neighbors[j]
                if n.tileType == "unknown" and n.predicted ~= "mine" then
                    open = open + 1
                end
            end
            
            s = open * 0.01
        end
        
        if s > bestScore then
            bestScore = s
            bestTile = t
        end
    end
    
    return bestTile, bestRisk
end

local function RunTankSolver(): boolean
    local madeProgress: boolean = false
    
    BuildFrontier()
    
    if FrontierCount == 0 then return false end
    
    local unknownMap: {[TileData]: number} = {}
    local unknownList: {TileData} = TableCreate(FrontierCount)
    local equations: {Equation} = TableCreate(100)
    local unknownCount: number = 0
    
    for i = 1, FrontierCount do
        local tile: TileData = FrontierTiles[i]
        if not unknownMap[tile] then
            unknownCount = unknownCount + 1
            unknownList[unknownCount] = tile
            unknownMap[tile] = unknownCount
        end
    end
    
    for i = 1, TileCount do
        local tile: TileData = Tiles[i]
        
        if tile.tileType == "number" and tile.number then
            local knownMines: number, unknowns: {TileData} = AnalyzeNeighbors(tile)
            local needed: number = tile.number - knownMines
            local eqVars: {number} = TableCreate(8)
            local eqVarCount: number = 0
            
            for j = 1, #unknowns do
                local uTile: TileData = unknowns[j]
                local varId: number? = unknownMap[uTile]
                if varId then
                    eqVarCount = eqVarCount + 1
                    eqVars[eqVarCount] = varId
                end
            end
            
            if eqVarCount > 0 and needed >= 0 and needed <= eqVarCount then
                equations[#equations + 1] = { needed = needed, vars = eqVars }
            end
        end
    end
    
    if unknownCount == 0 then return false end
    
    local varToEqIndex: {{number}} = TableCreate(unknownCount)
    for i = 1, unknownCount do
        varToEqIndex[i] = TableCreate(4)
    end
    
    for eqIdx = 1, #equations do
        local eq: Equation = equations[eqIdx]
        for j = 1, #eq.vars do
            local varId: number = eq.vars[j]
            local list: {number} = varToEqIndex[varId]
            list[#list + 1] = eqIdx
        end
    end
    
    LastTankSystem = {
        unknownMap = unknownMap,
        unknownList = unknownList,
        equations = equations,
        varToEqIndex = varToEqIndex
    }
    
    local visitedVars: {[number]: boolean} = {}
    local clusters: {{vars: {number}, eqs: {Equation}}} = TableCreate(10)
    
    for i = 1, unknownCount do
        if not visitedVars[i] then
            local clusterVars: {number} = TableCreate(50)
            local clusterEqs: {Equation} = TableCreate(50)
            local queue: {number} = TableCreate(50)
            local processedEqs: {[number]: boolean} = {}
            
            queue[1] = i
            visitedVars[i] = true
            local head: number = 1
            local queueSize: number = 1
            
            while head <= queueSize do
                local currVar: number = queue[head]
                head = head + 1
                clusterVars[#clusterVars + 1] = currVar
                
                local eqList: {number} = varToEqIndex[currVar]
                for j = 1, #eqList do
                    local eqIdx: number = eqList[j]
                    
                    if not processedEqs[eqIdx] then
                        processedEqs[eqIdx] = true
                        clusterEqs[#clusterEqs + 1] = equations[eqIdx]
                        
                        local eq: Equation = equations[eqIdx]
                        for k = 1, #eq.vars do
                            local neighborVar: number = eq.vars[k]
                            
                            if not visitedVars[neighborVar] then
                                visitedVars[neighborVar] = true
                                queueSize = queueSize + 1
                                queue[queueSize] = neighborVar
                            end
                        end
                    end
                end
            end
            
            clusters[#clusters + 1] = { vars = clusterVars, eqs = clusterEqs }
        end
    end
    
    for clusterIdx = 1, #clusters do
        local cluster = clusters[clusterIdx]
        
        if #cluster.vars <= MAX_CLUSTER_VARS then
            local orderedVars: {number} = TableCreate(#cluster.vars)
            for i = 1, #cluster.vars do
                orderedVars[i] = cluster.vars[i]
            end
            
            local degree: {[number]: number} = {}
            for i = 1, #orderedVars do
                degree[orderedVars[i]] = 0
            end
            
            for i = 1, #cluster.eqs do
                local eq: Equation = cluster.eqs[i]
                for j = 1, #eq.vars do
                    local globId: number = eq.vars[j]
                    if degree[globId] ~= nil then
                        degree[globId] = degree[globId] + 1
                    end
                end
            end
            
            TableSort(orderedVars, function(a: number, b: number): boolean
                return (degree[a] or 0) > (degree[b] or 0)
            end)
            
            local globalToLocal: {[number]: number} = {}
            local localToGlobal: {number} = TableCreate(#orderedVars)
            
            for locIdx = 1, #orderedVars do
                local globId: number = orderedVars[locIdx]
                globalToLocal[globId] = locIdx
                localToGlobal[locIdx] = globId
            end
            
            local nVars: number = #orderedVars
            local localEqs: {Equation} = TableCreate(#cluster.eqs)
            
            for i = 1, #cluster.eqs do
                local eq: Equation = cluster.eqs[i]
                local vars: {number} = TableCreate(#eq.vars)
                
                for j = 1, #eq.vars do
                    vars[j] = globalToLocal[eq.vars[j]]
                end
                
                localEqs[#localEqs + 1] = { needed = eq.needed, vars = vars }
            end
            
            local reducedEqs: {Equation}?, reduceStatus: string = ReduceEquations(localEqs)
            
            if reducedEqs then
                local varToEqs: {{number}} = TableCreate(nVars)
                for v = 1, nVars do
                    varToEqs[v] = TableCreate(4)
                end
                
                for eqIdx = 1, #reducedEqs do
                    local eq: Equation = reducedEqs[eqIdx]
                    for j = 1, #eq.vars do
                        local v: number = eq.vars[j]
                        local list: {number} = varToEqs[v]
                        list[#list + 1] = eqIdx
                    end
                end
                
                local varDegree: {number} = TableCreate(nVars)
                for v = 1, nVars do
                    varDegree[v] = #varToEqs[v]
                end
                
                local assignment: {[number]: number} = {}
                local eqMines: {number} = TableCreate(#reducedEqs)
                local eqUnk: {number} = TableCreate(#reducedEqs)
                
                for eqIdx = 1, #reducedEqs do
                    local eq: Equation = reducedEqs[eqIdx]
                    eqMines[eqIdx] = 0
                    eqUnk[eqIdx] = #eq.vars
                end
                
                local solutionHits: {{[number]: number}} = TableCreate(nVars)
                for v = 1, nVars do
                    solutionHits[v] = {}
                end
                local totalWeightLocal: number = 0
                local solutionCount: number = 0
                
                local function EnqueueEq(q: {number}, inQueue: {[number]: boolean}, eqIdx: number): ()
                    if not inQueue[eqIdx] then
                        inQueue[eqIdx] = true
                        q[#q + 1] = eqIdx
                    end
                end
                
                local function AssignVar(v: number, val: number, trail: {{v: number, val: number}}, q: {number}, inQueue: {[number]: boolean}): boolean
                    if assignment[v] ~= nil then
                        return assignment[v] == val
                    end
                    
                    assignment[v] = val
                    trail[#trail + 1] = { v = v, val = val }
                    
                    local eqList: {number} = varToEqs[v]
                    for i = 1, #eqList do
                        local eqIdx: number = eqList[i]
                        eqUnk[eqIdx] = eqUnk[eqIdx] - 1
                        eqMines[eqIdx] = eqMines[eqIdx] + val
                        EnqueueEq(q, inQueue, eqIdx)
                    end
                    
                    return true
                end
                
                local function UndoTo(trail: {{v: number, val: number}}, targetSize: number): ()
                    while #trail > targetSize do
                        local rec = trail[#trail]
                        trail[#trail] = nil
                        local v: number, val: number = rec.v, rec.val
                        assignment[v] = nil
                        
                        local eqList: {number} = varToEqs[v]
                        for i = 1, #eqList do
                            local eqIdx: number = eqList[i]
                            eqUnk[eqIdx] = eqUnk[eqIdx] + 1
                            eqMines[eqIdx] = eqMines[eqIdx] - val
                        end
                    end
                end
                
                local function Propagate(trail: {{v: number, val: number}}, q: {number}, inQueue: {[number]: boolean}): boolean
                    local head: number = 1
                    
                    while head <= #q do
                        local eqIdx: number = q[head]
                        head = head + 1
                        inQueue[eqIdx] = false
                        
                        local eq: Equation = reducedEqs[eqIdx]
                        local need: number = eq.needed
                        local mines: number = eqMines[eqIdx]
                        local unk: number = eqUnk[eqIdx]
                        
                        if mines > need then return false end
                        if mines + unk < need then return false end
                        
                        if unk > 0 then
                            if mines == need then
                                for j = 1, #eq.vars do
                                    local v: number = eq.vars[j]
                                    if assignment[v] == nil then
                                        if not AssignVar(v, 0, trail, q, inQueue) then
                                            return false
                                        end
                                    end
                                end
                            elseif mines + unk == need then
                                for j = 1, #eq.vars do
                                    local v: number = eq.vars[j]
                                    if assignment[v] == nil then
                                        if not AssignVar(v, 1, trail, q, inQueue) then
                                            return false
                                        end
                                    end
                                end
                            end
                        else
                            if mines ~= need then return false end
                        end
                    end
                    
                    return true
                end
                
                local function PickNextVar(): number?
                    local bestV: number? = nil
                    local bestScore: number = -1
                    
                    for v = 1, nVars do
                        if assignment[v] == nil then
                            local score: number = varDegree[v]
                            if score > bestScore then
                                bestScore = score
                                bestV = v
                            end
                        end
                    end
                    
                    return bestV
                end
                
                local function Backtrack(trail: {{v: number, val: number}}): ()
                    if solutionCount >= MAX_BACKTRACK_SOLUTIONS then return end
                    
                    local v: number? = PickNextVar()
                    
                    if not v then
                        solutionCount = solutionCount + 1
                        local m: number = 0
                        for i = 1, nVars do
                            if assignment[i] == 1 then
                                m = m + 1
                            end
                        end
                        
                        local w: number = WEIGHT_TABLE[m] or 1
                        totalWeightLocal = totalWeightLocal + w
                        
                        for i = 1, nVars do
                            if assignment[i] == 1 then
                                solutionHits[i][m] = (solutionHits[i][m] or 0) + 1
                            end
                        end
                        return
                    end
                    
                    do
                        local saved: number = #trail
                        local q: {number}, inQueue: {[number]: boolean} = AcquireQueues()
                        
                        if AssignVar(v, 0, trail, q, inQueue) and Propagate(trail, q, inQueue) then
                            Backtrack(trail)
                        end
                        
                        ReleaseQueues(q, inQueue)
                        UndoTo(trail, saved)
                    end
                    
                    do
                        local saved: number = #trail
                        local q: {number}, inQueue: {[number]: boolean} = AcquireQueues()
                        
                        if AssignVar(v, 1, trail, q, inQueue) and Propagate(trail, q, inQueue) then
                            Backtrack(trail)
                        end
                        
                        ReleaseQueues(q, inQueue)
                        UndoTo(trail, saved)
                    end
                end
                
                local trail: {{v: number, val: number}} = TableCreate(nVars)
                local q: {number}, inQueue: {[number]: boolean} = AcquireQueues()
                
                for eqIdx = 1, #reducedEqs do
                    EnqueueEq(q, inQueue, eqIdx)
                end
                
                if Propagate(trail, q, inQueue) then
                    Backtrack(trail)
                end
                
                ReleaseQueues(q, inQueue)
                
                if totalWeightLocal > 0 then
                    for locIdx = 1, #orderedVars do
                        local globId: number = localToGlobal[locIdx]
                        local tile: TileData = unknownList[globId]
                        
                        local weightedHits: number = 0
                        local hitsMap: {[number]: number} = solutionHits[locIdx]
                        
                        for m, count in pairs(hitsMap) do
                            local w: number = WEIGHT_TABLE[m] or 1
                            weightedHits = weightedHits + (count * w)
                        end
                        
                        local prob: number = weightedHits / totalWeightLocal
                        
                        if prob < 0 then prob = 0 end
                        if prob > 1 then prob = 1 end
                        
                        tile.probability = prob
                        
                        if prob < 1e-9 and tile.predicted ~= "safe" then
                            tile.predicted = "safe"
                            madeProgress = true
                        elseif prob > 1 - 1e-9 and tile.predicted ~= "mine" then
                            tile.predicted = "mine"
                            madeProgress = true
                        end
                    end
                end
            end
        end
    end
    
    return madeProgress
end

local function SolveAll(): ()
    for i = 1, TileCount do
        local tile: TileData = Tiles[i]
        if tile.tileType == "unknown" then
            tile.predicted = false
            tile.probability = nil
        end
    end
    
    for _ = 1, 15 do
        local trivialProgress: boolean = RunTrivialPass()
        local pairwiseProgress: boolean = RunPairwiseAnalysis()
        if not trivialProgress and not pairwiseProgress then
            break
        end
    end
    
    if RunTankSolver() then
        for _ = 1, 5 do
            if not RunTrivialPass() then break end
        end
    end
    
    BestMove, BestMoveRisk = PickBestMove()
end

local function VerifyPendingFlags(): ()
    local currentTime: number = OsClock()
    
    for i = #PendingVerifications, 1, -1 do
        local entry: AutoFlagEntry = PendingVerifications[i]
        
        if currentTime - entry.time >= AUTOFLAG_VERIFY_DELAY then
            local tile: TileData = entry.tile
            
            if tile.part and ValidateParent(tile.part) then
                if IsAlreadyFlagged(tile.part) or tile.tileType == "mine" then
                    tile.flagged = true
                    
                    if LockedTarget and LockedTarget.tile == tile then
                        LockedTarget = nil
                    end
                else
                    tile.flagged = false
                end
            end
            
            TableRemove(PendingVerifications, i)
        end
    end
end

local function GetNearbyMines(): {CandidateData}
    local candidates: {CandidateData} = TableCreate(50)
    local candidateCount: number = 0
    
    if not HumanoidRootPart or not ValidateParent(HumanoidRootPart) then
        return candidates
    end
    
    local success: boolean, charPos: Vector3? = SafeGetProperty(HumanoidRootPart, "Position")
    if not success or not charPos then return candidates end
    
    local charVec: vector = VectorCreate(charPos.X, charPos.Y, charPos.Z)
    
    for i = 1, TileCount do
        local tile: TileData = Tiles[i]
        
        if tile.predicted == "mine" and not tile.flagged and tile.tileType ~= "mine" then
            if tile.part and ValidateParent(tile.part) then
                if not IsAlreadyFlagged(tile.part) then
                    local posSuccess: boolean, tilePos: Vector3? = SafeGetProperty(tile.part, "Position")
                    
                    if posSuccess and tilePos then
                        local tileVec: vector = VectorCreate(tilePos.X, tilePos.Y, tilePos.Z)
                        local dist: number = GetDistance3D(charVec, tileVec)
                        
                        if dist <= AUTOFLAG_MAX_RANGE then
                            candidateCount = candidateCount + 1
                            candidates[candidateCount] = {
                                tile = tile,
                                distance = dist,
                                position = tileVec
                            }
                        end
                    end
                end
            end
        end
    end
    
    TableSort(candidates, function(a: CandidateData, b: CandidateData): boolean
        return a.distance < b.distance
    end)
    
    return candidates
end

local LastTargetScreenPos: vector? = nil
local MouseStableFrames: number = 0

local function ProcessAutoFlag(): ()
    if not _G.MS_AUTOFLAG then
        LockedTarget = nil
        LastTargetScreenPos = nil
        MouseStableFrames = 0
        return
    end
    
    VerifyPendingFlags()
    
    local currentTime: number = OsClock()
    
    if LockedTarget then
        local tile: TileData = LockedTarget.tile
        
        if not tile.part or not ValidateParent(tile.part) or tile.flagged or
           IsAlreadyFlagged(tile.part) or tile.tileType ~= "unknown" then
            LockedTarget = nil
            LastTargetScreenPos = nil
            MouseStableFrames = 0
        end
    end
    
    if not LockedTarget then
        local nearbyMines: {CandidateData} = GetNearbyMines()
        
        if #nearbyMines > 0 then
            LockedTarget = nearbyMines[1]
            LastTargetScreenPos = nil
            MouseStableFrames = 0
        end
    end
    
    if LockedTarget and Camera then
        local worldPos: Vector3 = Vector3.new(LockedTarget.position.X, LockedTarget.position.Y, LockedTarget.position.Z)
        local screenPos: vector?, onScreen: boolean = SafeWorldToScreen(Camera, worldPos)
        
        if screenPos and onScreen then
            local currentMouse: vector? = SafeGetMousePosition()
            
            if currentMouse then
                local distToTarget: number = GetDistance2D(currentMouse.X, currentMouse.Y, screenPos.X, screenPos.Y)
                
                if distToTarget > AUTOFLAG_CLICK_TOLERANCE then
                    local lerpedX: number = currentMouse.X + (screenPos.X - currentMouse.X) * AUTOFLAG_SMOOTHNESS
                    local lerpedY: number = currentMouse.Y + (screenPos.Y - currentMouse.Y) * AUTOFLAG_SMOOTHNESS
                    
                    SafeMouseMoveAbs(lerpedX, lerpedY)
                    MouseStableFrames = 0
                else
                    MouseStableFrames = MouseStableFrames + 1
                    
                    if MouseStableFrames >= 3 and currentTime - LastClickTime >= AUTOFLAG_CLICK_DELAY then
                        if not IsAlreadyFlagged(LockedTarget.tile.part) then
                            local tileType: string = ClassifyTile(LockedTarget.tile.part)
                            
                            if tileType == "unknown" then
                                local clickSuccess: boolean = SafeMouse1Click()
                                
                                if clickSuccess then
                                    LastClickTime = currentTime
                                    LockedTarget.tile.flagged = true
                                    
                                    PendingVerifications[#PendingVerifications + 1] = {
                                        tile = LockedTarget.tile,
                                        time = currentTime
                                    }
                                    
                                    LockedTarget = nil
                                    LastTargetScreenPos = nil
                                    MouseStableFrames = 0
                                end
                            else
                                LockedTarget = nil
                                LastTargetScreenPos = nil
                                MouseStableFrames = 0
                            end
                        else
                            LockedTarget.tile.flagged = true
                            LockedTarget = nil
                            LastTargetScreenPos = nil
                            MouseStableFrames = 0
                        end
                    end
                end
                
                LastTargetScreenPos = screenPos
            end
        else
            LockedTarget = nil
            LastTargetScreenPos = nil
            MouseStableFrames = 0
        end
    end
end

local function ProcessInput(): ()
    local isPressed: boolean = false
    
    local success: boolean, pressedKeys: {any}? = Pcall(function()
        return getpressedkeys()
    end)
    
    if success and pressedKeys then
        for i = 1, #pressedKeys do
            local key: any = pressedKeys[i]
            
            if type(key) == "string" then
                if StringUpper(key) == AUTOFLAG_TOGGLE_KEY then
                    isPressed = true
                    break
                end
            elseif type(key) == "number" then
                if key == 0x58 or key == 88 or key == StringByte("X") then
                    isPressed = true
                    break
                end
            end
        end
    end
    
    if isPressed and not WasKeyPressed then
        _G.MS_AUTOFLAG = not _G.MS_AUTOFLAG
    end
    
    WasKeyPressed = isPressed
end

local function UpdateReferences(): ()
    local camSuccess: boolean, cam: Camera? = Pcall(function()
        return Workspace.CurrentCamera
    end)
    
    if camSuccess and cam then
        Camera = cam
    end
    
    local playerSuccess: boolean, player: Player? = Pcall(function()
        return Players.LocalPlayer
    end)
    
    if playerSuccess and player then
        LocalPlayer = player
        
        local charSuccess: boolean, character: Model? = Pcall(function()
            return player.Character
        end)
        
        if charSuccess and character then
            HumanoidRootPart = SafeFindFirstChild(character, "HumanoidRootPart") :: BasePart?
        else
            HumanoidRootPart = nil
        end
    else
        LocalPlayer = nil
        HumanoidRootPart = nil
    end
end

local function ScanForNewTiles(): ()
    if not MS then return end
    
    local success: boolean, children: {Instance}? = SafeGetChildren(MS)
    if not success or not children then return end
    
    local curCount: number = #children
    
    if curCount ~= LastChildCount then
        if LastChildCount < 10 and curCount > 100 then
            TableClear(Tiles)
            TableClear(Grid)
            TileCount = 0
            RenderCount = 0
            
            for i = 1, #children do
                local part: Instance = children[i]
                if part.ClassName == "Part" or part.ClassName == "MeshPart" then
                    GenerateTile(part :: BasePart)
                end
            end
            
            SolverChanged = true
        else
            for i = 1, #children do
                local part: Instance = children[i]
                local key: string? = PosToKey(part :: BasePart)
                
                if key and not Grid[key] then
                    GenerateTile(part :: BasePart)
                    SolverChanged = true
                end
            end
            
            for i = TileCount, 1, -1 do
                local t: TileData = Tiles[i]
                if not t.part or not ValidateParent(t.part) then
                    RemoveTile(i)
                    SolverChanged = true
                end
            end
        end
        
        LastChildCount = curCount
    end
end

local function ReclassifyTiles(): ()
    for i = 1, TileCount do
        local t: TileData = Tiles[i]
        
        local newType: string, newNumber: number? = ClassifyTile(t.part)
        
        if newType ~= t.tileType or newNumber ~= t.number then
            t.tileType = newType
            t.number = newNumber
            t.hasRevealedNeighbor = nil
            
            if t.part and ValidateParent(t.part) then
                local posSuccess: boolean, pos: Vector3? = SafeGetProperty(t.part, "Position")
                if posSuccess and pos then
                    t.storedPos = pos
                end
            end
            
            SolverChanged = true
        end
    end
end

local function PrepareRenderData(): ()
    RenderCount = 0
    
    for i = 1, TileCount do
        local t: TileData = Tiles[i]
        
        if t.tileType == "unknown" then
            if t.predicted == "mine" or t.predicted == "safe" then
                RenderCount = RenderCount + 1
                RenderData[RenderCount] = t
            elseif t.probability and t.probability > 0.01 and t.probability < 0.99 then
                if t.hasRevealedNeighbor == nil then
                    t.hasRevealedNeighbor = false
                    local neighbors: {TileData} = GetNeighbors(t)
                    
                    for j = 1, #neighbors do
                        local n: TileData = neighbors[j]
                        if n.tileType == "number" or n.tileType == "empty" then
                            t.hasRevealedNeighbor = true
                            break
                        end
                    end
                end
                
                if t.hasRevealedNeighbor then
                    RenderCount = RenderCount + 1
                    RenderData[RenderCount] = t
                end
            end
        end
    end
end

local function Initialize(): ()
    UpdateReferences()
    
    FLAG = SafeFindFirstChild(Workspace, FLAG_NAME)
    
    if FLAG then
        MS = SafeFindFirstChild(FLAG, PARTS_NAME)
    else
        local wsSuccess: boolean, wsChildren: {Instance}? = SafeGetChildren(Workspace)
        if wsSuccess and wsChildren then
            for i = 1, #wsChildren do
                local child: Instance = wsChildren[i]
                local partsFolder: Instance? = SafeFindFirstChild(child, PARTS_NAME)
                if partsFolder then
                    FLAG = child
                    MS = partsFolder
                    break
                end
            end
        end
    end
    
    if MS then
        local success: boolean, children: {Instance}? = SafeGetChildren(MS)
        
        if success and children then
            LastChildCount = #children
            
            for i = 1, #children do
                local part: Instance = children[i]
                GenerateTile(part :: BasePart)
            end
        end
    end
    
    SolverChanged = true
    SolveAll()
    PrepareRenderData()
end

---- runtime ----

local function SafeDrawText(position: vector, size: number, color: Color3, transparency: number, text: string, centered: boolean): ()
    if not position or not color or not text then return end
    
    Pcall(function()
        DrawingImmediate.OutlinedText(position, size, color, transparency, text, centered, nil)
    end)
end

local function SafePostModel(): ()
    if not _G.MS_RUN then return end
    
    TickCount = TickCount + 1
    
    if (TickCount % SCAN_TICKS) == 0 then
        Pcall(ScanForNewTiles)
    end
    
    Pcall(ReclassifyTiles)
    
    if SolverChanged then
        Pcall(SolveAll)
        SolverChanged = false
    end
    
    Pcall(PrepareRenderData)
end

local function SafePreLocal(): ()
    if not _G.MS_RUN then return end
    
    Pcall(UpdateReferences)
    Pcall(ProcessInput)
    Pcall(ProcessAutoFlag)
end

local function SafeRender(): ()
    if not _G.MS_RUN then return end
    if not Camera then return end
    
    local statusColor: Color3 = _G.MS_AUTOFLAG and COLOR_STATUS_ON or COLOR_STATUS_OFF
    local statusText: string = _G.MS_AUTOFLAG and "AUTO-FLAG: ON (X)" or "AUTO-FLAG: OFF (X)"
    
    SafeDrawText(VectorCreate(12, 805, 0), 16, statusColor, 1, statusText, false)
    
    if BestMove and BestMove.part and ValidateParent(BestMove.part) then
        local success: boolean, pos: Vector3? = SafeGetProperty(BestMove.part, "Position")
        
        if success and pos then
            local screenPos: vector?, onScreen: boolean = SafeWorldToScreen(Camera, pos)
            
            if screenPos and onScreen then
                local riskText: string = "BEST"
                if BestMoveRisk > 0 then
                    local pct: number = MathFloor(BestMoveRisk * 100 + 0.5)
                    riskText = "BEST (" .. tostring(pct) .. "%)"
                end
                
                SafeDrawText(VectorCreate(screenPos.X, screenPos.Y - 30, 0), 18, COLOR_BEST, 1, riskText, true)
            end
        end
    end
    
    local renderCount: number = RenderCount
    if renderCount <= 0 then return end
    
    for i = 1, renderCount do
        local t: TileData? = RenderData[i]
        
        if t and t.part and ValidateParent(t.part) then
            local success: boolean, pos: Vector3? = SafeGetProperty(t.part, "Position")
            
            if success and pos then
                local screenPos: vector?, onScreen: boolean = SafeWorldToScreen(Camera, pos)
                
                if screenPos and onScreen then
                    local screenVec: vector = VectorCreate(screenPos.X, screenPos.Y, 0)
                    
                    if t.predicted == "mine" then
                        SafeDrawText(screenVec, 22, COLOR_MINE, 1, "M", true)
                    elseif t.predicted == "safe" then
                        SafeDrawText(screenVec, 22, COLOR_SAFE, 1, "S", true)
                    elseif t.probability and t.probability > 0 and t.probability < 1 then
                        local pct: number = MathFloor(t.probability * 100 + 0.5)
                        if pct <= 0 then pct = 1 end
                        if pct >= 100 then pct = 99 end
                        
                        local probColor: Color3? = PROB_COLORS[pct]
                        local probText: string? = PROB_TEXTS[pct]
                        
                        if probColor and probText then
                            SafeDrawText(screenVec, 22, probColor, 1, probText, true)
                        end
                    end
                end
            end
        end
    end
end

Pcall(Initialize)

RunService.PostModel:Connect(function(): ()
    Pcall(SafePostModel)
end)

RunService.PostLocal:Connect(function(): ()
    Pcall(SafePreLocal)
end)

RunService.Render:Connect(function(): ()
    Pcall(SafeRender)
end)
