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

function M.commit_from_lines(lines, reset_on_cancel)
	local trimmed = vim.tbl_filter(function(line)
		return line:match("%S") -- check for any non-whitespace
	end, lines)

	if #trimmed == 0 then
		vim.notify("❌ Commit aborted: message is empty", vim.log.levels.WARN)
		if reset_on_cancel then
			vim.fn.system("git reset HEAD")
		end
		return
	end

	local tmpfile = vim.fn.tempname()
	vim.fn.writefile(lines, tmpfile)
	local out = vim.fn.system({ "git", "commit", "-F", tmpfile })

	os.remove(tmpfile)
	if vim.v.shell_error ~= 0 then
		vim.notify("⚠️ Git commit failed:\n" .. out, vim.log.levels.ERROR)
		if reset_on_cancel then
			vim.fn.system("git reset HEAD")
		end
	else
		vim.notify(out, vim.log.levels.INFO)
		if config.options.prompt_after_commit then
			M.prompt_push()
		end
	end
end

function M.commit_with_message(msg, reset_on_cancel)
	M.commit_from_lines(vim.split(msg, "\n"), reset_on_cancel)
end

function M.commit_from_buffer(bufnr, reset_on_cancel)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	vim.api.nvim_buf_delete(bufnr, { force = true })
	M.commit_from_lines(lines, reset_on_cancel)
end

function M.open_commit_buffer(msg, reset_on_cancel)
	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.split(msg, "\n"))
	local tmpfile = vim.fn.tempname()
	vim.api.nvim_buf_set_name(buf, tmpfile)
	vim.bo[buf].filetype = "gitcommit"
	vim.bo[buf].bufhidden = "wipe"
	vim.api.nvim_set_current_buf(buf)

	vim.keymap.set("n", "q", function()
		vim.notify("❌ Commit canceled.", vim.log.levels.WARN)
		vim.api.nvim_buf_delete(buf, { force = true })
		if reset_on_cancel then
			vim.fn.system("git reset HEAD")
		end
	end, { buffer = buf, silent = true })

	vim.api.nvim_create_autocmd("BufWritePost", {
		buffer = buf,
		once = true,
		callback = function()
			M.commit_from_buffer(buf, reset_on_cancel)
		end,
	})
	vim.api.nvim_create_autocmd("BufUnload", {
		buffer = buf,
		callback = function()
			if vim.fn.filereadable(tmpfile) == 1 then
				pcall(os.remove, tmpfile)
			end
		end,
	})
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

-- Shows a floating window with the commit message and key bindings
function M.show_commit_ui(message, is_staged)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	local cwd = vim.fn.getcwd()
	local dir_name = vim.fn.fnamemodify(cwd, ":t")
	local branch = git.branch_name()

	local lines = {}
	table.insert(lines, " 📁 Repo: " .. dir_name .. "   🌿 Branch: " .. branch)
	table.insert(lines, "")
	table.insert(lines, " Generated commit message: ")
	table.insert(lines, "")

	local max_lines = 10
	local mlines = vim.split(message, "\n")
	for i, line in ipairs(mlines) do
		if i > max_lines then
			table.insert(lines, "  ... (truncated)")
			break
		end
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
	local width = math.floor(vim.o.columns * 0.7)
	local height = math.min(40, #lines + 2)
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = "rounded",
	})

	-- Styling via extmarks
	local ns = vim.api.nvim_create_namespace("commit-ui")
	vim.api.nvim_buf_add_highlight(buf, ns, "Identifier", 0, 0, #(" 📁 Repo: " .. dir_name))
	vim.api.nvim_buf_add_highlight(buf, ns, "Type", 0, #(" 📁 Repo: " .. dir_name .. "   🌿 "), -1)
	vim.api.nvim_buf_add_highlight(buf, ns, "Title", 2, 0, -1)
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

	local highlights = {
		Refactor = "Keyword",
		Feature = "String",
		Bugfix = "Error",
	}
	-- Highlight commit types (e.g., "Refactor", "Feature", "Bugfix")
	for i, line in ipairs(lines) do
		for word, hl in pairs(highlights) do
			local s, e = line:find(word)
			if s and e then
				vim.api.nvim_buf_add_highlight(buf, ns, hl, i - 1, s - 1, e)
			end
		end
	end
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
	-- Keymaps
	vim.keymap.set("n", "q", function()
		if is_staged then
			vim.fn.system("git reset HEAD")
		end
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf, silent = true })

	vim.keymap.set("n", "c", function()
		vim.api.nvim_win_close(win, true)
		M.commit_with_message(message, is_staged)
	end, { buffer = buf, silent = true })

	vim.keymap.set("n", "e", function()
		vim.api.nvim_win_close(win, true)
		M.open_commit_buffer(message, is_staged)
	end, { buffer = buf, silent = true })

	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		buffer = buf,
		callback = function()
			vim.api.nvim_win_set_cursor(win, { #lines - 2, 0 })
		end,
	})
end

-- Fetches from remote if available and returns if we’re behind
function M.check_remote_status()
	if git.can_fetch() then
		vim.fn.system({ "git", "fetch" })

		local status = vim.fn.system("git status --porcelain -b")
		if status:find("%[behind") then
			return false, "⚠️  You are behind the remote branch! Please run git pull first."
		end
	end

	return true
end

-- Checks if current buffer is inside a Git repo and changes CWD
function M.ensure_git_repo()
	local filepath = vim.api.nvim_buf_get_name(0)
	local git_root = git.find_git_root(filepath)
	if not git_root then
		return false, "🚫 Not a Git repository."
	end

	vim.fn.chdir(git_root)
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

	vim.defer_fn(function()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end, 3000)
end

function M.run()
	-- Check for Git repo
	local ok, err = M.ensure_git_repo()
	if not ok then
		show_floating_message(err)
		return
	end

	-- Check remote tracking status
	if config.options.auto_fetch then
		local ok_remote, err_remote = M.check_remote_status()
		if not ok_remote then
			show_floating_message(err_remote)
			return
		end
	end

	-- Check for changes
	if not git.has_changes_to_commit() then
		show_floating_message("✅ No changes to commit.")
		return
	end

	-- Stage files
	local reset_on_cancel = false
	if config.options.stage_all then
		vim.fn.system("git add -A")
		reset_on_cancel = true
	elseif not git.has_staged_changes() then
		--TODO: Add a staging UI
		show_floating_message(" 🚫 Nothing staged. Stage something first.")
		return
	end

	-- Get diff of staged changes
	local diff = vim.fn.system("git diff --cached")
	if diff == "" then
		show_floating_message("❌ No staged changes found.")
		return
	end

	-- Generate commit message and open UI
	M.generate_commit_message(diff, function(msg)
		M.show_commit_ui(msg, reset_on_cancel)
	end)
end

return M
