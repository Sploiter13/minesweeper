--!native
--!optimize 2

memory.set_write_strength(0.002)

---- environment ----
local loadSuccess: boolean = pcall(function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Sploiter13/severefuncs/refs/heads/main/merge2.lua"))()
end)

task.wait(0.5)

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
local MathRandom = math.random
local MathSin = math.sin
local MathCos = math.cos

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

local CLEANUP_INTERVAL: number = 20
local CLEANUP_POOL_MAX: number = 24
local STALE_TILE_CHECK_INTERVAL: number = 10
local DEEP_CLEANUP_INTERVAL: number = 60

local PathOpenSet: {PathNode} = TableCreate(100)
local PathCameFrom: {[string]: string} = {}
local PathGScore: {[string]: number} = {}
local PathFScore: {[string]: number} = {}
local PathClosedSet: {[string]: boolean} = {}

local MAX_TILES: number = 1000
local MAX_RENDER_TILES: number = 200
local MAX_FRONTIER_TILES: number = 300
local MAX_PENDING_VERIFICATIONS: number = 30
local MAX_PATH_ITERATIONS: number = 400
local MAX_PATH_LENGTH: number = 100

local RENDER_SKIP_FRAMES: number = 0
local AUTOFLAG_SCAN_INTERVAL: number = 0.15
local AUTOFLAG_MAX_CANDIDATES: number = 20

local AUTOFLAG_TOGGLE_KEY: string = "X"
local AUTOWALK_TOGGLE_KEY: string = "C"
local AUTOFLAG_MAX_RANGE: number = 17
local AUTOFLAG_CLICK_DELAY: number = 0.08
local AUTOFLAG_VERIFY_DELAY: number = 1.0
local AUTOFLAG_SMOOTHNESS: number = 0.75
local AUTOFLAG_CLICK_TOLERANCE: number = 4
local AUTOFLAG_BATCH_SIZE: number = 3

local LastTargetScreenPos: vector? = nil
local MouseStableFrames: number = 0
local IsUnflagging: boolean = false
local NextTargetQueued: CandidateData? = nil

local CachedMineCandidates: {CandidateData} = TableCreate(AUTOFLAG_MAX_CANDIDATES)
local CachedWrongFlagCandidates: {CandidateData} = TableCreate(AUTOFLAG_MAX_CANDIDATES)
local CachedMineCandidateCount: number = 0
local CachedWrongFlagCandidateCount: number = 0
local LastAutoFlagScanTime: number = 0

local WALK_ARRIVAL_DIST: number = 1.6
local WALK_HUMANIZE_VARIANCE: number = 0.08
local WALK_JUMP_BASE_CHANCE: number = 0.15
local WALK_JUMP_MIN_DISTANCE: number = 4
local WALK_JUMP_MIN_NODES: number = 4
local WALK_DIRECTION_SMOOTHING: number = 0.82
local WALK_PATH_UPDATE_INTERVAL: number = 0.18
local WALK_JUMP_COOLDOWN_MIN: number = 0.4
local WALK_JUMP_COOLDOWN_MAX: number = 0.7
local WALK_DIRECTION_CHANGE_THRESHOLD: number = 0.3
local WALK_STUCK_CHECK_INTERVAL: number = 0.5
local WALK_STUCK_DISTANCE_THRESHOLD: number = 0.3
local WALK_MAX_STUCK_TIME: number = 2.0
local WALK_REPATH_COOLDOWN: number = 0.5
local WALK_TARGET_REACHED_DIST: number = 3.0
local WALK_MAX_RISKY_PROBABILITY: number = 0.20  
local WALK_RISKY_TILE_COST: number = 50
local WALK_IDLE_RETRY_INTERVAL: number = 0.5
local LastWalkRetryTime: number = 0

local NEIGHBOR_OFFSETS: {{number}} = {
    {-1, -1}, {-1, 0}, {-1, 1},
    {0, -1},           {0, 1},
    {1, -1},  {1, 0},  {1, 1}
}

