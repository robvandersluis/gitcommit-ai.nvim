local M = {}

function M.current_branch()
	local output = vim.fn.systemlist("git rev-parse --abbrev-ref HEAD")
	return output[1]
end

function M.in_git_repo()
	return vim.fn.isdirectory(".git") == 1
end

-- Find Git root directory by walking up
function M.find_git_root(start_path)
	start_path = vim.fn.fnamemodify(start_path or vim.api.nvim_buf_get_name(0), ":p")
	while start_path and start_path ~= "/" do
		if vim.fn.isdirectory(start_path .. "/.git") == 1 then
			return start_path
		end
		start_path = vim.fn.fnamemodify(start_path, ":h")
	end
	return nil
end

function M.get_remotes()
	return vim.fn.systemlist("git remote")
end

function M.has_remote()
	return #M.get_remotes() > 0
end

function M.get_tracking_branch()
	local output = vim.fn.systemlist("git rev-parse --abbrev-ref --symbolic-full-name @{u}")
	return not (output[1] or ""):match("fatal:") and output[1] or nil
end

-- Check if current branch has an upstream/tracking remote
function M.has_tracking_branch()
	local output = vim.fn.systemlist("git rev-parse --abbrev-ref --symbolic-full-name @{u}")
	return not (output[1] or ""):match("fatal:")
end

function M.has_staged_changes()
	local output = vim.fn.systemlist("git diff --staged --name-only")
	return #output > 0
end

function M.has_untracked_files()
	local output = vim.fn.systemlist("git ls-files --others --exclude-standard")
	return #output > 0
end

function M.has_unstaged_changes()
	local output = vim.fn.systemlist("git diff --name-only")
	return #output > 0
end

-- Check if local branch is behind remote
function M.is_behind()
	local output = vim.fn.systemlist("git status -sb")[1]
	return output and output:match("%[behind")
end

function M.can_push()
	return M.has_remote() and M.has_tracking_branch() and not M.is_behind()
end

function M.can_fetch()
	return M.has_remote() and M.has_tracking_branch()
end
return M
