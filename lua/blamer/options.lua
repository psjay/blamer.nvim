-- Default options
local M = {
	window_width = 50, -- Width of the blame window
	show_summary = true, -- Whether to show commit summary
	date_format = "%Y-%m-%d %H:%M:%S", -- Date format
	update_delay = 500, -- Delay in milliseconds for updating blame info
	separator = "│", -- Separator between columns
	border = "single", -- Window border style: "none", "single", "double", "rounded", "solid", "shadow"
	highlight = {
		hash = "Identifier", -- Git hash highlight group
		author = "Type", -- Author highlight group
		date = "String", -- Date highlight group
		summary = "Comment", -- Summary highlight group
		separator = "NonText", -- Separator highlight group
		modified = "WarningMsg", -- Modified lines highlight group
	},
	padding = {
		left = 1, -- Left padding for each column
		right = 1, -- Right padding for each column
	},
}

M.merge_options = function(opts)
	M = vim.tbl_deep_extend("force", M, opts or {})
end

return M