local CARDINAL_OFFSETS: {{number}} = {
    {1, 0}, {-1, 0}, {0, 1}, {0, -1}
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
local COLOR_WALK_ON: Color3 = Color3.fromRGB(255, 200, 60)

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
    storedPos: Vector3?,
    lastValidated: number?
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

export type PathNode = {
    gx: number,
    gz: number,
    f: number,
    g: number
}

export type WalkState = {
    active: boolean,
    path: {{gx: number, gz: number}}?,
    pathIndex: number,
    targetTile: TileData?,
    lastRepath: number,
    lastPathUpdate: number,
    lastJump: number,
    nextJumpCooldown: number,
    currentDirection: vector,
    lastDirection: vector,
    abortToken: number
}

---- variables ----
_G.MS_RUN = true
_G.MS_AUTOFLAG = false
_G.MS_AUTOWALK = false

local Camera: Camera? = nil
local LocalPlayer: Player? = nil
local HumanoidRootPart: BasePart? = nil
local Humanoid: Humanoid? = nil

local Tiles: {TileData} = TableCreate(625)
local Grid: {[string]: TileData} = {}
local TileCount: number = 0

local TablePool: {{any}} = TableCreate(64)
local QueuePool: {{any}} = TableCreate(32)
local InQueuePool: {{[number]: boolean}} = TableCreate(32)
local PathNodePool: {PathNode} = TableCreate(100)

local NeighborCache: {TileData} = TableCreate(8)

local PendingVerifications: {AutoFlagEntry} = TableCreate(20)
local LastClickTime: number = 0
local LockedTarget: CandidateData? = nil

local TickCount: number = 0
local LastChildCount: number = 0
local SolverChanged: boolean = false
local WasAutoFlagKeyPressed: boolean = false
local WasAutoWalkKeyPressed: boolean = false

local LastCleanupTime: number = 0
local LastStaleCheckTime: number = 0
local LastDeepCleanupTime: number = 0

local MS: Instance? = nil
local FLAG: Instance? = nil

local RenderData: {TileData} = TableCreate(200)
local RenderCount: number = 0
local RenderFrameSkip: number = 0

local CachedScreenPositions: {[TileData]: vector} = {}
local LastScreenCacheTime: number = 0
local SCREEN_CACHE_INTERVAL: number = 0.016

local FrontierTiles: {TileData} = TableCreate(200)
local FrontierCount: number = 0

local BestMove: TileData? = nil
local BestMoveRisk: number = 1
local LastTankSystem: TankSystem? = nil

local WalkData: WalkState = {
    active = false,
    path = nil,
    pathIndex = 1,
    targetTile = nil,
    lastRepath = 0,
    lastPathUpdate = 0,
    lastJump = 0,
    nextJumpCooldown = 0.3,
    currentDirection = VectorCreate(0, 0, 0),
    lastDirection = VectorCreate(0, 0, 0),
    abortToken = 0,
    lastPosition = nil,
    lastPositionTime = 0,
    stuckTime = 0,
    lastSuccessfulMove = 0
}

---- memory management functions ----

local function GrabPooledTable(): {any}
    local poolSize: number = #TablePool
    if poolSize > 0 then
        local t: {any} = TablePool[poolSize]
        TablePool[poolSize] = nil
        return t
    end
    return {}
end

local function ReturnPooledTable(t: {any}): ()
    TableClear(t)
    if #TablePool < CLEANUP_POOL_MAX then
        TablePool[#TablePool + 1] = t
    end
end

local function GrabQueuePair(): ({any}, {[number]: boolean})
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

local function ReturnQueuePair(q: {any}, inq: {[number]: boolean}): ()
    TableClear(q)
    TableClear(inq)
    if #QueuePool < CLEANUP_POOL_MAX then
        QueuePool[#QueuePool + 1] = q
    end
    if #InQueuePool < CLEANUP_POOL_MAX then
        InQueuePool[#InQueuePool + 1] = inq
    end
end

local function GrabPathNode(): PathNode
    local poolSize: number = #PathNodePool
    if poolSize > 0 then
        local node: PathNode = PathNodePool[poolSize]
        PathNodePool[poolSize] = nil
        return node
    end
    return { gx = 0, gz = 0, f = 0, g = 0 }
end

local function ReturnPathNode(node: PathNode): ()
    if #PathNodePool < CLEANUP_POOL_MAX * 2 then
        PathNodePool[#PathNodePool + 1] = node
    end
end

local function TrimPool(pool: {any}, maxSize: number): ()
    local count: number = #pool
    while count > maxSize do
        pool[count] = nil
        count = count - 1
    end
end

local function UnregisterTile(index: number): ()
    local t: TileData = Tiles[index]
    if t and t.gx and t.gz then
        Grid[t.gx .. "|" .. t.gz] = nil
    end
    
    Tiles[index] = Tiles[TileCount]
    Tiles[TileCount] = nil
    TileCount = TileCount - 1
end

local function HaltMovement(): ()
    if not Humanoid then return end
    
    Pcall(function()
        Humanoid.MoveDirection = Vector3.new(0, 0, 0)
    end)
    
    WalkData.currentDirection = VectorCreate(0, 0, 0)
end

local function AbortCurrentWalk(): ()
    WalkData.active = false
    if WalkData.path then
        for i = #WalkData.path, 1, -1 do
            WalkData.path[i] = nil
        end
    end
    WalkData.path = nil
    WalkData.pathIndex = 1
    WalkData.targetTile = nil
    WalkData.abortToken = WalkData.abortToken + 1
    WalkData.lastDirection = VectorCreate(0, 0, 0)
    WalkData.currentDirection = VectorCreate(0, 0, 0)
    WalkData.lastRepath = 0
    WalkData.lastPathUpdate = 0
    WalkData.lastPosition = nil
    WalkData.stuckTime = 0
    HaltMovement()
end


local function PerformMemoryCleanup(): ()
    local currentTime: number = OsClock()
    
    if currentTime - LastCleanupTime < CLEANUP_INTERVAL then
        return
    end
    
    LastCleanupTime = currentTime
    
    TrimPool(TablePool, CLEANUP_POOL_MAX)
    TrimPool(QueuePool, CLEANUP_POOL_MAX)
    TrimPool(InQueuePool, CLEANUP_POOL_MAX)
    TrimPool(PathNodePool, CLEANUP_POOL_MAX * 2)
    
    local pendingCount: number = #PendingVerifications
    if pendingCount > MAX_PENDING_VERIFICATIONS then
        for i = pendingCount, MAX_PENDING_VERIFICATIONS + 1, -1 do
            PendingVerifications[i] = nil
        end
        pendingCount = MAX_PENDING_VERIFICATIONS
    end
    
    for i = pendingCount, 1, -1 do
        local entry: AutoFlagEntry? = PendingVerifications[i]
        if entry and currentTime - entry.time > 3 then
            PendingVerifications[i] = PendingVerifications[pendingCount]
            PendingVerifications[pendingCount] = nil
            pendingCount = pendingCount - 1
        end
    end
    
    if TileCount > 0 then
        local maxCheck: number = MathMin(TileCount, 15)
        for _ = 1, maxCheck do
            if TileCount <= 0 then break end
            local idx: number = MathRandom(1, TileCount)
            local t: TileData? = Tiles[idx]
            if t and t.part and not CheckParentValid(t.part) then
                UnregisterTile(idx)
                SolverChanged = true
            end
        end
    end
    
    if TileCount > MAX_TILES then
        for i = TileCount, MAX_TILES + 1, -1 do
            UnregisterTile(i)
        end
        SolverChanged = true
    end
end

local function PerformDeepCleanup(): ()
    local currentTime: number = OsClock()
    
    if currentTime - LastDeepCleanupTime < DEEP_CLEANUP_INTERVAL then
        return
    end
    
    LastDeepCleanupTime = currentTime
    
    TrimPool(TablePool, CLEANUP_POOL_MAX / 2)
    TrimPool(QueuePool, CLEANUP_POOL_MAX / 2)
    TrimPool(InQueuePool, CLEANUP_POOL_MAX / 2)
    TrimPool(PathNodePool, CLEANUP_POOL_MAX)
    
    if not _G.MS_AUTOWALK and not WalkData.active then
        for i = #PathNodePool, 1, -1 do
            PathNodePool[i] = nil
        end
        TableClear(PathCameFrom)
        TableClear(PathGScore)
        TableClear(PathFScore)
        TableClear(PathClosedSet)
        for i = #PathOpenSet, 1, -1 do
            PathOpenSet[i] = nil
        end
    end
    
    if not _G.MS_AUTOFLAG then
        for i = #PendingVerifications, 1, -1 do
            PendingVerifications[i] = nil
        end
        LockedTarget = nil
        NextTargetQueued = nil
        LastTargetScreenPos = nil
        MouseStableFrames = 0
        IsUnflagging = false
    end
    
    LastTankSystem = nil
    
    for i = RenderCount + 1, #RenderData do
        RenderData[i] = nil
    end
    
    for i = FrontierCount + 1, #FrontierTiles do
        FrontierTiles[i] = nil
    end
    
    collectgarbage("step", 100)
end

local function ResetAllState(): ()
    for i = TileCount, 1, -1 do
        Tiles[i] = nil
    end
    TileCount = 0
    TableClear(Grid)
    
    RenderCount = 0
    for i = 1, #RenderData do
        RenderData[i] = nil
    end
    
    FrontierCount = 0
    for i = 1, #FrontierTiles do
        FrontierTiles[i] = nil
    end
    
    for i = 1, #PendingVerifications do
        PendingVerifications[i] = nil
    end
    
    LockedTarget = nil
    NextTargetQueued = nil
    LastTargetScreenPos = nil
    MouseStableFrames = 0
    IsUnflagging = false
    
    AbortCurrentWalk()
    
    for i = #TablePool, 1, -1 do
        TablePool[i] = nil
    end
    for i = #QueuePool, 1, -1 do
        QueuePool[i] = nil
    end
    for i = #InQueuePool, 1, -1 do
        InQueuePool[i] = nil
    end
    for i = #PathNodePool, 1, -1 do
        PathNodePool[i] = nil
    end
    
    TableClear(PathCameFrom)
    TableClear(PathGScore)
    TableClear(PathFScore)
    TableClear(PathClosedSet)
    for i = #PathOpenSet, 1, -1 do
        PathOpenSet[i] = nil
    end
    
    BestMove = nil
    BestMoveRisk = 1
    LastTankSystem = nil
    SolverChanged = true
    LastChildCount = 0
    TickCount = 0
    
    collectgarbage("collect")
end

local function ValidateStaleTiles(): ()
    local currentTime: number = OsClock()
    
    if currentTime - LastStaleCheckTime < STALE_TILE_CHECK_INTERVAL then
        return
    end
    
    LastStaleCheckTime = currentTime
    
    for i = TileCount, 1, -1 do
        local t: TileData = Tiles[i]
        
        if not t.part then
            Grid[t.gx .. "|" .. t.gz] = nil
            Tiles[i] = Tiles[TileCount]
            Tiles[TileCount] = nil
            TileCount = TileCount - 1
            SolverChanged = true
        else
            local success: boolean, parent: Instance? = Pcall(function()
                return t.part.Parent
            end)
            
            if not success or not parent then
                Grid[t.gx .. "|" .. t.gz] = nil
                Tiles[i] = Tiles[TileCount]
                Tiles[TileCount] = nil
                TileCount = TileCount - 1
                SolverChanged = true
            else
                t.lastValidated = currentTime
            end
        end
    end
end

---- safe accessor functions ----

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

local function CheckParentValid(instance: Instance?): boolean
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

---- math helper functions ----

local function ComputeDistance3D(pos1: vector, pos2: vector): number
    local diff: vector = pos1 - pos2
    return VectorMagnitude(diff)
end

local function ComputeDistance2D(x1: number, y1: number, x2: number, y2: number): number
    local dx: number = x1 - x2
    local dy: number = y1 - y2
    return MathSqrt(dx * dx + dy * dy)
end

local function ComputeManhattanDist(x1: number, z1: number, x2: number, z2: number): number
    return MathAbs(x1 - x2) + MathAbs(z1 - z2)
end

local function NormalizeVector2D(dx: number, dz: number): (number, number)
    local mag: number = MathSqrt(dx * dx + dz * dz)
    if mag < 0.001 then
        return 0, 0
    end
    return dx / mag, dz / mag
end

local function AddHumanVariance(value: number, variance: number): number
    local offset: number = (MathRandom() - 0.5) * 2 * variance
    return value + offset
end

local function GetRefPosition(): Vector3?
    if HumanoidRootPart and CheckParentValid(HumanoidRootPart) then
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

---- grid functions ----

local function PositionToGridKey(part: BasePart?): (string?, number?, number?)
    if not CheckParentValid(part) then return nil, nil, nil end
    
    local success: boolean, pos: Vector3? = SafeGetProperty(part, "Position")
    if not success or not pos then return nil, nil, nil end
    
    local gx: number = MathFloor((pos.X - ORIGIN_X) / SPACING + 0.5)
    local gz: number = MathFloor((pos.Z - ORIGIN_Z) / SPACING + 0.5)
    
    return gx .. "|" .. gz, gx, gz
end

local function GridToWorldPosition(gx: number, gz: number): Vector3
    return Vector3.new(
        ORIGIN_X + gx * SPACING,
        ORIGIN_Y,
        ORIGIN_Z + gz * SPACING
    )
end

local function WorldToGridCoords(pos: Vector3): (number, number)
    local gx: number = MathFloor((pos.X - ORIGIN_X) / SPACING + 0.5)
    local gz: number = MathFloor((pos.Z - ORIGIN_Z) / SPACING + 0.5)
    return gx, gz
end

local function DetermineTileType(part: BasePart?): (string, number?)
    if not CheckParentValid(part) then
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

local function FetchNeighbors(t: TileData): {TileData}
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

local function FetchNeighborsCopy(t: TileData): {TileData}
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

local function CheckIfFlagged(part: BasePart?): boolean
    if not CheckParentValid(part) then return false end
    
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

local function RegisterTile(part: BasePart): ()
    if not CheckParentValid(part) then return end
    
    if TileCount >= MAX_TILES then return end
    
    local key: string?, gx: number?, gz: number? = PositionToGridKey(part)
    if not key or not gx or not gz then return end
    
    if Grid[key] then
        if Grid[key].part == part then return end
    end
    
    local tileType: string, val: number? = DetermineTileType(part)
    
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
        storedPos = posSuccess and pos or nil,
        lastValidated = OsClock()
    }
    
    TileCount = TileCount + 1
    Tiles[TileCount] = t
    Grid[key] = t
end

---- pathfinding functions ----

local function IsTileSafeToWalk(tile: TileData?): boolean
    -- Returns true only for completely safe tiles
    if not tile then return false end
    
    -- Never walk on confirmed/revealed mines
    if tile.tileType == "mine" then return false end
    
    -- Safe to walk on revealed tiles
    if tile.tileType == "number" or tile.tileType == "empty" then
        return true
    end
    
    -- For unknown tiles
    if tile.tileType == "unknown" then
        -- Flagged mines are safe to walk over (we marked them, can't click them)
        if tile.flagged then
            return true
        end
        
        -- Predicted mines - never walk on them
        if tile.predicted == "mine" then
            return false
        end
        
        -- Predicted safe - safe to walk
        if tile.predicted == "safe" then
            return true
        end
        
        -- Has probability - NOT safe (we want to avoid these in primary path)
        if tile.probability ~= nil then
            return false  -- Any percentage tile is not "safe"
        end
        
        -- Unknown with no data on frontier - not safe
        if tile.hasRevealedNeighbor then
            return false
        end
        
        -- Far from frontier with low density - marginally safe
        return DENSITY <= 0.15
    end
    
    return false
end

local function IsTileRiskyButAllowed(tile: TileData?): boolean
    -- Returns true for tiles that are risky but acceptable as last resort (≤20%)
    if not tile then return false end
    
    -- First check if it's already safe
    if IsTileSafeToWalk(tile) then return true end
    
    -- Never walk on mines
    if tile.tileType == "mine" then return false end
    if tile.predicted == "mine" then return false end
    
    -- For unknown tiles with probability
    if tile.tileType == "unknown" then
        if tile.probability ~= nil then
            return tile.probability <= WALK_MAX_RISKY_PROBABILITY
        end
        
        -- Unknown frontier tile with no probability - use density
        if tile.hasRevealedNeighbor then
            return DENSITY <= WALK_MAX_RISKY_PROBABILITY
        end
        
        return DENSITY <= WALK_MAX_RISKY_PROBABILITY
    end
    
    return false
end

local function GetTileTraversalCost(tile: TileData?, allowRisky: boolean): number?
    -- Returns nil if not traversable, or a cost value
    -- Lower cost = preferred path
    if not tile then return nil end
    
    -- Check if safe first
    if IsTileSafeToWalk(tile) then
        return 1  -- Base cost for safe tiles
    end
    
    -- If we're allowing risky tiles and this one qualifies
    if allowRisky and IsTileRiskyButAllowed(tile) then
        -- Add heavy penalty based on probability
        local prob: number = tile.probability or DENSITY
        -- Cost scales with risk: 20% = cost of 50, 10% = cost of 25, etc.
        return 1 + WALK_RISKY_TILE_COST * (prob / WALK_MAX_RISKY_PROBABILITY)
    end
    
    return nil  -- Not traversable
end


local function IsTileClickable(tile: TileData?): boolean
    if not tile then return false end
    
    if tile.tileType ~= "unknown" then return false end
    if tile.predicted == "mine" then return false end
    
    return true
end

local function ComputeGridPath(startGx: number, startGz: number, goalGx: number, goalGz: number, allowRisky: boolean): {{gx: number, gz: number}}?
    local startKey: string = startGx .. "|" .. startGz
    local goalKey: string = goalGx .. "|" .. goalGz
    
    if startKey == goalKey then
        return {{ gx = startGx, gz = startGz }}
    end
    
    TableClear(PathCameFrom)
    TableClear(PathGScore)
    TableClear(PathFScore)
    TableClear(PathClosedSet)
    
    for i = 1, #PathOpenSet do
        ReturnPathNode(PathOpenSet[i])
    end
    TableClear(PathOpenSet)
    
    local openSet: {PathNode} = PathOpenSet
    local cameFrom: {[string]: string} = PathCameFrom
    local gScore: {[string]: number} = PathGScore
    local fScore: {[string]: number} = PathFScore
    local closedSet: {[string]: boolean} = PathClosedSet
    
    gScore[startKey] = 0
    fScore[startKey] = ComputeManhattanDist(startGx, startGz, goalGx, goalGz)
    
    local startNode: PathNode = GrabPathNode()
    startNode.gx = startGx
    startNode.gz = startGz
    startNode.f = fScore[startKey]
    startNode.g = 0
    openSet[1] = startNode
    
    local iterations: number = 0
    
    while #openSet > 0 and iterations < MAX_PATH_ITERATIONS do
        iterations = iterations + 1
        
        TableSort(openSet, function(a: PathNode, b: PathNode): boolean
            return a.f < b.f
        end)
        
        local current: PathNode = TableRemove(openSet, 1)
        local currentKey: string = current.gx .. "|" .. current.gz
        
        if currentKey == goalKey then
            local path: {{gx: number, gz: number}} = TableCreate(50)
            local curr: string? = currentKey
            local pathLen: number = 0
            
            while curr and pathLen < MAX_PATH_LENGTH do
                local gxStr, gzStr = curr:match("^(%-?%d+)|(%-?%d+)$")
                if gxStr and gzStr then
                    TableInsert(path, 1, { gx = tonumber(gxStr), gz = tonumber(gzStr) })
                    pathLen = pathLen + 1
                end
                curr = cameFrom[curr]
            end
            
            ReturnPathNode(current)
            for i = 1, #openSet do
                ReturnPathNode(openSet[i])
            end
            
            return path
        end
        
        closedSet[currentKey] = true
        
        for i = 1, 4 do
            local offset: {number} = CARDINAL_OFFSETS[i]
            local nx: number = current.gx + offset[1]
            local nz: number = current.gz + offset[2]
            local nKey: string = nx .. "|" .. nz
            
            if not closedSet[nKey] then
                local neighborTile: TileData? = Grid[nKey]
                
                local moveCost: number? = nil
                
                -- Special handling for goal tile
                if nKey == goalKey then
                    if neighborTile and neighborTile.predicted ~= "mine" and neighborTile.tileType ~= "mine" then
                        moveCost = 1
                    end
                else
                    moveCost = GetTileTraversalCost(neighborTile, allowRisky)
                end
                
                if moveCost then
                    local tentativeG: number = (gScore[currentKey] or MathHuge) + moveCost
                    local currentG: number = gScore[nKey] or MathHuge
                    
                    if tentativeG < currentG then
                        cameFrom[nKey] = currentKey
                        gScore[nKey] = tentativeG
                        fScore[nKey] = tentativeG + ComputeManhattanDist(nx, nz, goalGx, goalGz)
                        
                        local inOpen: boolean = false
                        for j = 1, #openSet do
                            if openSet[j].gx == nx and openSet[j].gz == nz then
                                openSet[j].f = fScore[nKey]
                                openSet[j].g = tentativeG
                                inOpen = true
                                break
                            end
                        end
                        
                        if not inOpen then
                            local newNode: PathNode = GrabPathNode()
                            newNode.gx = nx
                            newNode.gz = nz
                            newNode.f = fScore[nKey]
                            newNode.g = tentativeG
                            openSet[#openSet + 1] = newNode
                        end
                    end
                end
            end
        end
        
        ReturnPathNode(current)
    end
    
    for i = 1, #openSet do
        ReturnPathNode(openSet[i])
    end
    
    return nil
end

local function FindApproachPath(startGx: number, startGz: number, targetTile: TileData): ({{gx: number, gz: number}}?, TileData?)
    if not targetTile then
        return nil, nil
    end
    
    local goalGx: number = targetTile.gx
    local goalGz: number = targetTile.gz
    
    -- First, try to find a completely safe path
    local safePath: {{gx: number, gz: number}}? = nil
    
    if IsTileSafeToWalk(targetTile) then
        safePath = ComputeGridPath(startGx, startGz, goalGx, goalGz, false)
        if safePath then
            return safePath, targetTile
        end
    end
    
    -- Try approaching from adjacent safe tiles
    local bestSafePath: {{gx: number, gz: number}}? = nil
    local bestSafeApproach: TileData? = nil
    local bestSafeLen: number = MathHuge
    
    for i = 1, 4 do
        local offset: {number} = CARDINAL_OFFSETS[i]
        local ax: number = goalGx + offset[1]
        local az: number = goalGz + offset[2]
        local aKey: string = ax .. "|" .. az
        local approachTile: TileData? = Grid[aKey]
        
        if approachTile and IsTileSafeToWalk(approachTile) then
            local path = ComputeGridPath(startGx, startGz, ax, az, false)
            if path and #path < bestSafeLen then
                bestSafeLen = #path
                bestSafePath = path
                bestSafeApproach = approachTile
            end
        end
    end
    
    if bestSafePath then
        return bestSafePath, bestSafeApproach
    end
    
    -- No safe path found - try with risky tiles allowed (≤20%)
    local riskyPath: {{gx: number, gz: number}}? = nil
    
    if IsTileRiskyButAllowed(targetTile) then
        riskyPath = ComputeGridPath(startGx, startGz, goalGx, goalGz, true)
        if riskyPath then
            return riskyPath, targetTile
        end
    end
    
    -- Try approaching from adjacent tiles (including risky ones)
    local bestRiskyPath: {{gx: number, gz: number}}? = nil
    local bestRiskyApproach: TileData? = nil
    local bestRiskyLen: number = MathHuge
    
    for i = 1, 4 do
        local offset: {number} = CARDINAL_OFFSETS[i]
        local ax: number = goalGx + offset[1]
        local az: number = goalGz + offset[2]
        local aKey: string = ax .. "|" .. az
        local approachTile: TileData? = Grid[aKey]
        
        if approachTile and IsTileRiskyButAllowed(approachTile) then
            local path = ComputeGridPath(startGx, startGz, ax, az, true)
            if path and #path < bestRiskyLen then
                bestRiskyLen = #path
                bestRiskyPath = path
                bestRiskyApproach = approachTile
            end
        end
    end
    
    return bestRiskyPath, bestRiskyApproach
end


---- movement functions ----

local function IsNearTarget(charPos: Vector3, targetTile: TileData): boolean
    if not targetTile or not targetTile.storedPos then return false end
    local targetPos: Vector3 = targetTile.storedPos
    local dx: number = targetPos.X - charPos.X
    local dz: number = targetPos.Z - charPos.Z
    local dist: number = MathSqrt(dx * dx + dz * dz)
    return dist < WALK_TARGET_REACHED_DIST
end

local function CheckIfStuck(charPos: Vector3): boolean
    local currentTime: number = OsClock()
    
    if not WalkData.lastPosition then
        WalkData.lastPosition = charPos
        WalkData.lastPositionTime = currentTime
        WalkData.stuckTime = 0
        return false
    end
    
    if currentTime - WalkData.lastPositionTime >= WALK_STUCK_CHECK_INTERVAL then
        local dx: number = charPos.X - WalkData.lastPosition.X
        local dz: number = charPos.Z - WalkData.lastPosition.Z
        local movedDist: number = MathSqrt(dx * dx + dz * dz)
        
        if movedDist < WALK_STUCK_DISTANCE_THRESHOLD then
            WalkData.stuckTime = WalkData.stuckTime + (currentTime - WalkData.lastPositionTime)
        else
            WalkData.stuckTime = 0
            WalkData.lastSuccessfulMove = currentTime
        end
        
        WalkData.lastPosition = charPos
        WalkData.lastPositionTime = currentTime
    end
    
    return WalkData.stuckTime >= WALK_MAX_STUCK_TIME
end

local function ApplyMoveDirection(dirX: number, dirZ: number): boolean
    if not Humanoid then return false end
    
    local directionChange: number = MathAbs(dirX - WalkData.lastDirection.X) + MathAbs(dirZ - WalkData.lastDirection.Z)
    
    local smoothingFactor: number = WALK_DIRECTION_SMOOTHING
    if directionChange > WALK_DIRECTION_CHANGE_THRESHOLD then
        smoothingFactor = smoothingFactor * 0.7
    end
    
    local smoothedX: number = WalkData.currentDirection.X + (dirX - WalkData.currentDirection.X) * smoothingFactor
    local smoothedZ: number = WalkData.currentDirection.Z + (dirZ - WalkData.currentDirection.Z) * smoothingFactor
    
    local varianceAmount: number = WALK_HUMANIZE_VARIANCE * (1 + MathRandom() * 0.3)
    smoothedX = AddHumanVariance(smoothedX, varianceAmount)
    smoothedZ = AddHumanVariance(smoothedZ, varianceAmount)
    
    local mag: number = MathSqrt(smoothedX * smoothedX + smoothedZ * smoothedZ)
    if mag > 1.1 then
        smoothedX = smoothedX / mag
        smoothedZ = smoothedZ / mag
    end
    
    local success: boolean = Pcall(function()
        Humanoid.MoveDirection = Vector3.new(smoothedX, 0, smoothedZ)
    end)
    
    if success then
        WalkData.currentDirection = VectorCreate(smoothedX, 0, smoothedZ)
        WalkData.lastDirection = VectorCreate(dirX, 0, dirZ)
    end
    
    return success
end

local function TriggerJump(): boolean
    if not Humanoid then return false end
    
    local currentTime: number = OsClock()
    if currentTime - WalkData.lastJump < WalkData.nextJumpCooldown then
        return false
    end
    
    local success: boolean = Pcall(function()
        Humanoid.Jump = true
    end)
    
    if success then
        WalkData.lastJump = currentTime
        WalkData.nextJumpCooldown = WALK_JUMP_COOLDOWN_MIN + MathRandom() * (WALK_JUMP_COOLDOWN_MAX - WALK_JUMP_COOLDOWN_MIN)
    end
    
    return success
end

local function UpdateWalkPath(): ()
    if not _G.MS_AUTOWALK then
        if WalkData.active then
            AbortCurrentWalk()
        end
        return
    end
    
    if not HumanoidRootPart or not CheckParentValid(HumanoidRootPart) then
        return
    end
    
    local currentTime: number = OsClock()
    local posSuccess: boolean, charPos: Vector3? = SafeGetProperty(HumanoidRootPart, "Position")
    if not posSuccess or not charPos then return end
    
    -- Check if we need to wait for nearby mines to be flagged
    if _G.MS_AUTOFLAG and CachedMineCandidateCount > 0 then
        for i = 1, MathMin(CachedMineCandidateCount, 5) do
            local candidate: CandidateData = CachedMineCandidates[i]
            if candidate.distance < 6 then  -- Reduced from 8 to 6
                -- Pause movement but keep path
                if WalkData.active then
                    HaltMovement()
                end
                -- Don't return - still check if we need to repath
                -- but don't move until mine is flagged
                return
            end
        end
    end
    
    -- Validate BestMove exists and is valid
    if not BestMove or not BestMove.part or not CheckParentValid(BestMove.part) then
        if WalkData.active then
            AbortCurrentWalk()
        end
        -- Keep trying to find a path periodically
        return
    end
    
    -- Check if BestMove is still a valid target
    if BestMove.tileType ~= "unknown" or BestMove.predicted == "mine" then
        if WalkData.active then
            AbortCurrentWalk()
        end
        return
    end
    
    -- Check if already near target
    if IsNearTarget(charPos, BestMove) then
        if WalkData.active then
            AbortCurrentWalk()
        end
        return
    end
    
    -- Determine if we need to find/update path
    local needsRepath: boolean = false
    
    if not WalkData.active then
        -- Not walking - try to start if enough time passed
        if currentTime - LastWalkRetryTime >= WALK_IDLE_RETRY_INTERVAL then
            needsRepath = true
            LastWalkRetryTime = currentTime
        end
    elseif WalkData.targetTile ~= BestMove then
        -- Target changed
        needsRepath = true
    elseif not WalkData.path or #WalkData.path == 0 then
        -- No path
        needsRepath = true
    elseif currentTime - WalkData.lastPathUpdate >= WALK_PATH_UPDATE_INTERVAL then
        -- Time for periodic check
        WalkData.lastPathUpdate = currentTime
        
        -- Check if stuck
        local isStuck: boolean = CheckIfStuck(charPos)
        
        if isStuck then
            if currentTime - WalkData.lastRepath > WALK_REPATH_COOLDOWN then
                needsRepath = true
                WalkData.stuckTime = 0
            end
        elseif currentTime - WalkData.lastRepath > 3 then
            -- Periodic repath every 3 seconds for long walks
            needsRepath = true
        end
    end
    
    if needsRepath then
        local startGx: number, startGz: number = WorldToGridCoords(charPos)
        
        local path, approach = FindApproachPath(startGx, startGz, BestMove)
        
        if path and #path > 0 then
            WalkData.active = true
            WalkData.path = path
            WalkData.pathIndex = (#path > 1) and 2 or 1
            WalkData.targetTile = BestMove
            WalkData.lastRepath = currentTime
            WalkData.lastPathUpdate = currentTime
            WalkData.lastPosition = charPos
            WalkData.lastPositionTime = currentTime
            WalkData.stuckTime = 0
            LastWalkRetryTime = currentTime
        else
            -- No path found - abort current walk but will retry
            if WalkData.active then
                AbortCurrentWalk()
            end
            LastWalkRetryTime = currentTime
        end
    end
end

local function ExecuteWalkMovement(): ()
    if not _G.MS_AUTOWALK then
        return
    end
    
    if not WalkData.active or not WalkData.path then
        return
    end
    
    if not HumanoidRootPart or not CheckParentValid(HumanoidRootPart) then
        return
    end
    
    if not Humanoid or not CheckParentValid(Humanoid) then
        return
    end
    
    local posSuccess: boolean, charPos: Vector3? = SafeGetProperty(HumanoidRootPart, "Position")
    if not posSuccess or not charPos then return end
    
    -- Check if we've reached the target tile area
    if WalkData.targetTile and IsNearTarget(charPos, WalkData.targetTile) then
        AbortCurrentWalk()
        return
    end
    
    -- Check path validity
    if #WalkData.path == 0 then
        WalkData.path = nil
        WalkData.lastRepath = 0
        return
    end
    
    -- Advance through waypoints we've passed
    local advanced: number = 0
    while WalkData.pathIndex <= #WalkData.path and advanced < 5 do
        local node = WalkData.path[WalkData.pathIndex]
        if not node then break end
        
        local nodeWorld: Vector3 = GridToWorldPosition(node.gx, node.gz)
        local dx: number = nodeWorld.X - charPos.X
        local dz: number = nodeWorld.Z - charPos.Z
        local dist2D: number = MathSqrt(dx * dx + dz * dz)
        
        if dist2D < WALK_ARRIVAL_DIST then
            WalkData.pathIndex = WalkData.pathIndex + 1
            advanced = advanced + 1
        else
            break
        end
    end
    
    -- Check if path completed
    if WalkData.pathIndex > #WalkData.path then
        WalkData.path = nil
        WalkData.lastRepath = 0
        return
    end
    
    local targetNode = WalkData.path[WalkData.pathIndex]
    if not targetNode then
        WalkData.path = nil
        WalkData.lastRepath = 0
        return
    end
    
    local targetWorld: Vector3 = GridToWorldPosition(targetNode.gx, targetNode.gz)
    local dx: number = targetWorld.X - charPos.X
    local dz: number = targetWorld.Z - charPos.Z
    local distToTarget: number = MathSqrt(dx * dx + dz * dz)
    
    if distToTarget < 0.1 then
        return
    end
    
    local dirX: number, dirZ: number = NormalizeVector2D(dx, dz)
    ApplyMoveDirection(dirX, dirZ)
    
    -- Jump logic
    local nodesRemaining: number = #WalkData.path - WalkData.pathIndex
    
    local shouldTryJump: boolean = false
    if nodesRemaining >= WALK_JUMP_MIN_NODES then
        shouldTryJump = true
    elseif distToTarget >= WALK_JUMP_MIN_DISTANCE then
        shouldTryJump = true
    elseif WalkData.stuckTime == 0 and MathRandom() < 0.01 then
        shouldTryJump = true
    end
    
    if shouldTryJump then
        local jumpChance: number = WALK_JUMP_BASE_CHANCE
        if distToTarget > 8 then
            jumpChance = jumpChance * 1.5
        end
        if nodesRemaining > 5 then
            jumpChance = jumpChance * 1.3
        end
        if MathRandom() < jumpChance then
            TriggerJump()
        end
    end
end

---- solver helper functions ----

local function SortAndUniq(vars: {number}): {number}
    TableSort(vars)
    local out: {number} = GrabPooledTable()
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
    local out: {string} = GrabPooledTable()
    for i = 1, #arr do
        out[i] = tostring(arr[i])
    end
    local result: string = TableConcat(out, ",")
    ReturnPooledTable(out)
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
    local out: {number} = GrabPooledTable()
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
            ReturnPooledTable(vars)
            return nil, "contradiction"
        end
        
        local varSetKey: string = JoinNums(vars)
        local existing: number? = byVarSet[varSetKey]
        
        if existing == nil then
            byVarSet[varSetKey] = needed
            normalized[#normalized + 1] = { needed = needed, vars = vars }
        else
            if existing ~= needed then
                ReturnPooledTable(vars)
                return nil, "contradiction"
            end
            ReturnPooledTable(vars)
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
                                ReturnPooledTable(diffVars)
                                return nil, "contradiction"
                            end
                            
                            if #diffVars == 0 then
                                if diffNeeded ~= 0 then
                                    ReturnPooledTable(diffVars)
                                    return nil, "contradiction"
                                end
                                ReturnPooledTable(diffVars)
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
                                    ReturnPooledTable(diffVars)
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
    local adj: {TileData} = FetchNeighbors(t)
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
                local neighborsOfA: {TileData} = FetchNeighborsCopy(tileA)
                
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
        if FrontierCount >= MAX_FRONTIER_TILES then break end
        
        local t: TileData? = Tiles[i]
        if not t then continue end
        
        t.hasRevealedNeighbor = nil
        t.constraintCount = 0
        
        if t.tileType == "unknown" and t.predicted == false then
            local neighbors: {TileData} = FetchNeighbors(t)
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
    local neighbors: {TileData} = FetchNeighborsCopy(tile)
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

local function CountUnknownNeighbors(tile: TileData): number
    local count: number = 0
    local neighbors: {TileData} = FetchNeighbors(tile)
    for i = 1, #neighbors do
        local n: TileData = neighbors[i]
        if n.tileType == "unknown" and n.predicted ~= "mine" and n.predicted ~= "safe" then
            count = count + 1
        end
    end
    return count
end

local function CountRevealedNeighbors(tile: TileData): number
    local count: number = 0
    local neighbors: {TileData} = FetchNeighbors(tile)
    for i = 1, #neighbors do
        local n: TileData = neighbors[i]
        if n.tileType == "number" or n.tileType == "empty" then
            count = count + 1
        end
    end
    return count
end

local function IsCornerTile(tile: TileData): boolean
    local revealed: number = CountRevealedNeighbors(tile)
    local unknown: number = CountUnknownNeighbors(tile)
    return revealed <= 2 and unknown >= 3
end

local function IsEdgeTile(tile: TileData): boolean
    local revealed: number = CountRevealedNeighbors(tile)
    return revealed >= 1 and revealed <= 3
end

local function ComputeTileScore(tile: TileData, risk: number): number
    local score: number = 0
    
    local safeProb: number = 1 - risk
    score = score + safeProb * 100
    
    local neighbors: {TileData} = FetchNeighborsCopy(tile)
    local unknownNeighbors: number = 0
    local revealedNeighbors: number = 0
    local constraintSum: number = 0
    
    for i = 1, #neighbors do
        local n: TileData = neighbors[i]
        if n.tileType == "unknown" and n.predicted ~= "mine" then
            unknownNeighbors = unknownNeighbors + 1
        elseif n.tileType == "number" then
            revealedNeighbors = revealedNeighbors + 1
            constraintSum = constraintSum + (n.constraintCount or 0)
        elseif n.tileType == "empty" then
            revealedNeighbors = revealedNeighbors + 1
        end
    end
    
    score = score + unknownNeighbors * 5
    
    score = score + revealedNeighbors * 3
    
    if tile.constraintCount and tile.constraintCount > 0 then
        score = score + tile.constraintCount * 8
    end
    
    if IsCornerTile(tile) then
        score = score - 15
    end
    
    if USE_ENTROPY_TIEBREAK then
        local dist: {number} = EstimateNeighborMineCountDist(tile)
        local entropy: number = Entropy(dist)
        score = score + entropy * 10
    end
    
    return score
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
    
    if bestRisk == 0 then
        local refPos: Vector3? = GetRefPosition()
        if candidateCount > 1 and refPos then
            TableSort(candidates, function(a: TileData, b: TileData): boolean
                local posA: Vector3? = a.storedPos
                local posB: Vector3? = b.storedPos
                if not posA then return false end
                if not posB then return true end
                local diffA: Vector3 = posA - refPos
                local diffB: Vector3 = posB - refPos
                local distA: number = VectorMagnitude(VectorCreate(diffA.X, diffA.Y, diffA.Z))
                local distB: number = VectorMagnitude(VectorCreate(diffB.X, diffB.Y, diffB.Z))
                return distA < distB
            end)
        end
        return candidates[1], 0
    end
    
    local bestTile: TileData = candidates[1]
    local bestScore: number = -MathHuge
    
    local maxEval: number = MathMin(candidateCount, 20)
    
    for i = 1, maxEval do
        local t: TileData = candidates[i]
        local r: number = t.probability or FALLBACK_RISK
        local score: number = ComputeTileScore(t, r)
        
        if score > bestScore then
            bestScore = score
            bestTile = t
        end
    end
    
    local refPos: Vector3? = GetRefPosition()
    if refPos and bestTile.storedPos then
        local bestDist: number = MathHuge
        local bestDistTile: TileData = bestTile
        
        for i = 1, maxEval do
            local t: TileData = candidates[i]
            local r: number = t.probability or FALLBACK_RISK
            local score: number = ComputeTileScore(t, r)
            
            if MathAbs(score - bestScore) < 5 and t.storedPos then
                local diff: Vector3 = t.storedPos - refPos
                local dist: number = VectorMagnitude(VectorCreate(diff.X, diff.Y, diff.Z))
                if dist < bestDist then
                    bestDist = dist
                    bestDistTile = t
                end
            end
        end
        
        bestTile = bestDistTile
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
                        local q: {number}, inQueue: {[number]: boolean} = GrabQueuePair()
                        
                        if AssignVar(v, 0, trail, q, inQueue) and Propagate(trail, q, inQueue) then
                            Backtrack(trail)
                        end
                        
                        ReturnQueuePair(q, inQueue)
                        UndoTo(trail, saved)
                    end
                    
                    do
                        local saved: number = #trail
                        local q: {number}, inQueue: {[number]: boolean} = GrabQueuePair()
                        
                        if AssignVar(v, 1, trail, q, inQueue) and Propagate(trail, q, inQueue) then
                            Backtrack(trail)
                        end
                        
                        ReturnQueuePair(q, inQueue)
                        UndoTo(trail, saved)
                    end
                end
                
                local trail: {{v: number, val: number}} = TableCreate(nVars)
                local q: {number}, inQueue: {[number]: boolean} = GrabQueuePair()
                
                for eqIdx = 1, #reducedEqs do
                    EnqueueEq(q, inQueue, eqIdx)
                end
                
                if Propagate(trail, q, inQueue) then
                    Backtrack(trail)
                end
                
                ReturnQueuePair(q, inQueue)
                
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

---- autoflag functions ----

local function VerifyPendingFlags(): ()
    local currentTime: number = OsClock()
    
    for i = #PendingVerifications, 1, -1 do
        local entry: AutoFlagEntry = PendingVerifications[i]
        
        if currentTime - entry.time >= AUTOFLAG_VERIFY_DELAY then
            local tile: TileData = entry.tile
            
            if tile.part and CheckParentValid(tile.part) then
                if CheckIfFlagged(tile.part) or tile.tileType == "mine" then
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

local function RefreshAutoFlagCandidates(): ()
    local currentTime: number = OsClock()
    
    if currentTime - LastAutoFlagScanTime < AUTOFLAG_SCAN_INTERVAL then
        return
    end
    
    LastAutoFlagScanTime = currentTime
    
    CachedMineCandidateCount = 0
    CachedWrongFlagCandidateCount = 0
    
    if not HumanoidRootPart or not CheckParentValid(HumanoidRootPart) then
        return
    end
    
    local success: boolean, charPos: Vector3? = SafeGetProperty(HumanoidRootPart, "Position")
    if not success or not charPos then return end
    
    local charX: number = charPos.X
    local charY: number = charPos.Y
    local charZ: number = charPos.Z
    local rangeSq: number = AUTOFLAG_MAX_RANGE * AUTOFLAG_MAX_RANGE
    
    for i = 1, TileCount do
        if CachedMineCandidateCount >= AUTOFLAG_MAX_CANDIDATES and CachedWrongFlagCandidateCount >= AUTOFLAG_MAX_CANDIDATES then
            break
        end
        
        local tile: TileData? = Tiles[i]
        if not tile then continue end
        if not tile.storedPos then continue end
        
        local tilePos: Vector3 = tile.storedPos
        local dx: number = tilePos.X - charX
        local dy: number = tilePos.Y - charY
        local dz: number = tilePos.Z - charZ
        local distSq: number = dx * dx + dy * dy + dz * dz
        
        if distSq > rangeSq then continue end
        
        local dist: number = MathSqrt(distSq)
        local tileVec: vector = VectorCreate(tilePos.X, tilePos.Y, tilePos.Z)
        
        if tile.predicted == "mine" and not tile.flagged and tile.tileType ~= "mine" then
            if tile.part and CheckParentValid(tile.part) then
                if not CheckIfFlagged(tile.part) then
                    if CachedMineCandidateCount < AUTOFLAG_MAX_CANDIDATES then
                        CachedMineCandidateCount = CachedMineCandidateCount + 1
                        local candidate: CandidateData? = CachedMineCandidates[CachedMineCandidateCount]
                        if candidate then
                            candidate.tile = tile
                            candidate.distance = dist
                            candidate.position = tileVec
                        else
                            CachedMineCandidates[CachedMineCandidateCount] = {
                                tile = tile,
                                distance = dist,
                                position = tileVec
                            }
                        end
                    end
                end
            end
        elseif tile.predicted == "safe" and tile.tileType == "unknown" then
            if tile.part and CheckParentValid(tile.part) then
                if CheckIfFlagged(tile.part) then
                    if CachedWrongFlagCandidateCount < AUTOFLAG_MAX_CANDIDATES then
                        CachedWrongFlagCandidateCount = CachedWrongFlagCandidateCount + 1
                        local candidate: CandidateData? = CachedWrongFlagCandidates[CachedWrongFlagCandidateCount]
                        if candidate then
                            candidate.tile = tile
                            candidate.distance = dist
                            candidate.position = tileVec
                        else
                            CachedWrongFlagCandidates[CachedWrongFlagCandidateCount] = {
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
    
    if CachedMineCandidateCount > 1 then
        for i = 1, CachedMineCandidateCount - 1 do
            local minIdx: number = i
            for j = i + 1, CachedMineCandidateCount do
                if CachedMineCandidates[j].distance < CachedMineCandidates[minIdx].distance then
                    minIdx = j
                end
            end
            if minIdx ~= i then
                local temp: CandidateData = CachedMineCandidates[i]
                CachedMineCandidates[i] = CachedMineCandidates[minIdx]
                CachedMineCandidates[minIdx] = temp
            end
        end
    end
    
    if CachedWrongFlagCandidateCount > 1 then
        for i = 1, CachedWrongFlagCandidateCount - 1 do
            local minIdx: number = i
            for j = i + 1, CachedWrongFlagCandidateCount do
                if CachedWrongFlagCandidates[j].distance < CachedWrongFlagCandidates[minIdx].distance then
                    minIdx = j
                end
            end
            if minIdx ~= i then
                local temp: CandidateData = CachedWrongFlagCandidates[i]
                CachedWrongFlagCandidates[i] = CachedWrongFlagCandidates[minIdx]
                CachedWrongFlagCandidates[minIdx] = temp
            end
        end
    end
end

local function GetCachedNearbyMines(): (CandidateData?, CandidateData?)
    if CachedMineCandidateCount >= 1 then
        return CachedMineCandidates[1], CachedMineCandidates[2]
    end
    return nil, nil
end

local function GetCachedNearbyWrongFlags(): (CandidateData?, CandidateData?)
    if CachedWrongFlagCandidateCount >= 1 then
        return CachedWrongFlagCandidates[1], CachedWrongFlagCandidates[2]
    end
    return nil, nil
end


local function ProcessAutoFlag(): ()
    if not _G.MS_AUTOFLAG then
        LockedTarget = nil
        NextTargetQueued = nil
        LastTargetScreenPos = nil
        MouseStableFrames = 0
        IsUnflagging = false
        return
    end
    
    local currentTime: number = OsClock()
    
    VerifyPendingFlags()
    RefreshAutoFlagCandidates()
    
    if LockedTarget then
        local tile: TileData = LockedTarget.tile
        local isInvalid: boolean = false
        
        if not tile.part then
            isInvalid = true
        elseif not CheckParentValid(tile.part) then
            isInvalid = true
        elseif IsUnflagging then
            if not CheckIfFlagged(tile.part) or tile.tileType ~= "unknown" then
                isInvalid = true
            end
        else
            if tile.flagged or CheckIfFlagged(tile.part) or tile.tileType ~= "unknown" then
                isInvalid = true
            end
        end
        
        if isInvalid then
            LockedTarget = NextTargetQueued
            NextTargetQueued = nil
            LastTargetScreenPos = nil
            MouseStableFrames = 0
            if not LockedTarget then
                IsUnflagging = false
            end
        end
    end
    
    if not LockedTarget then
        local wrongFlag1: CandidateData?, wrongFlag2: CandidateData? = GetCachedNearbyWrongFlags()
        
        if wrongFlag1 then
            LockedTarget = wrongFlag1
            NextTargetQueued = wrongFlag2
            LastTargetScreenPos = nil
            MouseStableFrames = 0
            IsUnflagging = true
        else
            local mine1: CandidateData?, mine2: CandidateData? = GetCachedNearbyMines()
            
            if mine1 then
                LockedTarget = mine1
                NextTargetQueued = mine2
                LastTargetScreenPos = nil
                MouseStableFrames = 0
                IsUnflagging = false
            end
        end
    elseif not NextTargetQueued then
        if IsUnflagging then
            local wrongFlag1: CandidateData?, wrongFlag2: CandidateData? = GetCachedNearbyWrongFlags()
            if wrongFlag2 then
                NextTargetQueued = wrongFlag2
            elseif not wrongFlag1 then
                local mine1: CandidateData?, mine2: CandidateData? = GetCachedNearbyMines()
                if mine1 then
                    NextTargetQueued = mine1
                end
            end
        else
            local mine1: CandidateData?, mine2: CandidateData? = GetCachedNearbyMines()
            if mine2 then
                NextTargetQueued = mine2
            end
        end
    end
    
    if LockedTarget and Camera then
        local worldPos: Vector3 = Vector3.new(LockedTarget.position.X, LockedTarget.position.Y, LockedTarget.position.Z)
        local screenPos: vector?, onScreen: boolean = SafeWorldToScreen(Camera, worldPos)
        
        if screenPos and onScreen then
            local currentMouse: vector? = SafeGetMousePosition()
            
            if currentMouse then
                local distToTarget: number = ComputeDistance2D(currentMouse.X, currentMouse.Y, screenPos.X, screenPos.Y)
                
                if distToTarget > AUTOFLAG_CLICK_TOLERANCE then
                    local lerpedX: number = currentMouse.X + (screenPos.X - currentMouse.X) * AUTOFLAG_SMOOTHNESS
                    local lerpedY: number = currentMouse.Y + (screenPos.Y - currentMouse.Y) * AUTOFLAG_SMOOTHNESS
                    
                    SafeMouseMoveAbs(lerpedX, lerpedY)
                    MouseStableFrames = 0
                else
                    MouseStableFrames = MouseStableFrames + 1
                    
                    if MouseStableFrames >= 2 and currentTime - LastClickTime >= AUTOFLAG_CLICK_DELAY then
                        local shouldClick: boolean = false
                        local tileType: string = DetermineTileType(LockedTarget.tile.part)
                        
                        if tileType == "unknown" then
                            if IsUnflagging then
                                shouldClick = CheckIfFlagged(LockedTarget.tile.part)
                            else
                                shouldClick = not CheckIfFlagged(LockedTarget.tile.part)
                            end
                        end
                        
                        if shouldClick then
                            local clickSuccess: boolean = SafeMouse1Click()
                            
                            if clickSuccess then
                                LastClickTime = currentTime
                                
                                if not IsUnflagging then
                                    LockedTarget.tile.flagged = true
                                end
                                
                                if #PendingVerifications < MAX_PENDING_VERIFICATIONS then
                                    PendingVerifications[#PendingVerifications + 1] = {
                                        tile = LockedTarget.tile,
                                        time = currentTime
                                    }
                                end
                                
                                LockedTarget = NextTargetQueued
                                NextTargetQueued = nil
                                LastTargetScreenPos = nil
                                MouseStableFrames = 0
                                
                                LastAutoFlagScanTime = 0
                                
                                if not LockedTarget then
                                    IsUnflagging = false
                                end
                            end
                        else
                            LockedTarget = NextTargetQueued
                            NextTargetQueued = nil
                            LastTargetScreenPos = nil
                            MouseStableFrames = 0
                            if not LockedTarget then
                                IsUnflagging = false
                            end
                        end
                    end
                end
                
                LastTargetScreenPos = screenPos
            end
        else
            LockedTarget = NextTargetQueued
            NextTargetQueued = nil
            LastTargetScreenPos = nil
            MouseStableFrames = 0
            if not LockedTarget then
                IsUnflagging = false
            end
        end
    end
end

---- input processing ----

local function ProcessInput(): ()
    local autoFlagPressed: boolean = false
    local autoWalkPressed: boolean = false
    
    local success: boolean, pressedKeys: {any}? = Pcall(function()
        return getpressedkeys()
    end)
    
    if success and pressedKeys then
        for i = 1, #pressedKeys do
            local key: any = pressedKeys[i]
            
            if type(key) == "string" then
                local keyUpper: string = StringUpper(key)
                if keyUpper == AUTOFLAG_TOGGLE_KEY then
                    autoFlagPressed = true
                elseif keyUpper == AUTOWALK_TOGGLE_KEY then
                    autoWalkPressed = true
                end
            elseif type(key) == "number" then
                if key == 0x58 or key == 88 or key == StringByte("X") then
                    autoFlagPressed = true
                elseif key == 0x43 or key == 67 or key == StringByte("C") then
                    autoWalkPressed = true
                end
            end
        end
    end
    
    if autoFlagPressed and not WasAutoFlagKeyPressed then
        _G.MS_AUTOFLAG = not _G.MS_AUTOFLAG
        print("[Minesweeper] Auto-Flag: " .. (_G.MS_AUTOFLAG and "ENABLED" or "DISABLED"))
    end
    WasAutoFlagKeyPressed = autoFlagPressed
    
    if autoWalkPressed and not WasAutoWalkKeyPressed then
        _G.MS_AUTOWALK = not _G.MS_AUTOWALK
        print("[Minesweeper] Auto-Walk: " .. (_G.MS_AUTOWALK and "ENABLED" or "DISABLED"))
        
        if not _G.MS_AUTOWALK then
            AbortCurrentWalk()
        end
    end
    WasAutoWalkKeyPressed = autoWalkPressed
end

---- system functions ----

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
            Humanoid = SafeFindFirstChild(character, "Humanoid") :: Humanoid?
        else
            HumanoidRootPart = nil
            Humanoid = nil
        end
    else
        LocalPlayer = nil
        HumanoidRootPart = nil
        Humanoid = nil
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
                    RegisterTile(part :: BasePart)
                end
            end
            
            SolverChanged = true
        else
            for i = 1, #children do
                local part: Instance = children[i]
                local key: string? = PositionToGridKey(part :: BasePart)
                
                if key and not Grid[key] then
                    RegisterTile(part :: BasePart)
                    SolverChanged = true
                end
            end
            
            for i = TileCount, 1, -1 do
                local t: TileData = Tiles[i]
                if not t.part or not CheckParentValid(t.part) then
                    UnregisterTile(i)
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
        
        if t and t.part then
            local newType: string, newNumber: number? = DetermineTileType(t.part)
            
            if newType ~= t.tileType or newNumber ~= t.number then
                t.tileType = newType
                t.number = newNumber
                t.hasRevealedNeighbor = nil
                
                if CheckParentValid(t.part) then
                    local posSuccess: boolean, pos: Vector3? = SafeGetProperty(t.part, "Position")
                    if posSuccess and pos then
                        t.storedPos = pos
                    end
                end
                
                SolverChanged = true
            end
        end
    end
end

local function PrepareRenderData(): ()
    RenderCount = 0
    
    for i = 1, TileCount do
        if RenderCount >= MAX_RENDER_TILES then break end
        
        local t: TileData? = Tiles[i]
        if not t then continue end
        
        if t.tileType == "unknown" then
            if t.predicted == "mine" or t.predicted == "safe" then
                RenderCount = RenderCount + 1
                RenderData[RenderCount] = t
            elseif t.probability and t.probability > 0.01 and t.probability < 0.99 then
                if t.hasRevealedNeighbor == nil then
                    t.hasRevealedNeighbor = false
                    local neighbors: {TileData} = FetchNeighbors(t)
                    
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
                RegisterTile(part :: BasePart)
            end
        end
    end
    
    SolverChanged = true
    SolveAll()
    PrepareRenderData()
end

local LastCameraUpdateTime: number = 0
local LastCharacterPosition: Vector3? = nil
local CAMERA_UPDATE_INTERVAL: number = 5

local function UpdateTopDownCamera(): ()
    if not _G.MS_AUTOFLAG then
        LastCharacterPosition = nil
        return
    end
    
    local cam = workspace.CurrentCamera
    if not cam then return end
    
    if not HumanoidRootPart or not CheckParentValid(HumanoidRootPart) then
        LastCharacterPosition = nil
        return
    end
    
    local posSuccess: boolean, charPos: Vector3? = SafeGetProperty(HumanoidRootPart, "Position")
    if not posSuccess or not charPos then return end
    
    local currentTime: number = OsClock()
    local shouldUpdate: boolean = false
    
    -- First time or respawn/new round (position changed drastically)
    if not LastCharacterPosition then
        shouldUpdate = true
    elseif currentTime - LastCameraUpdateTime >= CAMERA_UPDATE_INTERVAL then
        shouldUpdate = true
    else
        -- Check for respawn/teleport (large position change)
        local dx: number = charPos.X - LastCharacterPosition.X
        local dy: number = charPos.Y - LastCharacterPosition.Y
        local dz: number = charPos.Z - LastCharacterPosition.Z
        local distSq: number = dx * dx + dy * dy + dz * dz
        
        if distSq > 400 then -- More than 20 studs = likely respawn/teleport
            shouldUpdate = true
        end
    end
    
    if shouldUpdate then
        cam.CFrame = CFrame.new(charPos.X, charPos.Y + 50, charPos.Z) * CFrame.Angles(-math.pi/2, 0, 0)
        LastCameraUpdateTime = currentTime
    end
    
    LastCharacterPosition = charPos
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
    Pcall(PerformMemoryCleanup)
    Pcall(ValidateStaleTiles)
    Pcall(PerformDeepCleanup)
end

local function CleanupWalkMemory(): ()
    if not _G.MS_AUTOWALK and not WalkData.active then
        TrimPool(PathNodePool, 0)
        
        TableClear(PathCameFrom)
        TableClear(PathGScore)
        TableClear(PathFScore)
        TableClear(PathClosedSet)
        
        for i = #PathOpenSet, 1, -1 do
            PathOpenSet[i] = nil
        end
    end
end

local function CleanupAutoFlagMemory(): ()
    if not _G.MS_AUTOFLAG then
        LockedTarget = nil
        NextTargetQueued = nil
        LastTargetScreenPos = nil
        MouseStableFrames = 0
        IsUnflagging = false
        
        for i = #PendingVerifications, 1, -1 do
            PendingVerifications[i] = nil
        end
        
        CachedMineCandidateCount = 0
        CachedWrongFlagCandidateCount = 0
        LastAutoFlagScanTime = 0
    end
end

local function CleanupRenderMemory(): ()
    local currentTime: number = OsClock()
    
    if currentTime - LastScreenCacheTime > 5 then
        TableClear(CachedScreenPositions)
        LastScreenCacheTime = currentTime
    end
    
    for i = RenderCount + 1, #RenderData do
        RenderData[i] = nil
    end
end

local function SafePostLocal(): ()
    if not _G.MS_RUN then
        ResetAllState()
        return
    end
    
    Pcall(UpdateReferences)
    Pcall(ProcessInput)
    Pcall(UpdateTopDownCamera)
    Pcall(ProcessAutoFlag)
    Pcall(ExecuteWalkMovement)
    Pcall(UpdateWalkPath)
    Pcall(CleanupWalkMemory)
    Pcall(CleanupAutoFlagMemory)
end

local function UpdateScreenPositionCache(): ()
    local currentTime: number = OsClock()
    
    if currentTime - LastScreenCacheTime < SCREEN_CACHE_INTERVAL then
        return
    end
    
    LastScreenCacheTime = currentTime
    
    if not Camera then return end
    
    for i = 1, RenderCount do
        local t: TileData? = RenderData[i]
        if not t or not t.storedPos then continue end
        
        local screenPos: vector?, onScreen: boolean = SafeWorldToScreen(Camera, t.storedPos)
        
        if screenPos and onScreen then
            CachedScreenPositions[t] = VectorCreate(screenPos.X, screenPos.Y, 0)
        else
            CachedScreenPositions[t] = nil
        end
    end
end

local function SafeRender(): ()
    if not _G.MS_RUN then return end
    if not Camera then return end
    
    UpdateScreenPositionCache()
    
    local flagColor: Color3 = _G.MS_AUTOFLAG and COLOR_STATUS_ON or COLOR_STATUS_OFF
    local flagText: string = _G.MS_AUTOFLAG and "FLAG: ON (X)" or "FLAG: OFF (X)"
    
    local walkColor: Color3 = _G.MS_AUTOWALK and COLOR_WALK_ON or COLOR_STATUS_OFF
    local walkText: string = _G.MS_AUTOWALK and "WALK: ON (C)" or "WALK: OFF (C)"
    
    SafeDrawText(VectorCreate(12, 785, 0), 16, flagColor, 1, flagText, false)
    SafeDrawText(VectorCreate(12, 805, 0), 16, walkColor, 1, walkText, false)
    
    if BestMove and BestMove.storedPos then
        local cachedPos: vector? = CachedScreenPositions[BestMove]
        if not cachedPos then
            local screenPos: vector?, onScreen: boolean = SafeWorldToScreen(Camera, BestMove.storedPos)
            if screenPos and onScreen then
                cachedPos = VectorCreate(screenPos.X, screenPos.Y, 0)
            end
        end
        
        if cachedPos then
            local riskText: string = "BEST"
            if BestMoveRisk > 0 then
                local pct: number = MathFloor(BestMoveRisk * 100 + 0.5)
                riskText = "BEST (" .. tostring(pct) .. "%)"
            end
            
            SafeDrawText(VectorCreate(cachedPos.X, cachedPos.Y - 30, 0), 18, COLOR_BEST, 1, riskText, true)
        end
    end
    
    local renderCount: number = RenderCount
    if renderCount <= 0 then return end
    
    for i = 1, renderCount do
        local t: TileData? = RenderData[i]
        if not t then continue end
        
        local screenVec: vector? = CachedScreenPositions[t]
        if not screenVec then continue end
        
        local predicted: string | boolean = t.predicted
        
        if predicted == "mine" then
            SafeDrawText(screenVec, 22, COLOR_MINE, 1, "M", true)
        elseif predicted == "safe" then
            SafeDrawText(screenVec, 22, COLOR_SAFE, 1, "S", true)
        else
            local prob: number? = t.probability
            if prob and prob > 0 and prob < 1 then
                local pct: number = MathFloor(prob * 100 + 0.5)
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
    
    CleanupRenderMemory()
end

Pcall(Initialize)

RunService.PostModel:Connect(function(): ()
    Pcall(SafePostModel)
end)

RunService.PostLocal:Connect(function(): ()
    Pcall(SafePostLocal)
end)

RunService.Render:Connect(function(): ()
    Pcall(SafeRender)
end)
