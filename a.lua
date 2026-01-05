--!native
--!optimize 2
loadstring(game:HttpGet("https://raw.githubusercontent.com/Sploiter13/severefuncs/refs/heads/main/merge2.lua"))();
task.wait(2)
---- environment ----
local game = game
local workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local math_floor = math.floor
local math_sqrt = math.sqrt
local math_min = math.min
local math_max = math.max
local math_abs = math.abs
local table_insert = table.insert
local table_remove = table.remove
local table_sort = table.sort
local string_lower = string.lower
local string_find = string.find
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local os_clock = os.clock
local task_spawn = task.spawn
local task_wait = task.wait

local vector_create = vector.create
local vector_magnitude = vector.magnitude

local getpressedkeys = getpressedkeys
local getmouseposition = getmouseposition
local mouse1click = mouse1click

---- constants ----
local SAFE_TEXT: string = ""
local SPACING: number = 5
local ORIGIN: Vector3 = Vector3.new(0, 70, 0)
local LOOP_DELAY: number = 0.05
local AUTO_FLAG_ENABLED: boolean = true
local TRIGGERBOT_KEY: number = 0x05
local DETECTION_RADIUS: number = 15
local CLICK_DELAY: number = 0.05
local VERIFY_DELAY: number = 0.1
local VISUAL_RANGE: number = 1000
local MIN_CONFIDENCE_TO_FLAG: number = 0.95
local LOCK_SMOOTHNESS: number = 0.01
local CLICK_TOLERANCE: number = 45
local SOLVE_THROTTLE: number = 0.1
local NEARBY_CACHE_DURATION: number = 0.1

local NEIGH_OFFSETS: {{number}} = {
	{-1,-1},{-1,0},{-1,1},
	{0,-1},        {0,1},
	{1,-1},{1,0},{1,1}
}

---- variables ----
local local_player: Player? = nil
local camera: Camera? = nil
local flag_model: Instance? = nil
local ms_parts: Instance? = nil

local tiles: {any} = {}
local grid: {[string]: any} = {}
local render_buffer: {any} = {}
local pending_verification: {any} = {}
local neighbor_cache: {[string]: {any}} = {}
local nearby_mines_cache: {any} = {}

local last_click_time: number = 0
local triggerbot_active: boolean = false
local locked_target: any = nil
local state_dirty: boolean = true
local last_solve_tick: number = 0
local nearby_mines_cache_time: number = 0

---- functions ----
local function get_tile_position(part: BasePart): Vector3?
	if not part then return nil end
	
	local success, pos = pcall(function()
		if not part.Parent then return nil end
		local cls = part.ClassName
		if cls == "Part" or cls == "MeshPart" or cls == "UnionOperation" then
			return part.Position
		end
		return nil
	end)
	
	return success and pos or nil
end

local function safe_pos_to_key(part: BasePart): (string?, number?, number?)
	local pos = get_tile_position(part)
	if not pos then return nil, nil, nil end

	local gx = math_floor((pos.X - ORIGIN.X) / SPACING + 0.5)
	local gz = math_floor((pos.Z - ORIGIN.Z) / SPACING + 0.5)
	return gx.."|"..gz, gx, gz
end

local function is_already_flagged(part: BasePart): boolean
	if not part then return false end
	
	local success, result = pcall(function()
		if not part.Parent then return false end
		
		local flag_check = part:FindFirstChild("Flag")
		if flag_check then return true end
		
		local transparency = part.Transparency
		if transparency > 0.9 then return true end
		
		local children = part:GetChildren()
		for _, child in ipairs(children) do
			if child and child.Parent then
				local name_lower = string_lower(child.Name)
				if string_find(name_lower, "flag") or string_find(name_lower, "marker") then
					return true
				end
			end
		end
		
		return false
	end)
	
	return success and result or false
end

local function classify_tile(part: BasePart): (string, number?)
	if not part then return "deleted", nil end

	local success, tile_type, tile_num = pcall(function()
		if not part.Parent then return "deleted", nil end
		
		local gui = part:FindFirstChild("NumberGui")
		if gui then
			local label = gui:FindFirstChild("TextLabel")
			if label and label.ClassName == "TextLabel" then
				local text = label.Text
				
				if text == SAFE_TEXT or text == " " then
					return "empty", 0
				end
				
				local n = tonumber(text)
				if n then
					return "number", n
				end
				
				local text_lower = string_lower(text)
				if string_find(text_lower, "mine") or string_find(text_lower, "bomb") then
					return "mine", nil
				end
			end
			
			return "empty", 0
		end

		return "unknown", nil
	end)

	if success then
		return tile_type, tile_num
	end
	return "deleted", nil
