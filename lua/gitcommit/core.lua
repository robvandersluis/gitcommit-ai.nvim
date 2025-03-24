-- lua/gitcommit/core.lua
local config = require("gitcommit.config")
local curl = require("plenary.curl")
local git = require("gitcommit.git")

local M = {}

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

	vim.defer_fn(function()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end, 3000)
end

function M.show_commit_ui(message, is_staged)
	local buf = vim.api.nvim_create_buf(false, true)
	local lines = {}

	table.insert(lines, " 📌 Generated commit message:")
	table.insert(lines, "")

	local mlines = vim.split(message, "\n")
	for _, line in ipairs(mlines) do
		table.insert(lines, "  " .. line)
	end

	table.insert(lines, "")
	table.insert(
		lines,
		"─────────────────────────────────────────────"
	)
	table.insert(lines, " [e] Edit    [c] Commit    [q] Quit ")

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	-- Window layout
	local width = math.floor(vim.o.columns * 0.6)
	local height = #lines + 2
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "cursor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = "rounded",
	})

	-- Styling via extmarks
	local ns = vim.api.nvim_create_namespace("commit-ui")
	vim.api.nvim_buf_add_highlight(buf, ns, "Title", 0, 0, -1)
	vim.api.nvim_buf_add_highlight(buf, ns, "Comment", #lines - 2, 0, -1)

	-- Highlight key shortcuts
	local keyline = #lines - 1
	local keymap = {
		{ "[e]", "Keyword" },
		{ "Edit   ", "Normal" },
		{ "[c]", "Keyword" },
		{ "Commit   ", "Normal" },
		{ "[q]", "Keyword" },
		{ "Quit", "Normal" },
	}

	local col_pos = 1
	for _, pair in ipairs(keymap) do
		local text, hl = unpack(pair)
		local start_col = col_pos
		local end_col = start_col + #text
		vim.api.nvim_buf_add_highlight(buf, ns, hl, keyline, start_col - 1, end_col)
		col_pos = end_col + 1
	end

	-- Keymaps
	vim.keymap.set("n", "q", function()
		if is_staged then
			vim.fn.system("git reset HEAD")
		end
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
	vim.fn.writefile(vim.split(msg, "\n"), tmpfile)
	local out = vim.fn.system({ "git", "commit", "-F", tmpfile })
	vim.notify(out, vim.log.levels.INFO)
	M.prompt_push()
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
	vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), tmpfile)

	local out = vim.fn.system({ "git", "commit", "-F", tmpfile })
	vim.notify(out, vim.log.levels.INFO)

	vim.api.nvim_buf_delete(buf, { force = true })

	M.prompt_push()
end

function M.prompt_push()
	if git.can_push() then
		local target = git.get_tracking_branch() or "remote"
		local prompt_title = "Push to tracking branch [" .. target .. "]?"

		vim.schedule(function()
			vim.ui.select({ "Yes", "No" }, { prompt = prompt_title }, function(choice)
				if choice == "Yes" then
					local push_out = vim.fn.system({ "git", "push" })
					vim.notify(push_out, vim.log.levels.INFO)
				else
					vim.notify("🚀 Push skipped.", vim.log.levels.INFO)
				end
			end)
		end)
	end
end

function prompt_stage()
	local files = vim.fn.systemlist("git diff --name-only")
	if #files == 0 then
		vim.notify("✅ Nothing to stage.", vim.log.levels.INFO)
		return
	end

	vim.ui.select(files, { prompt = "Stage which file?" }, function(choice)
		if choice then
			local result = vim.fn.system({ "git", "add", choice })
			vim.notify("📦 Staged: " .. choice, vim.log.levels.INFO)
		end
	end)
end

function M.check_git_repo()
	local filepath = vim.api.nvim_buf_get_name(0)
	local git_root = git.find_git_root(filepath)
	if not git_root then
		return false, "🚫 Not a Git repository."
	end
	vim.fn.chdir(git_root)

	if git.can_fetch() then
		vim.fn.system({ "git", "fetch" })
	end

	local status = vim.fn.system("git status --porcelain -b")
	if status:find("%[behind") then
		return false, "⚠️  You are behind the remote branch! Please run git pull first."
	end

	if not config.options.stage_all then
		if not git.has_staged_changes() then
			--TODO: Add a staging UI
			return false, " 🚫 Nothing staged. Stage something first."
		end
	end
	local lines = {}
	for line in status:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	if #lines == 1 then
		return false, " ✅ No changes to commit."
	end
	-- print("🔍 File Changes :")
	-- for i = 2, #lines do
	-- 	print("  " .. lines[i])
	-- end
	--
	return true
end

function M.run()
	-- check if commit is possible
	local ok, err = M.check_git_repo()
	if not ok then
		show_floating_message(err)
		return
	end

	local is_staged = false
	if config.options.stage_all then
		vim.fn.system("git add -A")
		is_staged = true
	end

	local diff = vim.fn.system("git diff --cached")
	if diff == "" then
		show_floating_message("❌ No changes to commit.")
		return
	end

	M.generate_commit_message(diff, function(msg)
		M.show_commit_ui(msg, is_staged)
	end)
end

return M
