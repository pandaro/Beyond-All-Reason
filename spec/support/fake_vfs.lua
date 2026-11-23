---@diagnostic disable: param-type-mismatch, assign-type-mismatch, unnecessary-if

-- VFS.Pack* and VFS.Unpack* as Recoil implements them: little-endian, F32 as IEEE 754 single precision rounded to
-- nearest even, packing stops at the first value that is not a number and returns nothing when none is, and
-- unpacking returns nothing for a position below 1 or not below the string length. For specs; Lua numbers stay doubles.
local function toBytes(value, size)
	value = math.floor(value) % 2 ^ (8 * size)
	local bytes = {}
	for i = 1, size do
		local byte = value % 256
		bytes[i] = string.char(byte)
		value = (value - byte) / 256
	end
	return table.concat(bytes)
end

local function fromBytes(text, position, size)
	local value = 0
	for i = size, 1, -1 do
		value = value * 256 + string.byte(text, position + i - 1)
	end
	return value
end

local function roundEven(value)
	local floor = math.floor(value)
	local fraction = value - floor
	if fraction > 0.5 or (fraction == 0.5 and floor % 2 == 1) then
		return floor + 1
	end
	return floor
end

local function encodeF32(value)
	local sign = 0
	if value < 0 or (value == 0 and 1 / value < 0) then
		sign = 1
		value = -value
	end
	local exponent, mantissa
	if value ~= value then
		exponent, mantissa = 255, 2 ^ 22
	elseif value == math.huge then
		exponent, mantissa = 255, 0
	elseif value == 0 then
		exponent, mantissa = 0, 0
	else
		local fraction, power = math.frexp(value)
		exponent = power + 126
		if exponent <= 0 then
			exponent = 0
			mantissa = roundEven(value * 2 ^ 149)
			if mantissa >= 2 ^ 23 then
				exponent, mantissa = 1, mantissa - 2 ^ 23
			end
		else
			mantissa = roundEven((fraction * 2 - 1) * 2 ^ 23)
			if mantissa == 2 ^ 23 then
				exponent, mantissa = exponent + 1, 0
			end
			if exponent >= 255 then
				exponent, mantissa = 255, 0
			end
		end
	end
	return toBytes(sign * 2 ^ 31 + exponent * 2 ^ 23 + mantissa, 4)
end

local function decodeF32(text, position)
	local bits = fromBytes(text, position, 4)
	local sign = bits >= 2 ^ 31 and -1 or 1
	bits = bits % 2 ^ 31
	local exponent = math.floor(bits / 2 ^ 23)
	local mantissa = bits % 2 ^ 23
	if exponent == 255 then
		return mantissa == 0 and sign * math.huge or 0 / 0
	elseif exponent == 0 then
		return sign * mantissa * 2 ^ -149
	end
	return sign * (1 + mantissa / 2 ^ 23) * 2 ^ (exponent - 127)
end

local function packer(encode)
	return function(first, ...)
		local values = type(first) == "table" and first or { first, ... }
		local pieces = {}
		local i = 1
		while type(values[i]) == "number" do
			pieces[i] = encode(values[i])
			i = i + 1
		end
		if i == 1 then
			return nil
		end
		return table.concat(pieces)
	end
end

local function unpacker(size, decode)
	return function(text, position, count)
		local length = #text
		local offset = 0
		if position ~= nil then
			if position < 1 or position >= length then
				return
			end
			offset = position - 1
		end
		local available = length - offset
		if available < size then
			return
		end
		if count == nil then
			return decode(text, offset + 1)
		end
		local maxCount = math.floor(available / size)
		if count < 0 or count > maxCount then
			count = maxCount
		end
		local values = { n = count }
		for i = 1, count do
			values[i] = decode(text, offset + 1 + (i - 1) * size)
		end
		return values
	end
end

local function unsigned(size)
	return function(text, position)
		return fromBytes(text, position, size)
	end
end

local function decodeS32(text, position)
	local value = fromBytes(text, position, 4)
	if value >= 2 ^ 31 then
		return value - 2 ^ 32
	end
	return value
end

--- A VFS table whose Include runs files in `env` unless given another environment
--
-- @param env table
-- @return table
local function newVFS(env)
	return {
		PackU8 = packer(function(value)
			return toBytes(value, 1)
		end),
		PackU16 = packer(function(value)
			return toBytes(value, 2)
		end),
		PackU32 = packer(function(value)
			return toBytes(value, 4)
		end),
		PackS32 = packer(function(value)
			return toBytes(value, 4)
		end),
		PackF32 = packer(encodeF32),
		UnpackU8 = unpacker(1, unsigned(1)),
		UnpackU16 = unpacker(2, unsigned(2)),
		UnpackU32 = unpacker(4, unsigned(4)),
		UnpackS32 = unpacker(4, decodeS32),
		UnpackF32 = unpacker(4, decodeF32),
		Include = function(path, includeEnv)
			local chunk = assert(loadfile(path))
			setfenv(chunk, includeEnv or env)
			return chunk()
		end,
	}
end

return newVFS