end

local function generate_tile(part: BasePart)
	local key, gx, gz = safe_pos_to_key(part)
	if not key then return end

	if grid[key] then
		grid[key].part = part
		return
	end

	local tp, val = classify_tile(part)
	local t = {
		part = part,
		gx = gx,
		gz = gz,
		type = tp,
		number = val,
		predicted = false,
		probability = nil,
		constraint_count = 0,
		flagged = false,
		click_time = 0,
		confidence = 0,
	}
	table_insert(tiles, t)
	grid[key] = t
	
	neighbor_cache[key] = nil
end

local function get_neighbors(t: any): {any}
	local key = t.gx.."|"..t.gz
	if neighbor_cache[key] then
		return neighbor_cache[key]
	end
	
	local out = {}
	for _, o in ipairs(NEIGH_OFFSETS) do
		local nkey = (t.gx + o[1]) .. "|" .. (t.gz + o[2])
		local v = grid[nkey]
		if v then table_insert(out, v) end
	end
	
	neighbor_cache[key] = out
	return out
end

local function analyze_neighbors(t: any): (number, {any})
	local adj = get_neighbors(t)
	local known_mines = 0
	local unknowns = {}
	
	for _, n in ipairs(adj) do
		if n.type == "mine" or (n.predicted == "mine" and n.confidence >= MIN_CONFIDENCE_TO_FLAG) then
			known_mines = known_mines + 1
		elseif n.type == "unknown" and n.predicted ~= "safe" then
			table_insert(unknowns, n)
		end
	end
	return known_mines, unknowns
end

local function create_constraints(): {any}
	local constraints = {}
	
	for _, t in ipairs(tiles) do
		if t.type == "number" then
			local mines, unknowns = analyze_neighbors(t)
			local needed = t.number - mines
			
			if #unknowns > 0 then
				table_insert(constraints, {
					tile = t,
					unknowns = unknowns,
					mines_needed = needed
				})
			end
		end
	end
	
	return constraints
end

local function get_shared_unknowns(c1: any, c2: any): {any}
	local shared = {}
	local lookup = {}
	
	for _, u in ipairs(c1.unknowns) do
		lookup[u] = true
	end
	
	for _, u in ipairs(c2.unknowns) do
		if lookup[u] then
			table_insert(shared, u)
		end
	end
	
	return shared
end

local function solve_constraints(): boolean
	local constraints = create_constraints()
	local changed = false
	
	if #constraints == 0 then return false end
	
	for i = 1, #constraints do
		for j = i + 1, #constraints do
			local c1 = constraints[i]
			local c2 = constraints[j]
			
			local shared = get_shared_unknowns(c1, c2)
			
			if #shared > 0 and #shared < #c1.unknowns and #shared < #c2.unknowns then
				local c1_only = {}
				local c2_only = {}
				
				local shared_lookup = {}
				for _, u in ipairs(shared) do
					shared_lookup[u] = true
				end
				
				for _, u in ipairs(c1.unknowns) do
					if not shared_lookup[u] then
						table_insert(c1_only, u)
					end
				end
				
				for _, u in ipairs(c2.unknowns) do
					if not shared_lookup[u] then
						table_insert(c2_only, u)
					end
				end
				
				if #c1_only == 0 and #c2_only > 0 then
					local diff_mines = c2.mines_needed - c1.mines_needed
					
					if diff_mines == 0 then
						for _, u in ipairs(c2_only) do
							if u.predicted ~= "safe" then
								u.predicted = "safe"
								u.confidence = 1.0
								changed = true
							end
						end
					elseif diff_mines == #c2_only then
						for _, u in ipairs(c2_only) do
							if u.predicted ~= "mine" then
								u.predicted = "mine"
								u.confidence = 1.0
								changed = true
							end
						end
					end
				end
				
				if #c2_only == 0 and #c1_only > 0 then
					local diff_mines = c1.mines_needed - c2.mines_needed
					
					if diff_mines == 0 then
						for _, u in ipairs(c1_only) do
							if u.predicted ~= "safe" then
								u.predicted = "safe"
								u.confidence = 1.0
								changed = true
							end
						end
					elseif diff_mines == #c1_only then
						for _, u in ipairs(c1_only) do
							if u.predicted ~= "mine" then
								u.predicted = "mine"
								u.confidence = 1.0
								changed = true
							end
						end
					end
				end
			end
		end
	end
	
	return changed
