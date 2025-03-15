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
M.hash_highlights = {}
M.next_color_index = 1
M.last_buffer = nil

-- Function to convert hex color to RGB
local function hex_to_rgb(hex)
	if not hex then return 0, 0, 0 end
	hex = hex:gsub("#", "")
	return tonumber(hex:sub(1, 2), 16) or 0,
		tonumber(hex:sub(3, 4), 16) or 0,
		tonumber(hex:sub(5, 6), 16) or 0
end

-- Function to convert RGB to hex
local function rgb_to_hex(r, g, b)
	return string.format("#%02x%02x%02x", r, g, b)
end

-- Function to get color from highlight group
local function get_hl_color(group)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group })
	if ok and hl and hl.fg then
		return string.format("#%06x", hl.fg)
	end
	return nil
end

-- Function to get theme colors
local function get_theme_colors()
	local colors = {}
	local groups = {
		"Identifier",  -- Usually blue/cyan
		"Type",       -- Usually green
		"String",     -- Usually yellow/orange
		"Function",   -- Usually purple/magenta
		"Keyword",    -- Usually red
		"Special",    -- Usually orange/brown
		"Statement",  -- Usually bold/bright
		"Constant"    -- Usually purple/red
	}
	
	for _, group in ipairs(groups) do
		local color = get_hl_color(group)
		if color then
			table.insert(colors, color)
		end
	end
	
	-- Add some fallback colors if we couldn't get enough from the theme
	if #colors < 4 then
		table.insert(colors, "#ff5555") -- Red
		table.insert(colors, "#50fa7b") -- Green
		table.insert(colors, "#bd93f9") -- Purple
		table.insert(colors, "#f1fa8c") -- Yellow
	end
	
	return colors
end

-- Function to make color more vibrant
local function make_vibrant(color)
	local r, g, b = hex_to_rgb(color)
	-- Increase saturation by boosting the dominant channel
	local max_val = math.max(r, g, b)
	if r == max_val then
		r = math.min(255, r * 1.2)
	elseif g == max_val then
		g = math.min(255, g * 1.2)
	elseif b == max_val then
		b = math.min(255, b * 1.2)
	end
	return rgb_to_hex(math.floor(r), math.floor(g), math.floor(b))
end

-- Function to make color more muted
local function make_muted(color)
	local r, g, b = hex_to_rgb(color)
	local bg_r, bg_g, bg_b = hex_to_rgb(get_hl_color("Normal") or "#000000")
	
	-- Move color 40% towards background (reduce saturation and brightness)
	r = math.floor(r * 0.6 + bg_r * 0.4)
	g = math.floor(g * 0.6 + bg_g * 0.4)
	b = math.floor(b * 0.6 + bg_b * 0.4)
	
	return rgb_to_hex(r, g, b)
end

