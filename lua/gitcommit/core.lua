-- lua/gitcommit /core.lua
local curl = require("plenary.curl")
local config = require("gitcommit.config")

local M = {}

local function run_command(cmd)
	return vim.fn.system(cmd)
end

function M.check_git_status()
	if vim.fn.isdirectory(".git") == 0 then
		print("🚫 Geen Git-repository gevonden.")
		return false
	end

	local status = run_command("git status --porcelain -b")
	if status:find("%[behind") then
		print("⚠️  Je loopt achter op de remote branch! Doe eerst een git pull.")
		return false
	end

	local untracked = run_command("git ls-files --others --exclude-standard")
	if #untracked:gsub("%s+", "") > 0 then
		print("⚠️  Ongetrackte bestanden gevonden:")
		for line in untracked:gmatch("[^\r\n]+") do
			print("  " .. line)
		end
		print("⚠️  Voeg ze toe met `git add`.")
		return false
	end

	local lines = {}
	for line in status:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	if #lines == 1 then
		print("✅ Geen wijzigingen om te committen.")
		return false
	end

	print("🔍 Gewijzigde bestanden:")
	for i = 2, #lines do
		print("  " .. lines[i])
	end

	return true
end

function M.generate_commit_message(diff, callback)
	local api_key = config.options.api_key

	if not api_key then
		callback("❌ Geen OPENAI_API_KEY gevonden in environment")
		return
	end
	local payload = vim.fn.json_encode({
		model = config.options.model,
		messages = {
			{ role = "system", content = config.options.system_prompt },
			{ role = "user", content = config.options.user_prompt .. "\n\n" .. diff },
		},
		temperature = config.options.temperature,
	})

	callback(" debug payload: " .. payload)
	local response = curl.post("https://api.openai.com/v1/chat/completions", {
		headers = {
			["Authorization"] = "Bearer " .. api_key,
			["Content-Type"] = "application/json",
		},
		body = vim.fn.json_encode(payload),
	})

	if response.status == 200 then
		local ok, decoded = pcall(vim.fn.json_decode, response.body)
		if ok and decoded and decoded.choices and decoded.choices[1] then
			callback(decoded.choices[1].message.content)
		else
			callback("❌ Ongeldig antwoord van OpenAI API")
		end
	else
		callback("❌ HTTP fout: " .. tostring(response.status))
	end
end

function M.run()
	if not M.check_git_status() then
		return
	end
	local diff = run_command("git diff HEAD")
	M.generate_commit_message(diff, function(msg)
		print("\n📦 Commit message:\n" .. msg)
	end)
end

return M
