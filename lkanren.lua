-- Implementaiton of micro-kanren, plus some idiosyncratic extensions
-- see: http://webyrd.net/scheme-2013/papers/HemannMuKanren2013.pdf


-- Variables
local variable_mt = {
	__tostring = function(v) return "_"..v.id end,
	__eq = function(a, b) return a.id == b.id end
}

local function variable(id)
	v = {id=id}
	setmetatable(v, variable_mt)
	return v
end

local function isVar(v)
	return getmetatable(v) == variable_mt
end

-- State

local function empty()
	return {
		-- substitutions is a map between the string encoding of variables
		-- and either variables or concrete values.
		substitutions = {},
		count = 0
		}
end

local function increment(state)
	local new = table_copy(state)
	new.count = new.count + 1
	return new
end


-- This implementation of walk recurses over lists and tables;
local function walk(u, state)
	if not isVar(u) then
		if type(u) == 'table' then
			local ret = {}
			for k,v in pairs(u) do
				ret[k] = walk(v, state)
			end
			return ret
		end
		return u
	end
	if state.substitutions[tostring(u)] ~= nil then
		return walk(state.substitutions[tostring(u)], state)
	end
	return u
end

local function extend(u, v, state)
	if not isVar(u) then
		error ("can only extend a set of substitutions with variables, got"..u)
	end
	local new = table_copy(state)
	new.substitutions[tostring(u)] = v

	return new
end

-- Streams

local function stream(first, rest)
	if rest ~= nil and type(rest) ~= 'function' then
		error "When construction a stream, 'rest' must be a function if non-nil"
	end
	return {first=first, rest=rest}
end

-- constructs a stream with a single state
local function unit(state)
	return stream(state, nil)
end

local function merge(stream1, stream2)
	if stream1 == nil or (stream1.first == nil and stream1.rest == nil) then
		return stream2
	end
	if stream1.first == nil and stream1.rest ~= nil then
		return stream(
			nil,
			function() return merge(stream2, stream1.rest()) end
		)
	end

	if stream1.rest ~= nil then
		return stream(
			stream1.first,
			function() return merge(stream1.rest(), stream2) end
		)
	else
		return stream(
			stream1.first,
			function() return stream2 end
		)
	end
end

-- goals are func -> state ->stream
local function bind(stream1, goal)
	-- TODO(andrew): clean this up.
	if stream1 == nil or (stream1.first == nil and stream1.rest == nil) then
		return stream(nil, nil)
	end
	if stream1.first == nil and stream1.rest ~= nil  then
		return bind(stream1.rest(), goal)
	end
	if stream1.rest == nil then
		return goal(stream1.first)
	end
	return merge( goal(stream1.first), bind( stream1.rest(), goal))
end

-- unify
local function unify(u, v, state)
	u = walk(u, state)
	v = walk(v, state)
	if isVar(u) and isVar(v) and u == v then
		return state
	elseif isVar(u) then
		return extend(u, v, state)
	elseif isVar(v) then
		return extend(v, u, state)
	elseif type(u) == 'table' and type(v) == 'table' then
		-- if the keys in each table are different, then we can't unify.
		if not check_keys(u, v) then
			return nil
		end
		for k,u_value in pairs(u) do
			state = unify(u_value, v[k], state)
			if state == nil then
				return nil
			end
		end
		return state
	elseif table_eq(u, v) then
		return state
	end
	return nil
end

-- goal constructors
local function equal(u, v)
	return function(state)
		local s1 = unify(u, v, state)
		if s1 ~= nil then
			return unit(s1)
		else
			return nil
		end
	end
end

local function disj(goal1, goal2)
	return function(state)
		return merge(goal1(state), goal2(state))
	end
end

local function conj(goal1, goal2)
	return function(state)
		return bind(goal1(state), goal2)
	end
end


-- main entry point
-- f: variable -> state -> stream
local function call_fresh(f)
	return function(state)
		local v = variable(state.count)
		return f(v)(increment(state))
	end
end

local function reify1st(state)
	return walk(variable(0), state)
end

local function pull(stream, n, e)
	e = e or function(v) return v end
	local results = {}
	while #results < n and stream ~= nil do
		if stream.first ~= nil then
			results[#results + 1] = e(stream.first)
		end
		if stream.rest ~= nil then
			stream = stream.rest()
		else
			return results
		end
	end
	return results
end

local function reifyN1st(stream, n)
	return pull(stream, n, reify1st)
end

return {
	-- Variables
	variable = variable,
	isVar = isVar,

	-- States
	extend = extend,
	empty = empty,

	-- streams
	stream = stream,
	unit = unit,

	equal = equal,
	conj = conj,
	disj = disj,

	call_fresh = call_fresh,

	-- helpers
	reifyN1st = reifyN1st
}