end

local function solve_step(): boolean
	local changed = false
	
	for _, t in ipairs(tiles) do
		if t.type == "number" then
			local mines, unknowns = analyze_neighbors(t)
			local needed = t.number - mines
			local count_u = #unknowns
			
			if count_u > 0 then
				if needed == 0 then
					for _, u in ipairs(unknowns) do
						if u.predicted ~= "safe" then
							u.predicted = "safe"
							u.confidence = 1.0
							changed = true
						end
					end
				elseif needed == count_u then
					for _, u in ipairs(unknowns) do
						if u.predicted ~= "mine" then
							u.predicted = "mine"
							u.confidence = 1.0
							changed = true
						end
					end
				elseif needed < 0 then
					for _, u in ipairs(unknowns) do
						if u.predicted and u.confidence < 1.0 then
							u.predicted = false
							u.confidence = 0
							changed = true
						end
					end
				end
			end
		end
	end
	
	return changed
end

local function calculate_probabilities()
	local constraints = create_constraints()
	
	for _, t in ipairs(tiles) do
		if t.type == "unknown" and not t.predicted then
			t.probability = 0
			t.constraint_count = 0
		end
	end
	
	for _, c in ipairs(constraints) do
		if #c.unknowns > 0 and c.mines_needed >= 0 then
			local prob_per_tile = c.mines_needed / #c.unknowns
			
			for _, u in ipairs(c.unknowns) do
				if not u.predicted then
					u.probability = u.probability + prob_per_tile
					u.constraint_count = u.constraint_count + 1
				end
			end
		end
	end
	
	for _, t in ipairs(tiles) do
		if t.type == "unknown" and not t.predicted then
			if t.constraint_count > 0 then
				t.probability = t.probability / t.constraint_count
				t.confidence = math_min(t.probability, 1.0)
			else
				t.probability = 0.3
				t.confidence = 0
			end
		end
	end
end

local function verify_predictions()
	for _, t in ipairs(tiles) do
		if t.predicted == "mine" and t.confidence > 0 then
			local neighbors = get_neighbors(t)
			
			for _, n in ipairs(neighbors) do
				if n.type == "number" then
					local mines, unknowns = analyze_neighbors(n)
					
					if mines > n.number then
						t.predicted = false
						t.confidence = 0
					elseif mines == n.number then
						t.confidence = math_min(t.confidence + 0.1, 1.0)
					end
				end
			end
		end
	end
end

