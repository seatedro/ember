vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 4
vim.opt.expandtab = true

vim.keymap.set("n", "<F1>", function()
	local Terminal = require("toggleterm.terminal").Terminal
	local build = Terminal:new({
		cmd = "./build.sh",
		dir = vim.fn.getcwd(),
		direction = "horizontal",
		close_on_exit = false,
	})
	build:toggle()
end, { desc = "Build ember" })
