-- lua/gitcommit /core.lua
local config = require("gitcommit.config")
local curl = require("plenary.curl")

local M = {}

local function run_command(cmd)
	return vim.fn.system(cmd)
end

function M.generate_commit_message(diff, callback)
	local api_key = config.options.api_key or os.getenv("OPENAI_API_KEY")

	if not api_key then
		callback("❌ Geen OPENAI_API_KEY gevonden in environment en settings.api_key")
		return
	end
	local payload = {
		model = config.options.model,
		messages = {
			{ role = "system", content = config.options.system_prompt },
			{ role = "user", content = config.options.user_prompt .. "\n\n" .. diff },
		},
		temperature = config.options.temperature,
	}

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
			print("❌ Ongeldig antwoord van OpenAI API")
		end
	else
		print("❌ HTTP fout: " .. tostring(response.status))
	end
end

function M.check_git_status()
	-- if vim.fn.isdirectory(".git") == 0 then
	-- 	print("🚫 Geen Git-repository gevonden.")
	-- 	return false
	-- end

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

function M.run()
	if not M.check_git_status() then
		return
	end
	local diff = run_command("git diff HEAD")
	M.generate_commit_message(diff, function(msg)
		--print("\n📦 Commit message:\n" .. msg)

		local tmpfile = vim.fn.tempname()
		-- Open commit message in new buffer
		local buf = vim.api.nvim_create_buf(true, false) -- listed, not scratch
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.split(msg, "\n"))
		vim.api.nvim_buf_set_name(buf, tmpfile)
		vim.bo[buf].filetype = "gitcommit"
		vim.bo[buf].bufhidden = "wipe"
		--vim.bo[buf].buftype = "nofile"
		-- open buffer in new window
		vim.api.nvim_set_current_buf(buf)

		-- Auto-command: save and close buffer
		vim.api.nvim_create_autocmd("BufWritePost", {
			buffer = buf,
			once = true,
			callback = function()
				-- Stage alles voor commit
				vim.fn.system({ "git", "add", "-A" })

				vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), tmpfile)

				-- Commit message
				local out = vim.fn.system({ "git", "commit", "-F", tmpfile })
				vim.notify(out, vim.log.levels.INFO)

				-- Close buffer
				vim.api.nvim_buf_delete(buf, { force = true })
			end,
		})
	end)
end

return M
