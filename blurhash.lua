local bit = require("bit")

local blurhash = {}

local alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~"
assert(#alphabet == 83)

local digit_list = {}
for i = 1, #alphabet do
	digit_list[i - 1] = alphabet:sub(i, i)
end

local digit_map = {}
for i = 0, #alphabet - 1 do
	digit_map[digit_list[i]] = i
end

local function decode83(str)
	local value = 0
	for i = 1, #str do
		local c = str:sub(i, i)
		local digit = digit_map[c]
		value = value * 83 + digit
	end
	return value
end

local function encode83(n, length)
	local result = {}
	for i = 1, length do
		local digit = (math.floor(n) / math.pow(83, length - i)) % 83
		result[#result + 1] = digit_list[math.floor(digit)]
	end
	return table.concat(result)
end

local function to_linear(value)
	local v = value / 255
	if v <= 0.04045 then
		return v / 12.92
	end
	return math.pow((v + 0.055) / 1.055, 2.4)
end

local function to_srgb(value)
	local v = math.max(0, math.min(1, value))
	if v <= 0.0031308 then
		return math.floor(v * 12.92 * 255 + 0.5)
	end
	return math.floor((1.055 * math.pow(v, 1 / 2.4) - 0.055) * 255 + 0.5)
end

local function sign(n)
	return n < 0 and -1 or 1
end

local function sign_pow(val, exp)
	return sign(val) * math.pow(math.abs(val), exp)
end

local function decode_dc(value)
	local r = bit.rshift(value, 16)
	local g = bit.band(bit.rshift(value, 8), 255)
	local b = bit.band(value, 255)
	return {to_linear(r), to_linear(g), to_linear(b)}
end

local function decode_ac(value, max_value)
	local r = math.floor(value / (19 * 19))
	local g = math.floor(value / 19) % 19
	local b = value % 19

	return {
		sign_pow((r - 9) / 9, 2) * max_value,
		sign_pow((g - 9) / 9, 2) * max_value,
		sign_pow((b - 9) / 9, 2) * max_value
	}
end

function blurhash.render(colors, size_x, size_y, width, height)
	local pixels = {}
	for y = 0, height - 1 do
		local pixel_row = {}
		for x = 0, width - 1 do
			local pixel = {0, 0, 0}

			for j = 0, size_y - 1 do
				for i = 0, size_x - 1 do
					local basis = math.cos(math.pi * x * i / width) * math.cos(math.pi * y * j / height)
					local color = colors[i + j * size_x]
					pixel[1] = pixel[1] + color[1] * basis
					pixel[2] = pixel[2] + color[2] * basis
					pixel[3] = pixel[3] + color[3] * basis
				end
			end
			pixel_row[x] = {
				to_srgb(pixel[1]),
				to_srgb(pixel[2]),
				to_srgb(pixel[3])
			}
		end
		pixels[y] = pixel_row
	end
	return pixels
end

function blurhash.decode(blur_hash, punch)
	punch = punch or 1

	if #blur_hash < 6 then
		error("BlurHash must be at least 6 characters long.")
	end

	local size_info = decode83(blur_hash:sub(1, 1))
	local size_y = math.floor(size_info / 9) + 1
	local size_x = (size_info % 9) + 1

	local quant_max_value = decode83(blur_hash:sub(2, 2))
	local max_value = ((quant_max_value + 1) / 166) * punch

	if #blur_hash ~= 4 + 2 * size_x * size_y then
		error("Invalid BlurHash length.")
	end

	local colors = {}
	colors[0] = decode_dc(decode83(blur_hash:sub(3, 6)))

	for i = 1, size_x * size_y - 1 do
		local value = decode83(blur_hash:sub(5 + i * 2, 6 + i * 2))
		colors[i] = decode_ac(value, max_value * punch)
	end

	return size_x, size_y, colors
end

function blurhash.encode(image, width, height, components_x, components_y)
	if components_x < 1 or components_x > 9 or components_y < 1 or components_y > 9 then
		error("x and y component counts must be between 1 and 9 inclusive.")
	end

	local image_linear = {}
	for y = 0, height - 1 do
		local image_linear_line = {}
		for x = 0, width - 1 do
			image_linear_line[x] = {
				to_linear(image[y][x][1]),
				to_linear(image[y][x][2]),
				to_linear(image[y][x][3])
			}
		end
		image_linear[y] = image_linear_line
	end

	local components = {}
	local max_ac_component = 0
	for j = 0, components_y - 1 do
		for i = 0, components_x - 1 do
			local norm_factor = (i == 0 and j == 0) and 1 or 2
			local component = {0, 0, 0}
			for y = 0, height - 1 do
				for x = 0, width - 1 do
					local basis = norm_factor * math.cos(math.pi * i * x / width) * math.cos(math.pi * j * y / height)
					component[1] = component[1] + basis * image_linear[y][x][1]
					component[2] = component[2] + basis * image_linear[y][x][2]
					component[3] = component[3] + basis * image_linear[y][x][3]
				end
			end

			component[1] = component[1] / (width * height)
			component[2] = component[2] / (width * height)
			component[3] = component[3] / (width * height)
			components[#components + 1] = component

			if not (i == 0 and j == 0) then
				max_ac_component = math.max(max_ac_component, math.abs(component[1]), math.abs(component[2]), math.abs(component[3]))
			end
		end
	end

	local dc_value = bit.lshift(to_srgb(components[1][1]), 16) +
					 bit.lshift(to_srgb(components[1][2]), 8) +
								to_srgb(components[1][3])

	local quant_max_ac_component = math.floor(math.max(0, math.min(82, math.floor(max_ac_component * 166 - 0.5))))
	local ac_component_norm_factor = (quant_max_ac_component + 1) / 166

	local ac_values = {}
	for i = 2, #components do
		local component = components[i]
		local r, g, b = unpack(component)
		ac_values[#ac_values + 1] = (
			math.floor(math.max(0, math.min(18, math.floor(sign_pow(r / ac_component_norm_factor, 0.5) * 9 + 9.5)))) * 19 * 19 +
			math.floor(math.max(0, math.min(18, math.floor(sign_pow(g / ac_component_norm_factor, 0.5) * 9 + 9.5)))) * 19 +
			math.floor(math.max(0, math.min(18, math.floor(sign_pow(b / ac_component_norm_factor, 0.5) * 9 + 9.5))))
		)
	end

	local blur_hash = ""
	blur_hash = blur_hash .. encode83((components_x - 1) + (components_y - 1) * 9, 1)
	blur_hash = blur_hash .. encode83(quant_max_ac_component, 1)
	blur_hash = blur_hash .. encode83(dc_value, 4)
	for _, ac_value in ipairs(ac_values) do
		blur_hash = blur_hash .. encode83(ac_value, 2)
	end

	return blur_hash
end

return blurhash
