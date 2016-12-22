------------------------------------------------------------
-- Copyright (c) 2016 tacigar. All rights reserved.
-- https://github.com/tacigar/maidroid
------------------------------------------------------------

local state = {
	WALK_RANDOMLY = 0,
	WALK_TO_PLANT = 1,
	WALK_TO_MOW   = 2,
	PLANT         = 3,
	MOW           = 4,
}

local target_plants = {
	"farming:cotton_8",
	"farming:wheat_8",
}

local _aux = maidroid_core._aux

local FIND_PATH_TIME_INTERVAL = 20
local CHANGE_DIRECTION_TIME_INTERVAL = 30
local MAX_WALK_TIME = 120

-- is_plantable_place reports whether maidroid can plant any seed.
local function is_plantable_place(pos)
	local node = minetest.get_node(pos)
	local lpos = vector.add(pos, {x = 0, y = -1, z = 0})
	local lnode = minetest.get_node(lpos)
	return node.name == "air"
		and minetest.get_item_group(lnode.name, "wet") > 0
end

-- is_mowable_place reports whether maidroid can mow.
local function is_mowable_place(pos)
	local node = minetest.get_node(pos)
	for _, plant in ipairs(target_plants) do
		if plant == node.name then
			return true
		end
	end
	return false
end

do -- register farming core

	local walk_randomly, walk_to_plant_and_mow_common, plant, mow
	local to_walk_randomly, to_walk_to_plant, to_walk_to_mow, to_plant, to_mow

	local function on_start(self)
		self.object:setacceleration{x = 0, y = -10, z = 0}
		self.object:setvelocity{x = 0, y = 0, z = 0}
		self.state = state.WALK_RANDOMLY
		self.time_counters = {}
		self.path = nil
		to_walk_randomly(self)
	end

	local function on_stop(self)
		self.object:setvelocity{x = 0, y = 0, z = 0}
		self.state = nil
		self.time_counters = nil
		self.path = nil
	end

	local function is_near(self, pos, distance)
		local p = self.object:getpos()
		p.y = p.y + 0.5
		return vector.distance(p, pos) < distance
	end

	local searching_range = {x = 5, y = 2, z = 5}

	walk_randomly = function(self, dtime)
		if self.time_counters[1] >= FIND_PATH_TIME_INTERVAL then
			self.time_counters[1] = 0
			self.time_counters[2] = self.time_counters[2] + 1

			if self:has_item_in_main(function(itemname)	return (minetest.get_item_group(itemname, "seed") > 0) end) then
				local destination = _aux.search_surrounding(self.object:getpos(), is_plantable_place, searching_range)
				if destination ~= nil then
					local path = minetest.find_path(self.object:getpos(), destination, 10, 1, 1, "A*")

					if path ~= nil then -- to walk to plant state.
						to_walk_to_plant(self, path, destination)
						return
					end
				end
			end
			-- if couldn't find path to plant, try to mow.
			local destination = _aux.search_surrounding(self.object:getpos(), is_mowable_place, searching_range)
			if destination ~= nil then
				local path = minetest.find_path(self.object:getpos(), destination, 10, 1, 1, "A*")
				if path ~= nil then -- to walk to mow state.
					for _, p in ipairs(path) do
						print(p.x, p.y, p.z)
					end

					to_walk_to_mow(self, path, destination)
					return
				end
			end
			-- else do nothing.
			return

		elseif self.time_counters[2] >= CHANGE_DIRECTION_TIME_INTERVAL then
			self.time_counters[1] = self.time_counters[1] + 1
			self.time_counters[2] = 0
			self:change_direction_randomly()
			return
		else
			self.time_counters[1] = self.time_counters[1] + 1
			self.time_counters[2] = self.time_counters[2] + 1
			return
		end
	end

	to_walk_randomly = function(self)
		print("to walk randomly")
		self.state = state.WALK_RANDOMLY
		self.time_counters[1] = 0
		self.time_counters[2] = 0
		self:change_direction_randomly()
		self:set_animation(maidroid.animation_frames.WALK)
	end

	to_walk_to_plant = function(self, path, destination)
		print("to walk to plant")
		self.state = state.WALK_TO_PLANT
		self.path = path
		self.destination = destination
		self.time_counters[1] = 0 -- find path interval
		self.time_counters[2] = 0
		self:change_direction(self.path[1])
		self:set_animation(maidroid.animation_frames.WALK)
	end

	to_walk_to_mow = function(self, path, destination)
		print("to walk to mow")
		self.state = state.WALK_TO_MOW
		self.path = path
		self.destination = destination
		self.time_counters[1] = 0 -- find path interval
		self.time_counters[2] = 0
		self:change_direction(self.path[1])
		self:set_animation(maidroid.animation_frames.WALK)
	end

	to_plant = function(self)
		print("to plant")
		if self:move_main_to_wield(function(itemname)	return (minetest.get_item_group(itemname, "seed") > 0) end) then
			self.state = state.PLANT
			self.time_counters[1] = 0
			self.object:setvelocity{x = 0, y = 0, z = 0}
			self:set_animation(maidroid.animation_frames.MINE)
			return
		else
			to_walk_randomly(self)
			return
		end
	end

	to_mow = function(self)
		print("to mow")
		self.state = state.MOW
		self.time_counters[1] = 0
		self.object:setvelocity{x = 0, y = 0, z = 0}
		self:set_animation(maidroid.animation_frames.MINE)
	end

	walk_to_plant_and_mow_common = function(self, dtime)
		if is_near(self, self.destination, 1.0) then
			if self.state == state.WALK_TO_PLANT then
				to_plant(self)
				return
			elseif self.state == state.WALK_TO_MOW then
				to_mow(self)
				return
			end
		end

		if self.time_counters[2] >= MAX_WALK_TIME then -- time over.
			to_walk_randomly(self)
			return
		end

		self.time_counters[1] = self.time_counters[1] + 1
		self.time_counters[2] = self.time_counters[2] + 1

		if self.time_counters[1] >= FIND_PATH_TIME_INTERVAL then
			print("KOKOKOK")
			self.time_counters[1] = 0
			self.time_counters[2] = self.time_counters[2] + 1
			local path = minetest.find_path(self.object:getpos(), self.destination, 10, 1, 1, "A*")
			if path == nil then
				to_walk_randomly(self)
				return
			end
			self.path = path
		end

		-- follow path
		if is_near(self, self.path[1], 0.01) then
			print("KOK")
			table.remove(self.path, 1)

			if #self.path == 0 then -- end of path
				if self.state == state.WALK_TO_PLANT then
					to_plant(self)
					return
				elseif self.state == state.WALK_TO_MOW then
					to_mow(self)
					return
				end
			else -- else next step, follow next path.
				self:change_direction(self.path[1])
			end

		else
			-- self:change_direction(self.path[1])
			-- if maidroid is stopped by obstacles, the maidroid must jump.
			-- self:change_direction(self.path[1])
			local velocity = self.object:getvelocity()
			if velocity.y == 0 then
				local front_node = self:get_front_node()
				if front_node.name ~= "air" then
					self.object:setvelocity{x = velocity.x, y = 3, z = velocity.z}
				end
			end
		end
	end

	plant = function(self, dtime)
		if self.time_counters[1] >= 15 then
			if is_plantable_place(self.destination) then
				local stack = self:get_wield_item_stack()
				local itemname = stack:get_name()
				minetest.add_node(self.destination, {name = itemname, param2 = 1})
				stack:take_item(1)
				self:set_wield_item_stack(stack)
			end
			to_walk_randomly(self)
			return
		else
			self.time_counters[1] = self.time_counters[1] + 1
		end
	end

	mow = function(self, dtime)
		if self.time_counters[1] >= 15 then
			if is_mowable_place(self.destination) then
				local destnode = minetest.get_node(self.destination)
				minetest.remove_node(self.destination)
				local stacks = minetest.get_node_drops(destnode.name)

				for _, stack in ipairs(stacks) do
					local leftover = self:add_item_to_main(stack)
					minetest.add_item(self.destination, leftover)
				end
			end
			to_walk_randomly(self)
			return
		else
			self.time_counters[1] = self.time_counters[1] + 1
		end
	end

	local function on_step(self, dtime)
		if self.state == state.WALK_RANDOMLY then
--			print("== now walk randomly")
			walk_randomly(self, dtime)
		elseif self.state == state.WALK_TO_PLANT or self.state == state.WALK_TO_MOW then
--			print("== now walk to *")
			walk_to_plant_and_mow_common(self, dtime)
		elseif self.state == state.PLANT then
--			print("== now plant")
			plant(self, dtime)
		elseif self.state == state.MOW then
--			print("== now mow")
			mow(self, dtime)
		end
	end

	maidroid.register_core("maidroid_core:farming", {
		description      = "maidroid core : farming",
		inventory_image  = "maidroid_core_farming.png",
		on_start         = on_start,
		on_stop          = on_stop,
		on_resume        = on_start,
		on_pause         = on_stop,
		on_step          = on_step,
	})

end -- register farming core
