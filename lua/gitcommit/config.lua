-- lua/gitcommit/config.lua
local M = {}

M.options = {
	model = "gpt-3.5-turbo",
	temperature = 0.7,
	system_prompt = "Je bent een AI die behulpzame git commit messages genereert.",
	user_prompt = "Genereer een duidelijke commit message op basis van deze git diff:",
}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

return M
