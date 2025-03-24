local M = {}

-- Get current Git branch name
function M.current_branch()
	local output = vim.fn.systemlist("git rev-parse --abbrev-ref HEAD")
	return output[1]
end

-- Check if .git directory exists (i.e. we're in a Git repo)
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

-- Get list of Git remotes
function M.get_remotes()
	return vim.fn.systemlist("git remote")
end

-- Check if any remote exists
function M.has_remote()
	return #M.get_remotes() > 0
end

-- Check if current branch has an upstream/tracking remote
function M.has_tracking_branch()
	local output = vim.fn.systemlist("git rev-parse --abbrev-ref --symbolic-full-name @{u}")
	return not (output[1] or ""):match("fatal:")
end

-- Check if local branch is behind remote
function M.is_behind()
	local output = vim.fn.systemlist("git status -sb")[1]
	return output and output:match("%[behind")
end

-- Check if safe to push
function M.can_push()
	return M.has_remote() and M.has_tracking_branch() and not M.is_behind()
end

return M
