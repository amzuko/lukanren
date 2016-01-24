local logic = require("lkanren")
require("util")

local cf = logic.call_fresh
local eq = logic.equal
local conj = logic.conj
local disj = logic.disj

local assert_count = 0
function assert_eq(actual, expected, message)
	assert_count = assert_count + 1
	if not table_eq(expected, actual) then
		error (message or ("Expected " .. table_tostring(expected) ..
							" got " .. table_tostring(actual)),
				2)
	end
end

local assert_one_result = function(f, expected)
	local stream = f(logic.empty())
	assert_eq(logic.reifyN1st(stream, 1), {expected})
end

local TestLogic = {}

TestLogic.testVariable = function()
	local v1 = logic.variable(123)
	local s = tostring(v1)
	assert_eq(s, "_123")

	local v2 = logic.variable(123)
	local eq = v1 == v2
	assert_eq(eq, true)
	assert_eq(v1, v2)

	local v3 = logic.variable(234)
	eq = v1 == v3
	assert_eq(eq, false)

	assert_eq(logic.isVar({}), false)
	assert_eq(logic.isVar(v1), true)
end

TestLogic.testReify = function()
	local s1 = logic.unit(logic.extend(logic.variable(0), "bar",
										logic.empty()))
	local reified = logic.reifyN1st(s1, 1)
	assert_eq(reified, {"bar"})
end

TestLogic.testEquate = function()
	local testEquate = function(value, message_prefix)
		message_prefix = message_prefix or type(value)
		local s = logic.call_fresh(function(v)
			return logic.equal(v, value)
		end)(logic.empty())

		local r = logic.reifyN1st(s, 1)
		assert_eq(r, {value}, message_prefix .. " failed to unify.")
	end

	testEquate(123)
	testEquate(0)
	testEquate("hello, world")
	testEquate(function(a,b)return a + b end)
	testEquate({hello="world"})
	testEquate({})
	testEquate({1,2,3})
	testEquate(true)
	testEquate(false)


	local s = logic.call_fresh(function(v)
		return logic.equal(123, 345)
	end)(logic.empty())
	assert_eq(logic.reifyN1st(s, 1), {})
end

TestLogic.testConj = function()
	local s = cf(function(v1) return
			cf(function(v2) return
			conj(
				eq(v2, 123),
				eq(v1, v2)
			)
		end)
		end) (logic.empty())

	assert_eq(logic.reifyN1st(s, 1), {123})


	local s = cf(function(v1) return
			cf(function(v2) return
			cf(function(v3) return
			conj(
				conj(
					eq(v3, "foobarbaz"),
					eq(v3, v2)
				),
				eq(v2, v1)
				)
			end)
		end)
		end) (logic.empty())

	assert_eq(logic.reifyN1st(s, 1), {"foobarbaz"})

end

TestLogic.testDisj = function()
	local s = cf(function(v1) return
			disj(
				eq(v1, 123),
				eq(v1, 345)
			)
		end) (logic.empty())
	assert_eq(logic.reifyN1st(s, 2), {123, 345})
end


TestLogic.testStructured = function()

	assert_one_result(
		cf(function(v1) return
			eq({foo=v1}, {foo="bar"})
			end),
		"bar")

	assert_one_result(
			cf(function(v1) return
			cf(function(v2) return
			cf(function(v3)
				return conj(eq({foo=v2, bar=456},
								{foo=123, bar=v3}),
							eq(v1, {v2, v3}))
			end) end) end),
		{123, 456})

	assert_one_result(
			cf(function(v1) return
			cf(function(v2) return
			cf(function(v3)
				return conj(
							eq(v1, {v2, v3}),
							eq({foo=v2, bar=v3},
								{foo=123, bar=456}))
			end) end) end),
		{123, 456})

	assert_one_result(
			cf(function(v1) return
			cf(function(v2) return
			cf(function(v3) return
			cf(function(v4)
				return conj(conj(
							eq(v2, {v3, 456}),
							eq(v2, {123, v4})
							),
							eq(v1, {v2, v3, v4}))
			end) end) end) end),
		{{123, 456}, 123, 456})



	assert_one_result(
			cf(function(v1) return
			cf(function(v2) return
			cf(function(v3) return
			cf(function(v4)
				return conj(conj(
							-- single variables on the rhs of relation
							eq({v3, 456}, v2),
							eq({123, v4}, v2)
							),
							eq(v1, {v2, v3, v4}))
			end) end) end) end),
		{{123, 456}, 123, 456})

	assert_one_result(
			cf(function(v1) return
			cf(function(v2) return
			cf(function(v3)
				return conj(
							eq({v2, v3}, {123, 456}),
							eq(v1, {v2, v3})
							)
			end) end) end),
		{123, 456})

	assert_one_result(
			cf(function(v1) return
			cf(function(v2) return
			cf(function(v3)
				return conj(
							eq(v1, {v2, v3}),
							eq(v1, {123, 456})
							)
			end) end) end),
		{123, 456})

	assert_one_result(
			cf(function(v1) return
			cf(function(v2) return
			cf(function(v3) return
			cf(function(v4)
				return conj(conj(
							-- single variables on the rhs of relation
							eq({v3, {456}}, v2),
							eq({123, {v4}}, v2)
							),
							eq(v1, {v2, v3, v4}))
			end) end) end) end),
		{{123, {456}}, 123, 456})


	assert_one_result(
			cf(function(v1) return
			cf(function(v2) return
			cf(function(v3) return
			cf(function(v4)
				return conj(conj(
							-- single variables on the rhs of relation
							eq({k1= v2, k2= "second value"}, v3),
							eq(v3, {k1= "first value", k2= v4})
							),
							eq(v1, {v2, v4}))
			end) end) end) end),
		{"first value", "second value"})
end


function main()
	local failures = {}
	for k,v in pairs(TestLogic) do
		print("starting "..k.."...")
		local status, err = pcall(v)
		if not status then
			failures[k] = err
		end
		print("      ...finished "..k..".")
	end

	local n_failures = table_length(failures)
	print(table_length(TestLogic).." total tests, "..assert_count.." assertions made.")
	print(table_length(TestLogic) - n_failures .." Successes.")

	if n_failures == 0 then
		return 0
	else
		print(n_failures .. " Failures:")
		for k,v in pairs(failures) do
			print(k .. " : ", v)
		end
		return 1
	end
end

main()