🚀 A Neovim plugin that generates Git commit messages using OpenAI.
# gitcommit-ai.nvim

Save time and write better commit messages with the help of AI. This plugin analyzes your Git diff and generates a clear, consistent, and categorized commit message based on your changes.

---

## ✨ Features

- 🤖 Generates commit messages using OpenAI Chat API (GPT-3.5 / GPT-4 / GPT-4o)
- 🔍 Checks Git status before continuing
- 📄 Opens message in editable buffer (optional edits)
- 💾 Commit on save
- ❌ Cancel with `q`
- 🚀 Asks to push after commit
- 🔥 Default prompt with smart categorization (Feature, Bugfix, Refactor)

---

## 🛠 Installation (Lazy.nvim)

```lua
{
  "robvandersluis/gitcommit-ai.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("gitcommit").setup({
      stage_all = true, -- Automatically stage changes (git add -A)
    })

    vim.keymap.set("n", "<leader>gc", "<cmd>GenerateCommitMessage<CR>", { desc = "AI Commit" })
  end,
}
```

---

## 🔐 Setting your OpenAI API Key

This plugin reads your API key from the OPENAI_API_KEY environment variable by default.
You can also pass it manually via the api_key option in the setup() call (not recommended for security reasons).
### Linux / macOS (Zsh or Bash)
```bash
echo 'export OPENAI_API_KEY="sk-..."' >> ~/.zshrc  # or ~/.bashrc
source ~/.zshrc  # or source ~/.bashrc
```

### Windows (PowerShell)
```powershell
nvim $PROFILE
# Add this line:
$env:OPENAI_API_KEY = "sk-..."
. $PROFILE  # Reload the profile
```

---

## 🚀 Usage

- Run with command: `:GenerateCommitMessage`
- Or use the default keymap: `<leader>gc`

### Workflow:
1. Checks if the current buffer belongs to a valid Git repository
2. It checks for changes using git status --porcelain
3. If stage_all = true, it runs git add -A
4. If stage_all = false, it checks for staged changes and aborts if there are none
5. A commit message is generated using the staged diff (git diff --cached)
6. A preview buffer opens with the generated commit message
7. You can:
  - Edit (e) and save (:w) to confirm and commit
  - Quit (q) to cancel
8. If the commit is cancelled and stage_all = true, a git reset is performed to unstage changes 
9. Optionally prompts to push (only if a tracking branch exists)
9. Done! 🎉
---

## ⚙️ Configuration options

```lua
require("gitcommit").setup({
  model = "gpt-4o-mini", 
  temperature = 0.7,
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
  stage_all = true, -- Stage all changes (git add -A) before commit
  --    stage_all = false: You must stage files before running the plugin
  model = "gpt-4o",
  api_key = "...", -- optional (will default to env var)
})
```

Defaults already work well out-of-the-box.

---

## 🧠 Default prompt logic

The built-in prompt will guide the AI to:
- Detect the type of change (Feature, Bugfix, Refactor)
- Return only the commit message in format: `Feature: ...`
- Skip explanations

---

## 📷 screenshot

![MyPlugin Screenshot](media/screenshot.png)
---

## ✅ Todo / Ideas

- [x] Working core logic
- [x] Cancel with `q`
- [x] Ask to push
- [ ] Add retry (`:GenerateCommitMessage!`)
- [x] Add option for `git diff --cached`
- [x] Highlight AI output (e.g., markdown/comments)
- [ ] `.env` file support (dotenv)

---

Made with  and way too much coffee ☕ by [@robvandersluis](https://github.com/robvandersluis)

A Neovim plugin that generates AI-powered Git commit messages using OpenAI.
