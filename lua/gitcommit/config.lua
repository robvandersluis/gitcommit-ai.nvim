-- lua/gitcommitai/config.lua
local M = {}

M.options = {
	stage_all = true, -- Stage all changes before generating commit message
   auto_fetch = false, -- Fetch before pushing (if tracking branch exists). Disable to avoid blocking UI by default.
	prompt_after_commit = true, -- Prompt to push after committing
	model = "gpt-4o-mini",
 	temperature = 0.7,
 	-- Maximum time (in seconds) to wait for OpenAI API response
 	timeout = 30,
	system_prompt = [[
You are an assistant that only generates git commit messages.
Use one of the following prefixes:
- Feature: for new functionality
- Bugfix: for resolved bugs
- Refactor: for code changes without functional impact
Return only the commit message, without any explanation.
]],
	user_prompt = "Generate a clear commit message based on this git diff:",
	api_key = os.getenv("OPENAI_API_KEY"),
}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

return M
