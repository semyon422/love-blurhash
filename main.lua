local blurhash = require("blurhash")

local function encode_image(path, size_x, size_y)
	local blur_hash_path = path .. ".blurhash" .. size_x .. size_y
	local file = io.open(blur_hash_path)
	if file then
		local blur_hash = file:read("*all")
		file:close()
		return blur_hash
	end

	local imageData = love.image.newImageData(path)

	local pixels = {}
	for y = 0, imageData:getHeight() - 1 do
		local row = {}
		pixels[y] = row
		for x = 0, imageData:getWidth() - 1 do
			local r, g, b = imageData:getPixel(x, y)
			row[x] = {r * 255, g * 255, b * 255}
		end
	end

	local blur_hash = blurhash.encode(pixels, imageData:getWidth(), imageData:getHeight(), size_x, size_y)

	file = io.open(blur_hash_path, "w")
	file:write(blur_hash)
	file:close()

	return blur_hash
end

local encoded = encode_image("image.jpg", 9, 5)

local shader
local pixelImageData
local pixelImage
local size_x, size_y, colors

function love.load()
	shader = love.graphics.newShader("blurhash.glsl")
	pixelImageData = love.image.newImageData(1, 1)
	pixelImageData:setPixel(0, 0, 1, 1, 1, 1)
	pixelImage = love.graphics.newImage(pixelImageData)

	love.window.setMode(
		1920,
		1080,
		{
			fullscreen = true,
			vsync = 0
		}
	)
end

function love.update()
	size_x, size_y, colors = blurhash.decode(encoded)
	shader:send("size_x", size_x)
	shader:send("size_y", size_y)
	shader:send("colors", colors[0], unpack(colors))
end

local function draw_shader()
	local screen_width, screen_height = love.graphics.getDimensions()

	shader:send("screen_width", screen_width)
	shader:send("screen_height", screen_height)

	love.graphics.setColor(1, 1, 1)
	love.graphics.setShader(shader)

	love.graphics.draw(pixelImage, 0, 0, 0, screen_width, screen_height)

	love.graphics.setShader()
end

local function draw_point()
	local screen_width, screen_height = love.graphics.getDimensions()

	local pixels = blurhash.render(colors, size_x, size_y, screen_width, screen_height)
	for x = 0, screen_width - 1 do
		for y = 0, screen_height - 1 do
			local r, g, b = unpack(pixels[y][x])
			love.graphics.setColor(r / 255, g / 255, b / 255)
			love.graphics.points(x, y)
		end
	end
end

function love.draw()
	draw_shader()
	-- draw_point()

	love.graphics.print(love.timer.getFPS())
end