local options = require("blamer.options")

local M = {}
local api = vim.api
local fn = vim.fn
local timer = vim.uv.new_timer()

-- Function to parse git blame output
local function parse_blame_output(blame_output)
	local parsed_blame = {}
	local commit_cache = {}
	local line_number = 0

	local i = 1
	while i <= #blame_output do
		local line = blame_output[i]
		if not line then
			break
		end

		if line:match("^%x+") then
			line_number = line_number + 1
			local hash, orig_line, final_line, group_lines = line:match("^(%x+)%s+(%d+)%s+(%d+)%s*(%d*)")

			local current_commit
			if commit_cache[hash] then
				current_commit = vim.deepcopy(commit_cache[hash])
			else
				current_commit = {
					hash = hash,
					author = "",
					time = 0,
					time_str = "",
					summary = "",
					orig_line = tonumber(orig_line),
					final_line = tonumber(final_line),
					group_lines = tonumber(group_lines) or 1,
				}
				commit_cache[hash] = current_commit
			end

			current_commit.line_number = line_number

			-- Parse additional information
			while i <= #blame_output do
				i = i + 1
				local info_line = blame_output[i]
				if info_line:match("^\t") then
					break
				end -- Content line starts

				local key, value = info_line:match("^([%w-]+)%s(.+)")
				if key and value then
					current_commit[key] = value
					commit_cache[hash][key] = value
				end
			end

			-- Add content line
			if blame_output[i] and blame_output[i]:match("^\t") then
				current_commit.content = blame_output[i]:sub(2) -- Remove leading tab
			end

			table.insert(parsed_blame, current_commit)
		end

		i = i + 1
	end
	return parsed_blame
end

local function async_get_git_blame(bufnr, callback)
	local filepath = api.nvim_buf_get_name(bufnr)
	local tempfile = fn.tempname()
	-- Write buffer contents to temp file
	local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
	fn.writefile(lines, tempfile)

	-- Find git root directory
	local git_root_cmd =
		string.format("git -C %s rev-parse --show-toplevel 2>/dev/null", fn.shellescape(fn.fnamemodify(filepath, ":h")))
	local git_root = fn.trim(fn.system(git_root_cmd))

	if git_root == "" then
		-- Not in a git repository
		callback(nil)
		fn.delete(tempfile)
		return
	end

	-- Get relative path from git root
	local relative_path = fn.fnamemodify(filepath, ":.")
	if fn.isdirectory(git_root) == 1 then
		relative_path = fn.fnamemodify(filepath, ":s?" .. git_root .. "/?")
	end

	-- Prepare git blame command
	local blame_cmd = string.format(
		"git -C %s blame --porcelain %s --contents %s",
		fn.shellescape(git_root),
		fn.shellescape(relative_path),
		fn.shellescape(tempfile)
	)

	-- Run git blame asynchronously
	fn.jobstart(blame_cmd, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			if data then
				local blame_output = data
				local parsed_blame = parse_blame_output(blame_output)
				callback(parsed_blame)
			end
		end,
		on_exit = function()
			-- Clean up temp file
			fn.delete(tempfile)
		end,
	})
end

-- Set up throttled update for the current buffer
M.throttled_blame = function(buf_to_blame, callback)
	if timer:is_active() then
		timer:stop()
	end
	timer:start(
		options.update_delay,
		0,
		vim.schedule_wrap(function()
			async_get_git_blame(buf_to_blame, callback)
		end)
	)
end

return M
