-- Default options
local M = {
	window_width = 50, -- Width of the blame window
	show_summary = true, -- Whether to show commit summary
	date_format = "%Y-%m-%d %H:%M:%S", -- Date format
	update_delay = 500, -- Delay in milliseconds for updating blame info
}

M.merge_options = function(opts)
	M = vim.tbl_deep_extend("force", M, opts or {})
end

return M
