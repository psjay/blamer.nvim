local git = require("blamer.git")
local options = require("blamer.options")
local api = vim.api

local M = {}
M.buf_to_blame = nil
M.buf_to_blame_autocmd = nil
M.blame_winid = nil
M.to_blamed_buf_win = nil
M.original_window_settings = {
	scrollbind = false,
	cursorbind = false
}

-- Function to format blame information
local function format_blame_info(blame_info)
	local formatted = {}
	local max_lengths = { hash = 0, author = 0, time = 0 }

	-- First pass: calculate maximum lengths
	for _, info in ipairs(blame_info) do
		if info and info.hash then
			local is_modified = info.hash:match("^0+$")
			local hash = is_modified and "Not Committed" or info.hash:sub(1, 8)
			local author = is_modified and " " or info.author
			local time = info["author-time"] and tonumber(info["author-time"])
			local time_str = is_modified and " " or (time and os.date(options.date_format, time))

			max_lengths.hash = math.max(max_lengths.hash, #hash)
			max_lengths.author = math.max(max_lengths.author, #author)
			max_lengths.time = math.max(max_lengths.time, #time_str)
		end
	end

	-- Second pass: format with padding
	for _, info in ipairs(blame_info) do
		if info and info.hash then
			local is_modified = info.hash:match("^0+$")
			local hash = is_modified and "Not Committed" or info.hash:sub(1, 8)
			local author = is_modified and " " or info.author
			local time = info["author-time"] and tonumber(info["author-time"])
			local time_str = is_modified and " " or (time and os.date(options.date_format, time))
			local summary = is_modified and " " or info.summary

			local line = string.format(
				"%-" .. max_lengths.hash .. "s | %-" .. max_lengths.author .. "s | %-" .. max_lengths.time .. "s",
				hash,
				author,
				time_str
			)
			if options.show_summary then
				line = line .. string.format(" | %s", summary)
			end

			if info.line_number then
				formatted[info.line_number] = line
			end
		end
	end

	return formatted
end

M.update_blame_info = function(blame_bufnr, formatted_blame)
	if not (api.nvim_buf_is_valid(blame_bufnr) and M.blame_winid and api.nvim_win_is_valid(M.blame_winid)) then
		return
	end
	local blame_lines = {}
	for i = 1, #formatted_blame do
		table.insert(blame_lines, formatted_blame[i] or string.rep(" ", options.window_width))
	end
	vim.bo[blame_bufnr].modifiable = true
	api.nvim_buf_set_lines(blame_bufnr, 0, -1, false, blame_lines)
	vim.bo[blame_bufnr].modifiable = false
end

-- Function to show blame information in a new window
function M.show_blame()
	local current_bufnr = api.nvim_get_current_buf()
	local current_winid = api.nvim_get_current_win()

	-- Save original window settings
	M.original_window_settings.scrollbind = vim.wo[current_winid].scrollbind
	M.original_window_settings.cursorbind = vim.wo[current_winid].cursorbind

	-- Create a new buffer for blame info
	local blame_bufnr = api.nvim_create_buf(false, true)

	-- Open a new window and set its buffer
	api.nvim_command("vsplit")
	local blame_winid = api.nvim_get_current_win()
	api.nvim_win_set_buf(blame_winid, blame_bufnr)

	-- Set buffer options
	vim.bo[blame_bufnr].buftype = "nofile"
	vim.bo[blame_bufnr].bufhidden = "wipe"
	vim.bo[blame_bufnr].filetype = "blamer"
	api.nvim_buf_set_name(blame_bufnr, "Blamer")

	-- Set window options
	vim.wo[blame_winid].wrap = false
	vim.wo[blame_winid].number = vim.wo[current_winid].number
	vim.wo[blame_winid].relativenumber = vim.wo[current_winid].relativenumber
	vim.wo[blame_winid].cursorline = true
	api.nvim_win_set_width(blame_winid, options.window_width)

	-- Switch back to the original window
	vim.api.nvim_set_current_win(current_winid)

	-- Set up autocommands to disable scrollbind and clean up
	local augroup = api.nvim_create_augroup("BlamerAuGroup", { clear = true })

	local function get_buff_for_target_win()
		if vim.api.nvim_win_is_valid(current_winid) then
			local buf_id = vim.api.nvim_win_get_buf(current_winid)
			return buf_id
		else
			return nil
		end
	end

	local function setup_for_new_buff(buff)
		git.throttled_blame(buff, function(blame_info)
			local formatted_blame = format_blame_info(blame_info)
			M.update_blame_info(blame_bufnr, formatted_blame)
			vim.wo[M.blame_winid].scrollbind = true
			vim.wo[M.blame_winid].cursorbind = true
			vim.wo[current_winid].scrollbind = true
			vim.wo[current_winid].cursorbind = true
			api.nvim_command("syncbind")
		end)
		M.buf_to_blame_autocmd = api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
			group = augroup,
			buffer = buff,
			callback = function()
				git.throttled_blame(buff, function(blame_info)
					local formatted_blame = format_blame_info(blame_info)
					M.update_blame_info(blame_bufnr, formatted_blame)
				end)
			end,
		})
	end

	local bufenter_autocmd_id = api.nvim_create_autocmd({ "BufEnter" }, {
		group = augroup,
		pattern = "*",
		nested = true,
		callback = function()
			if get_buff_for_target_win() ~= api.nvim_get_current_buf() then
				return
			end
			if get_buff_for_target_win() == M.buf_to_blame then
				return
			end

			if M.buf_to_blame_autocmd then
				pcall(api.nvim_del_autocmd, M.buf_to_blame_autocmd)
			end

			-- Set up autocommand for buffer changes
			M.buf_to_blame = api.nvim_get_current_buf()
			if M.buf_to_blame then
				setup_for_new_buff(M.buf_to_blame)
			end
		end,
	})

	api.nvim_create_autocmd({ "WinClosed" }, {
		group = augroup,
		pattern = tostring(blame_winid),
		callback = function()
			api.nvim_del_autocmd(bufenter_autocmd_id)
			api.nvim_del_autocmd(M.buf_to_blame_autocmd)
			M.blame_winid = nil
		end,
	})

	api.nvim_buf_set_keymap(blame_bufnr, "n", "q", "", {
		callback = function()
			api.nvim_win_close(blame_winid, true)
		end,
		noremap = true,
		silent = true,
	})
	api.nvim_buf_set_keymap(blame_bufnr, "n", "<ESC>", "", {
		callback = function()
			api.nvim_win_close(blame_winid, true)
		end,
		noremap = true,
		silent = true,
	})

	M.blame_winid = blame_winid
	M.buf_to_blame = current_bufnr
	M.to_blamed_buf_win = current_winid
	setup_for_new_buff(M.buf_to_blame)
end

function M.toggle_blame()
	if M.blame_winid and api.nvim_win_is_valid(M.blame_winid) then
		api.nvim_win_close(M.blame_winid, false)
		M.blame_winid = nil
		-- Restore original settings
		if M.to_blamed_buf_win and api.nvim_win_is_valid(M.to_blamed_buf_win) then
			vim.wo[M.to_blamed_buf_win].scrollbind = M.original_window_settings.scrollbind
			vim.wo[M.to_blamed_buf_win].cursorbind = M.original_window_settings.cursorbind
		end
		M.to_blamed_buf_win = nil
	else
		M.show_blame()
	end
end

-- Cleanup function
function M.cleanup()
	if M.blame_winid and api.nvim_win_is_valid(M.blame_winid) then
		api.nvim_win_close(M.blame_winid, false)
	end
	if M.buf_to_blame_autocmd then
		pcall(api.nvim_del_autocmd, M.buf_to_blame_autocmd)
	end
	git.cleanup()
	M.blame_winid = nil
	M.buf_to_blame = nil
	M.to_blamed_buf_win = nil
end

-- Setup function
function M.setup(opts)
	-- Merge user options with defaults
	options.merge_options(opts)

	-- Create user command
	api.nvim_create_user_command("BlamerToggle", M.toggle_blame, {})
	
	-- Set up cleanup on VimLeavePre
	api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			M.cleanup()
		end,
	})
end

return M
