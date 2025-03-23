print("loaded gitcommit.lua")
local M = {}

function M.setup(opts)
	-- Config toepassen
	M.options = vim.tbl_deep_extend("force", {
		model = "gpt-3.5-turbo",
		temperature = 0.7,
		system_prompt = "Je bent een AI die git commit messages schrijft.",
	}, opts or {})

	-- eventueel autocommands of keymaps hier
	-- Keymap voor het schrijven van een commit message
	-- vim.api.nvim_set_keymap("n", "<leader>gc", ":lua require('gitcommit').write_commit_message()<CR>", { noremap = true, silent = true })
	-- vim.api.nvim_set_keymap("n", "<leader>gC", ":lua require('gitcommit').write_commit_message({ amend = true })<CR>", { noremap = true, silent = true })
	-- vim.api.nvim_set_keymap("n", "<leader>gca", ":lua require('gitcommit').write_commit_message({ amend = true, all = true })<CR>", { noremap = true, silent = true })
	-- vim.api.nvim_set_keymap("n", "<leader>gcm", ":lua require('gitcommit').write_commit_message({ message = vim.fn.input('Commit message: ') })<CR>", { noremap = true, silent = true })
	-- vim.api.nvim_set_keymap("n", "<leader>gcf", ":lua require('gitcommit').write_commit_message({ fixup = true })<CR>", { noremap = true, silent = true })
	-- vim.api.nvim_set_keymap("n", "<leader>gcs", ":lua require('gitcommit').write_commit_message({ squash = true })<CR>", { noremap = true, silent = true })
	-- vim.api.nvim_set_keymap("n", "<leader>gcr", ":lua require('gitcommit').write_commit_message({ reword = true })<CR>", { noremap = true, silent = true })
	--
end

function M.write_commit_message(opts)
	local options = vim.tbl_deep_extend("force", M.options, opts or {})

	-- Check of er wijzigingen zijn
	if not M.check_git_status() then
		return
	end

	-- Commit message schrijven
	local message = vim.fn.system("git log -1 --pretty=%B")
	if options.reword then
		message = vim.fn.input("Nieuwe commit message: ", message)
	elseif options.fixup then
		message = "fixup! " .. message
	elseif options.squash then
		message = "squash! " .. message
	elseif options.message then
		message = options.message
	end

	-- Commit aanmaken
	local cmd = "git commit"
	if options.amend then
		cmd = cmd .. " --amend"
	end
	if options.all then
		cmd = cmd .. " -a"
	end
	cmd = cmd .. " -m " .. vim.fn.shellescape(message)
	vim.fn.system(cmd)

	print("✅ Commit aangemaakt.")
end

function M.check_git_status()
	local function run(cmd)
		return vim.fn.system(cmd)
	end

	-- Check of de branch achterloopt
	local status = run("git status --porcelain -b")
	if status:find("%[behind") then
		print("⚠️  Je loopt achter op de remote branch! Haal eerst de laatste wijzigingen op (git pull).")
		return false
	end

	-- Check op ongetrackte bestanden
	local untracked = run("git ls-files --others --exclude-standard")
	if #untracked:gsub("%s+", "") > 0 then
		print("⚠️  Ongetrackte bestanden gevonden:")
		for line in untracked:gmatch("[^\r\n]+") do
			print("  " .. line)
		end
		print("⚠️  Voeg ze toe met `git add`.")
		return false
	end

	-- Check of er veranderingen zijn
	local status_lines = {}
	for line in status:gmatch("[^\r\n]+") do
		table.insert(status_lines, line)
	end

	if #status_lines == 1 then
		print("✅ Geen wijzigingen om te committen.")
		return false
	end

	print("🔍 Gewijzigde bestanden:")
	for i = 2, #status_lines do
		print("  " .. status_lines[i])
	end

	return true
end

return M
