-- Implementaiton of micro-kanren, plus some idiosyncratic extensions
-- see: http://webyrd.net/scheme-2013/papers/HemannMuKanren2013.pdf


-- Variables
local variable_mt = {
	__tostring = function(v) return "_"..v.count end,
	__eq = function(a, b) return a.count == b.count end
}

local function variable(count)
	v = {count=count}
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

local function walk(u, state)
	if state == nil then
		print(debug.traceback())
	end
	if not isVar(u) then
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
	print("BINDING", table_tostring(stream1), goal)
	if stream1 == nil or (stream1.first == nil and stream1.rest == nil) then
		print("nasty shit in bind")
		return stream(nil, nil)
	end
	if stream1.first == nil and stream1.rest ~= nil  then
		print("bind to rest of stream")
		return bind(stream1.rest(), goal)
	end
	if stream1.rest == nil then
		print("only one state, apply the goal and move on")
		return goal(stream1.first)
	end
	print("returning the merge")
	return merge( goal(stream1.first), bind( stream1.rest(), goal))
end

-- unify
local function unify(u, v, state)
	u = walk(u, state)
	v = walk(v, state)
	print("unifying",u,v)
	if isVar(u) and isVar(v) and u == v then
		return state
	elseif isVar(u) then
		return extend(u, v, state)
	elseif isVar(v) then
		return extend(v, u, state)
	-- TODO(andrew): recurse over structured data.

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
	return state.substitutions["_0"]
end

local function pull(stream, n, e)
	e = e or function(v) return v end
	local results = {}
	while #results < n and stream ~= nil do
		if stream.first ~= nil then
			results[#results + 1] = e(stream.first)
			print("pulled", table_tostring(stream.first))
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

	reifyN1st = reifyN1st
}