-- lua/gitcommit/core.lua
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
	local Job = require("plenary.job")
	local payload = vim.fn.json_encode({
		model = config.options.model,
		messages = {
			{ role = "system", content = config.options.system_prompt },
			{ role = "user", content = config.options.user_prompt .. "\n\n" .. diff },
		},
		temperature = config.options.temperature,
	})

	Job
		:new({
			command = "curl",
			args = {
				"-s",
				"-X",
				"POST",
				"-H",
				"Content-Type: application/json",
				"-H",
				"Authorization: Bearer " .. os.getenv("OPENAI_API_KEY"),
				"--data",
				payload,
				"https://api.openai.com/v1/chat/completions",
			},
			on_exit = function(j, return_val)
				if return_val == 0 then
					local ok, decoded = pcall(vim.fn.json_decode, table.concat(j:result(), "\n"))
					if ok and decoded and decoded.choices and decoded.choices[1] then
						callback(decoded.choices[1].message.content)
					else
						callback("Auto-commit (OpenAI gaf geen geldig antwoord)")
					end
				else
					callback("Auto-commit (curl fout)")
				end
			end,
		})
		:start()
end

function M.run()
	if not M.check_git_status() then
		return
	end
	local diff = run_command("git diff")
	M.generate_commit_message(diff, function(msg)
		print("\n📦 Commit message:\n" .. msg)
	end)
end

return M