-- Function to get color for a commit hash
local function get_hash_color(hash)
	if not hash then return nil end
	
	if hash:match("^0+$") then
		return get_hl_color("WarningMsg")
	end

	if not M.hash_highlights[hash] then
		local theme_colors = get_theme_colors()
		if #theme_colors > 0 then
			M.hash_highlights[hash] = theme_colors[M.next_color_index]
			M.next_color_index = (M.next_color_index % #theme_colors) + 1
		end
	end

	return M.hash_highlights[hash]
end

-- Function to setup hash highlights
local function setup_hash_highlights(blame_bufnr)
	-- Reset color assignments if buffer changed
	if M.last_buffer ~= blame_bufnr then
		M.hash_highlights = {}
		M.next_color_index = 1
		M.last_buffer = blame_bufnr
	end
end

-- Function to format blame information
local function format_blame_info(blame_info)
	if not blame_info then return {}, {} end
	
	local formatted = {}
	local max_lengths = { hash = 0, author = 0, time = 0 }
	local hash_positions = {} -- Store hash positions for highlighting

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
		if info and info.hash and info.line_number then
			local is_modified = info.hash:match("^0+$")
			local hash = is_modified and "Not Committed" or info.hash:sub(1, 8)
			local author = is_modified and " " or info.author
			local time = info["author-time"] and tonumber(info["author-time"])
			local time_str = is_modified and " " or (time and os.date(options.date_format, time))
			local summary = is_modified and " " or info.summary

			local padding = string.rep(" ", options.padding.left)
			local sep = padding .. options.separator .. padding

			local line = string.format(
				"%-" .. max_lengths.hash .. "s%s%-" .. max_lengths.author .. "s%s%-" .. max_lengths.time .. "s",
				hash,
				sep,
				author,
				sep,
				time_str
			)
			if options.show_summary then
				line = line .. string.format("%s%s", sep, summary)
			end

			formatted[info.line_number] = line
			-- Store positions for highlighting
			hash_positions[info.line_number] = {
				hash = info.hash,
				columns = {
					hash = { start = 0, ["end"] = max_lengths.hash },
					sep1 = { start = max_lengths.hash, ["end"] = max_lengths.hash + #sep },
					author = { start = max_lengths.hash + #sep, ["end"] = max_lengths.hash + #sep + max_lengths.author },
					sep2 = { start = max_lengths.hash + #sep + max_lengths.author, ["end"] = max_lengths.hash + 2 * #sep + max_lengths.author },
					date = { start = max_lengths.hash + 2 * #sep + max_lengths.author, ["end"] = max_lengths.hash + 2 * #sep + max_lengths.author + max_lengths.time }
				}
			}
			if options.show_summary then
				hash_positions[info.line_number].columns.sep3 = {
					start = max_lengths.hash + 2 * #sep + max_lengths.author + max_lengths.time,
					["end"] = max_lengths.hash + 3 * #sep + max_lengths.author + max_lengths.time
				}
				hash_positions[info.line_number].columns.summary = {
					start = max_lengths.hash + 3 * #sep + max_lengths.author + max_lengths.time,
					["end"] = #line
				}
			end
		end
	end

	return formatted, hash_positions
end

M.update_blame_info = function(blame_bufnr, formatted_blame, hash_positions)
	if not (api.nvim_buf_is_valid(blame_bufnr) and M.blame_winid and api.nvim_win_is_valid(M.blame_winid)) then
		return
	end

	setup_hash_highlights(blame_bufnr)

	local blame_lines = {}
	for i = 1, #formatted_blame do
		table.insert(blame_lines, formatted_blame[i] or string.rep(" ", options.window_width))
	end

	vim.bo[blame_bufnr].modifiable = true
	api.nvim_buf_set_lines(blame_bufnr, 0, -1, false, blame_lines)

	-- Apply colors
	local ns_id = vim.api.nvim_create_namespace("blamer_highlights")
	-- Clear existing highlights
	vim.api.nvim_buf_clear_namespace(blame_bufnr, ns_id, 0, -1)
	
	for line_num, pos_info in pairs(hash_positions) do
		local commit_color = get_hash_color(pos_info.hash)
		if commit_color then
			-- Apply column colors with different emphasis
			local columns = pos_info.columns

			-- Create highlight groups for each column
			local hash_hl_group = "BlamerHash" .. pos_info.hash:sub(1, 8)
			local author_hl_group = "BlamerAuthor" .. pos_info.hash:sub(1, 8)
			local date_hl_group = "BlamerDate" .. pos_info.hash:sub(1, 8)
			local summary_hl_group = "BlamerSummary" .. pos_info.hash:sub(1, 8)

			-- Set up highlight groups with different emphasis
			-- Hash: Make it vibrant (most prominent)
			vim.api.nvim_set_hl(0, hash_hl_group, { fg = make_vibrant(commit_color), bold = true })
			
			-- Author: Keep original color (prominent)
			vim.api.nvim_set_hl(0, author_hl_group, { fg = commit_color })
			
			-- Date: Make it muted (less prominent)
			vim.api.nvim_set_hl(0, date_hl_group, { fg = make_muted(commit_color) })
			
			-- Summary: Make it very muted (least prominent)
			vim.api.nvim_set_hl(0, summary_hl_group, { fg = make_muted(commit_color), italic = true })

			-- Apply highlights
			pcall(vim.api.nvim_buf_add_highlight, blame_bufnr, ns_id, hash_hl_group, line_num - 1, columns.hash.start, columns.hash["end"])
			pcall(vim.api.nvim_buf_add_highlight, blame_bufnr, ns_id, author_hl_group, line_num - 1, columns.author.start, columns.author["end"])
			pcall(vim.api.nvim_buf_add_highlight, blame_bufnr, ns_id, date_hl_group, line_num - 1, columns.date.start, columns.date["end"])

			-- Separators
			pcall(vim.api.nvim_buf_add_highlight, blame_bufnr, ns_id, "NonText", line_num - 1, columns.sep1.start, columns.sep1["end"])
			pcall(vim.api.nvim_buf_add_highlight, blame_bufnr, ns_id, "NonText", line_num - 1, columns.sep2.start, columns.sep2["end"])

			-- Summary column
			if options.show_summary and columns.summary then
				pcall(vim.api.nvim_buf_add_highlight, blame_bufnr, ns_id, summary_hl_group, line_num - 1, columns.summary.start, columns.summary["end"])
				pcall(vim.api.nvim_buf_add_highlight, blame_bufnr, ns_id, "NonText", line_num - 1, columns.sep3.start, columns.sep3["end"])
			end
		end
	end

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
	vim.wo[blame_winid].signcolumn = "no"
	api.nvim_win_set_width(blame_winid, options.window_width)

	-- Set window border
	if options.border ~= "none" then
		local border = options.border
		if type(border) == "string" then
			-- Check if UTF-8 is supported
			local ok, result = pcall(vim.api.nvim_eval, [[&encoding == "utf-8" ? "single" : "none"]])
			border = ok and result or "none"
		end
		
		-- Only set border if supported by Neovim version
		pcall(function()
			api.nvim_win_set_config(blame_winid, {
				border = border,
			})
		end)
	end

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
			local formatted_blame, hash_positions = format_blame_info(blame_info)
			M.update_blame_info(blame_bufnr, formatted_blame, hash_positions)
			
			-- Only set scrollbind if windows are still valid
			if vim.api.nvim_win_is_valid(M.blame_winid) and vim.api.nvim_win_is_valid(current_winid) then
				vim.wo[M.blame_winid].scrollbind = true
				vim.wo[M.blame_winid].cursorbind = true
				vim.wo[current_winid].scrollbind = true
				vim.wo[current_winid].cursorbind = true
				api.nvim_command("syncbind")
			end
		end)
		
		-- Remove existing autocmd if it exists
		if M.buf_to_blame_autocmd then
			pcall(api.nvim_del_autocmd, M.buf_to_blame_autocmd)
		end
		
		M.buf_to_blame_autocmd = api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
			group = augroup,
			buffer = buff,
			callback = function()
				git.throttled_blame(buff, function(blame_info)
					local formatted_blame, hash_positions = format_blame_info(blame_info)
					M.update_blame_info(blame_bufnr, formatted_blame, hash_positions)
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
			pcall(api.nvim_del_autocmd, bufenter_autocmd_id)
			if M.buf_to_blame_autocmd then
				pcall(api.nvim_del_autocmd, M.buf_to_blame_autocmd)
			end
			M.blame_winid = nil
		end,
	})

	api.nvim_buf_set_keymap(blame_bufnr, "n", "q", "", {
		callback = function()
			if api.nvim_win_is_valid(blame_winid) then
				api.nvim_win_close(blame_winid, true)
			end
		end,
		noremap = true,
		silent = true,
	})
	api.nvim_buf_set_keymap(blame_bufnr, "n", "<ESC>", "", {
		callback = function()
			if api.nvim_win_is_valid(blame_winid) then
				api.nvim_win_close(blame_winid, true)
			end
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
	M.hash_highlights = {}
	M.next_color_index = 1
	M.last_buffer = nil
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
