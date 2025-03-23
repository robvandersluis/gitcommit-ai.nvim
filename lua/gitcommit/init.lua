-- lua/gitcommit/init.lua
local M = {}

function M.setup(opts)
	local config = require("gitcommit.config")
	config.setup(opts)

	vim.api.nvim_create_user_command("GenerateCommitMessage", function()
		require("gitcommit.core").run()
	end, { desc = "Genereer commit message via OpenAI" })
end

return M
