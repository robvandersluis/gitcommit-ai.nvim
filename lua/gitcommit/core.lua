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
		print("❌ OPENAI_API_KEY not found or empty.")
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
			print("❌ Unexpected OpenAI API	response:")
		end
	else
		print("❌ HTTP error: " .. tostring(response.status))
	end
end

function M.check_git_status()
	if vim.fn.isdirectory(".git") == 0 then
		return false, "🚫 No Git repository found."
	end

	local status = run_command("git status --porcelain -b")
	if status:find("%[behind") then
		return false, "⚠️  You are behind the remote branch! Please run git pull first."
	end

	local untracked = run_command("git ls-files --others --exclude-standard")
	if #untracked:gsub("%s+", "") > 0 then
		local message = "⚠️  Untracked files found:\n"
		for line in untracked:gmatch("[^\r\n]+") do
			message = message .. "  " .. line .. "\n"
		end
		message = message .. "\n⚠️  Add them with `git add`."
		return false, message
	end

	local lines = {}
	for line in status:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	if #lines == 1 then
		return false, "✅ No changes to commit."
	end
	-- print("🔍 Gewijzigde bestanden:")
	-- for i = 2, #lines do
	-- 	print("  " .. lines[i])
	-- end
	--
	return true
end

local function show_floating_message(message)
	local buf = vim.api.nvim_create_buf(false, true) -- [listed=false, scratch=true]
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(message, "\n"))

	local width = math.max(30, #message + 4)
	local height = 5
	local opts = {
		relative = "editor",
		width = width,
		height = height,
		row = (vim.o.lines - height) / 2,
		col = (vim.o.columns - width) / 2,
		style = "minimal",
		border = "rounded",
	}

	local win = vim.api.nvim_open_win(buf, false, opts)

	-- Sluit automatisch na 2 seconden
	vim.defer_fn(function()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end, 2000)
end

function M.show_commit_ui(message)
	local buf = vim.api.nvim_create_buf(false, true)
	local lines = {}
	table.insert(lines, "👃 Generated commit message:")

	local mlines = vim.split(message, "\n")
	table.insert(lines, "")
	for _, line in ipairs(mlines) do
		table.insert(lines, " " .. line)
	end
	table.insert(lines, " ───────────────────────────── ")
	table.insert(lines, " [e] Edit  [c] Commit  [q] Quit ")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	local width = math.floor(vim.o.columns * 0.6)
	local height = math.max(20, #lines + 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = (vim.o.lines - height) / 2,
		style = "minimal",
		border = "rounded",
	})

	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf, silent = true })

	vim.keymap.set("n", "c", function()
		vim.api.nvim_win_close(win, true)
		M.commit_with_message(message)
	end, { buffer = buf, silent = true })

	vim.keymap.set("n", "e", function()
		vim.api.nvim_win_close(win, true)
		M.open_commit_buffer(message)
	end, { buffer = buf, silent = true })
end

function M.commit_with_message(msg)
	local tmpfile = vim.fn.tempname()
	vim.fn.system({ "git", "add", "-A" })
	vim.fn.writefile(vim.split(msg, "\n"), tmpfile)
	local out = vim.fn.system({ "git", "commit", "-F", tmpfile })
	vim.notify(out, vim.log.levels.INFO)
	M.prompt_push()
end
function M.run()
	local ok, err = M.check_git_status()
	if not ok then
		show_floating_message(err)
		return
	end

	local diff = run_command("git diff HEAD")
	M.generate_commit_message(diff, function(msg)
		M.show_commit_ui(msg)
	end)
end

function M.open_commit_buffer(msg)
	local tmpfile = vim.fn.tempname()
	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.split(msg, "\n"))
	vim.api.nvim_buf_set_name(buf, tmpfile)
	vim.bo[buf].filetype = "gitcommit"
	vim.bo[buf].bufhidden = "wipe"
	vim.api.nvim_set_current_buf(buf)

	vim.keymap.set("n", "q", function()
		vim.notify("❌ Commit canceled.", vim.log.levels.WARN)
		vim.api.nvim_buf_delete(buf, { force = true })
	end, { buffer = buf, silent = true })

	vim.api.nvim_create_autocmd("BufWritePost", {
		buffer = buf,
		once = true,
		callback = function()
			M.commit_from_buffer(buf, tmpfile)
		end,
	})
end

function M.commit_from_buffer(buf, tmpfile)
	vim.fn.system({ "git", "add", "-A" })
	vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), tmpfile)

	local out = vim.fn.system({ "git", "commit", "-F", tmpfile })
	vim.notify(out, vim.log.levels.INFO)

	vim.api.nvim_buf_delete(buf, { force = true })

	M.prompt_push()
end

function M.prompt_push()
	vim.schedule(function()
		vim.ui.select({ "Yes", "No" }, { prompt = "Push to Remote?" }, function(choice)
			if choice == "Yes" then
				local push_out = vim.fn.system({ "git", "push" })
				vim.notify(push_out, vim.log.levels.INFO)
			else
				vim.notify("🚀 Push skipped.", vim.log.levels.INFO)
			end
		end)
	end)
end
return M
