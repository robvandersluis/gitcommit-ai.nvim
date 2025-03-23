-- lua/gitcommitai/config.lua
local M = {}

M.options = {
	model = "gpt-4o-mini",
	temperature = 0.7,
	system_prompt = "Je bent een AI die behulpzame git commit messages genereert.",
	user_prompt = "Genereer een duidelijke commit message op basis van deze git diff:",
	api_key = os.getenv("OPENAI_API_KEY"),
}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

return M
