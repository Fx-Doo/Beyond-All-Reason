-- Deterministic PRNG shared by synced and unsynced code, and by the offline tools.
--
-- The engine's Lua numbers are 32-bit floats (24-bit mantissa), not doubles: a Park-Miller multiplication
-- (state * 16807 reaches 2^45) is silently rounded there, which gave other sequences in game than offline and a poor
-- generator. This one is a Wichmann-Hill style generator whose every intermediate value stays below 2^24, so each
-- operation is exact in float32 and in double alike: the same seed gives the same sequence everywhere.
--   three small linear congruential generators (moduli 30269, 30307, 30323), combined into a 24-bit integer;
--   the output is that integer / 2^24 (a power of two, exact).

-- Usage:
--   local rng = Prng.new(seed, salt)
--   rng:next()            float in [0, 1)
--   rng:range(a, b)       float in [a, b)
--   rng:int(a, b)         integer in [a, b]
--   rng:chance(p)         true with probability p
--   rng:pick(list)        uniformly chosen element of a list
--   rng:weighted(entries) value of a { value, weight } pair, chosen proportionally to its weight

local floor = math.floor

-- ===========================================================================================================
-- Generator constants
-- ===========================================================================================================

-- Moduli of the three component generators (primes close to 2^15, the classic Wichmann-Hill choice).
local MODULUS_X, MODULUS_Y, MODULUS_Z = 30269, 30307, 30323

local Prng = {}
Prng.__index = Prng

-- ===========================================================================================================
-- Helpers
-- ===========================================================================================================

-- Remainder of value / modulus, computed so that float32 rounding cannot push it out of [0, modulus).
-- Params: value (non-negative integer below 2^24), modulus (positive integer).
-- Returns: integer in [0, modulus).
local function modExact(value, modulus)
	local remainder = value % modulus
	if remainder < 0 then
		remainder = remainder + modulus
	elseif remainder >= modulus then
		remainder = remainder - modulus
	end
	return remainder
end

-- ===========================================================================================================
-- Construction
-- ===========================================================================================================

-- Creates a generator whose state is derived from a seed, then warmed up.
-- Params: seed (any non-negative integer the engine can hold exactly: below 2^24 = 16777216; larger ones are
--         already rounded by the engine before they get here), salt (optional small integer that re-rolls the
--         sequence: the chain attempt number).
-- Returns: a new Prng object.
function Prng.new(seed, salt)
	seed = floor(tonumber(seed) or 1)
	if seed < 0 then
		seed = -seed
	end

	-- Split the seed into three "digits" in mixed radix (modulus - 1 each), one per component generator.
	-- Each component state must lie in [1, modulus - 1], hence the radix of modulus - 1 and the + 1 below.
	local remX = modExact(seed, MODULUS_X - 1)
	local quotX = (seed - remX) / (MODULUS_X - 1) -- exactly divisible
	local remY = modExact(quotX, MODULUS_Y - 1)
	local quotY = (quotX - remY) / (MODULUS_Y - 1)
	-- 977 spreads consecutive salts apart in the third digit
	local remZ = modExact(quotY + (salt or 0) * 977, MODULUS_Z - 1)

	local self = setmetatable({ x = remX + 1, y = remY + 1, z = remZ + 1 }, Prng)

	-- consecutive seeds start with nearly identical states; scramble them
	for _ = 1, 12 do
		self:next()
	end
	return self
end

-- ===========================================================================================================
-- Drawing numbers
-- ===========================================================================================================

-- Advances the three component generators and combines them into one 24-bit value.
-- Returns: float in [0, 1).
function Prng:next()
	-- 171, 172 and 170 are the Wichmann-Hill multipliers; each product stays below 2^23
	local stateX = (171 * self.x) % MODULUS_X
	local stateY = (172 * self.y) % MODULUS_Y
	local stateZ = (170 * self.z) % MODULUS_Z
	self.x = stateX
	self.y = stateY
	self.z = stateZ

	-- two 12-bit halves (4096 = 2^12), each a mix of the components, glued into a 24-bit integer
	local lowBits = (stateX + 2 * stateZ) % 4096
	local highBits = (stateY + 5 * stateX) % 4096
	return (lowBits + 4096 * highBits) / 16777216 -- 16777216 = 2^24
end

-- Params: a, b (bounds, a <= b).
-- Returns: float in [a, b).
function Prng:range(a, b)
	return a + (b - a) * self:next()
end

-- Params: a, b (integer bounds, a <= b).
-- Returns: integer in [a, b], both ends included.
function Prng:int(a, b)
	return a + floor(self:next() * (b - a + 1))
end

-- Params: p (probability in [0, 1]).
-- Returns: true with probability p, false otherwise.
function Prng:chance(p)
	return self:next() < p
end

-- Params: list (non-empty array).
-- Returns: one uniformly chosen element.
function Prng:pick(list)
	return list[self:int(1, #list)]
end

-- Params: entries (array of { value, weight } pairs, weights non-negative).
-- Returns: the value of one pair, chosen with probability proportional to its weight.
function Prng:weighted(entries)
	local totalWeight = 0
	for i = 1, #entries do
		totalWeight = totalWeight + entries[i][2]
	end

	-- walk through the entries, spending the random amount until it runs out
	local remaining = self:next() * totalWeight
	for i = 1, #entries do
		remaining = remaining - entries[i][2]
		if remaining < 0 then
			return entries[i][1]
		end
	end
	-- only reachable through rounding: fall back to the last entry
	return entries[#entries][1]
end

return Prng