local function get_best_guesses(top_n: number): {any}
	local candidates = {}
	
	for _, t in ipairs(tiles) do
		if t.type == "unknown" and not t.predicted then
			table_insert(candidates, t)
		end
	end
	
	table_sort(candidates, function(a, b)
		local prob_a = a.probability or 0.5
		local prob_b = b.probability or 0.5
		
		if math_abs(prob_a - prob_b) < 0.01 then
			local count_a = a.constraint_count or 0
			local count_b = b.constraint_count or 0
			return count_a > count_b
		end
		
		return prob_a < prob_b
	end)
	
	local result = {}
	for i = 1, math_min(top_n or 3, #candidates) do
		table_insert(result, candidates[i])
	end
	
	return result
end

local function has_definite_moves(): boolean
	for _, t in ipairs(tiles) do
		if (t.predicted == "safe" and t.confidence >= 0.99) or 
		   (t.predicted == "mine" and t.confidence >= MIN_CONFIDENCE_TO_FLAG) then
			return true
		end
	end
	return false
end

local function get_nearby_mines(): {any}
	local current_time = os_clock()
	
	if current_time - nearby_mines_cache_time < NEARBY_CACHE_DURATION then
		return nearby_mines_cache
	end
	
	if not local_player then return {} end
	
	local success, nearby = pcall(function()
		local character = local_player.Character
		if not character or not character.Parent then return {} end
		
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or root.ClassName ~= "Part" then return {} end
		
		local char_pos = root.Position
		local result = {}
		
		for _, t in ipairs(tiles) do
			if t and t.predicted == "mine" and t.confidence >= MIN_CONFIDENCE_TO_FLAG and not t.flagged and t.type ~= "mine" then
				if t.part and t.part.Parent then
					if not is_already_flagged(t.part) then
						local tile_pos = get_tile_position(t.part)
						if tile_pos then
							local delta = char_pos - tile_pos
							local dist = vector_magnitude(delta)
							if dist <= DETECTION_RADIUS then
								table_insert(result, {tile = t, distance = dist, position = tile_pos})
							end
						end
					end
				end
			end
		end
		
		table_sort(result, function(a, b) return a.distance < b.distance end)
		return result
	end)
	
	if not success then nearby = {} end
	
	nearby_mines_cache = nearby
	nearby_mines_cache_time = current_time
	
	return nearby
end

local function verify_flags()
	local current_time = os_clock()
	
	for i = #pending_verification, 1, -1 do
		local entry = pending_verification[i]
		
		if current_time - entry.time >= VERIFY_DELAY then
			local tile = entry.tile
			
			pcall(function()
				if tile.part and tile.part.Parent then
					if is_already_flagged(tile.part) or tile.type == "mine" then
						tile.flagged = true
						
						if locked_target and locked_target.tile == tile then
							locked_target = nil
						end
					else
						tile.flagged = false
						tile.click_time = 0
					end
				end
			end)
			
			table_remove(pending_verification, i)
		end
	end
end

local function update_triggerbot()
	local pressed = getpressedkeys()
	local is_pressed = false
	for _, key in ipairs(pressed) do
		if key == TRIGGERBOT_KEY then
			is_pressed = true
			break
		end
	end
	
	triggerbot_active = is_pressed
	
	if not triggerbot_active then
		locked_target = nil
		return
	end
	
	verify_flags()
	
	local current_time = os_clock()
	
	if locked_target then
		local tile = locked_target.tile
		
		pcall(function()
			if not tile.part or not tile.part.Parent or tile.flagged or 
			   is_already_flagged(tile.part) or tile.type ~= "unknown" then
				locked_target = nil
			end
		end)
	end
	
	if not locked_target then
		local nearby_mines = get_nearby_mines()
		
		if #nearby_mines > 0 then
			locked_target = nearby_mines[1]
		end
	end
	
	if locked_target and camera then
		pcall(function()
			local target_screen_pos, visible = camera:WorldToScreenPoint(locked_target.position)
			
			if visible then
				local current_mouse = getmouseposition()
				
				local dist_to_target = math_sqrt(
					(current_mouse.X - target_screen_pos.X)^2 + 
					(current_mouse.Y - target_screen_pos.Y)^2
				)
				
				if dist_to_target <= CLICK_TOLERANCE and current_time - last_click_time >= CLICK_DELAY then
					local tile_type, _ = classify_tile(locked_target.tile.part)
					if tile_type == "unknown" then
						local success = pcall(function()
							mouse1click()
						end)
						
						if success then
							locked_target.tile.click_time = current_time
							last_click_time = current_time
							
							table_insert(pending_verification, {
								tile = locked_target.tile,
								time = current_time
							})
						end
					end
				end
			end
		end)
	end
end

local function update_loop()
	pcall(function()
		if not camera then camera = workspace.CurrentCamera end
		if not local_player then local_player = Players.LocalPlayer end
		
		if not ms_parts or not ms_parts.Parent then
			local f = workspace:FindFirstChild("Flag")
			if f then ms_parts = f:FindFirstChild("Parts") end
		end

		if ms_parts and ms_parts.Parent then
			local children = ms_parts:GetChildren()
			local current_lookup = {}
			
			for _, p in ipairs(children) do
				current_lookup[p] = true
				generate_tile(p)
			end

			for i = #tiles, 1, -1 do
				local valid = false
				pcall(function()
					if tiles[i].part.Parent and current_lookup[tiles[i].part] then
						valid = true
					end
				end)
				
				if not valid then
					local t = tiles[i]
					local k = t.gx.."|"..t.gz
					if grid[k] == t then grid[k] = nil end
					neighbor_cache[k] = nil
					table_remove(tiles, i)
					state_dirty = true
				end
			end

			local state_changed = false
			for _, t in ipairs(tiles) do
				local new_type, new_num = classify_tile(t.part)
				if new_type ~= t.type or new_num ~= t.number then
					t.type = new_type
					t.number = new_num
					t.predicted = false
					t.probability = nil
					t.constraint_count = 0
					t.confidence = 0
					state_changed = true
					state_dirty = true
					
					local key = t.gx.."|"..t.gz
					neighbor_cache[key] = nil
					for _, o in ipairs(NEIGH_OFFSETS) do
						local nkey = (t.gx + o[1]) .. "|" .. (t.gz + o[2])
						neighbor_cache[nkey] = nil
					end
				end
			end

			local current_time = os_clock()
			if state_changed or (state_dirty and current_time - last_solve_tick >= SOLVE_THROTTLE) then
				for i = 1, 15 do
					local basic_changed = solve_step()
					local advanced_changed = solve_constraints()
					if not basic_changed and not advanced_changed then 
						state_dirty = false
						break 
					end
				end
				
				verify_predictions()
				last_solve_tick = current_time
			end
			
			calculate_probabilities()
			update_triggerbot()
			
			local new_buffer = {}
			
			for _, t in ipairs(tiles) do
				if t.predicted == "mine" and t.confidence >= MIN_CONFIDENCE_TO_FLAG and t.type ~= "mine" then
					local already_flagged = is_already_flagged(t.part)
					if already_flagged then
						t.flagged = true
					end
					
					local conf_pct = math_floor(t.confidence * 100)
					local marker = t.flagged and "M✓" or ("M" .. conf_pct)
					local marker_color = t.flagged and Color3.new(0.5, 0.5, 0.5) or Color3.new(1, 0, 0)
					table_insert(new_buffer, {part = t.part, text = marker, col = marker_color})
				elseif t.type == "mine" then
					table_insert(new_buffer, {part = t.part, text = "M✓", col = Color3.new(1, 0, 0)})
				elseif t.predicted == "safe" and t.confidence >= 0.99 and t.type == "unknown" then
					table_insert(new_buffer, {part = t.part, text = "S", col = Color3.new(0, 1, 0)})
				end
			end
			
			if not has_definite_moves() then
				local best_guesses = get_best_guesses(3)
				
				for i, t in ipairs(best_guesses) do
					local prob = t.probability or 0.5
					local pct = math_floor(prob * 100 + 0.5)
					
					if i == 1 then
						table_insert(new_buffer, {part = t.part, text = "★" .. pct, col = Color3.new(0, 1, 1)})
					elseif i == 2 then
						table_insert(new_buffer, {part = t.part, text = "2:" .. pct, col = Color3.new(0.5, 1, 0.5)})
					elseif i == 3 then
						table_insert(new_buffer, {part = t.part, text = "3:" .. pct, col = Color3.new(1, 1, 0.5)})
					end
				end
			end
			
			render_buffer = new_buffer
		end
	end)
end

---- runtime ----
task_spawn(function()
	task_wait(0.5)
	pcall(function()
		local_player = Players.LocalPlayer
		camera = workspace.CurrentCamera
		flag_model = workspace:FindFirstChild("Flag")
		if flag_model then ms_parts = flag_model:FindFirstChild("Parts") end
	end)
end)

task_spawn(function()
	while true do
		update_loop()
		task_wait(LOOP_DELAY)
	end
end)

RunService.Render:Connect(function()
	if not camera or not local_player then return end
	
	pcall(function()
		local character = local_player.Character
		if not character or not character.Parent then return end
		
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or root.ClassName ~= "Part" then return end
		
		local char_pos = root.Position
		local viewport = camera.ViewportSize
		
		if triggerbot_active then
			local status_text = "AUTO-FLAG: " .. (locked_target and "LOCKED" or "SEARCHING")
			local status_color = locked_target and Color3.new(1, 0, 0) or Color3.new(1, 1, 0)
			
			DrawingImmediate.OutlinedText(
				vector_create(viewport.X / 2 - 100, 50, 0),
				18,
				status_color,
				1,
				status_text,
				true,
				"Tamzen"
			)
			
			if locked_target then
				local target_screen, visible = camera:WorldToScreenPoint(locked_target.position)
				if visible then
					local screen_pos = vector_create(target_screen.X, target_screen.Y, 0)
					DrawingImmediate.Circle(screen_pos, 20, Color3.new(1, 0, 0), 1, 2)
					DrawingImmediate.Circle(screen_pos, 15, Color3.new(1, 0, 0), 1, 2)
				end
			end
		end
		
		for _, item in ipairs(render_buffer) do
			if item.part and item.part.Parent then
				local pos = get_tile_position(item.part)
				if pos then
					local delta = char_pos - pos
					local dist = vector_magnitude(delta)
					
					if dist <= VISUAL_RANGE then
						local screen_pos, visible = camera:WorldToScreenPoint(pos)
						
						if visible then
							DrawingImmediate.OutlinedText(
								vector_create(screen_pos.X, screen_pos.Y, 0),
								16,
								item.col,
								1,
								item.text,
								true,
								"Tamzen"
							)
						end
					end
				end
			end
		end
	end)
end)
