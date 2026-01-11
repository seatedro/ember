vim.api.nvim_create_autocmd("InsertEnter", {
	once = true,
	callback = function()
		local ok, loader = pcall(require, "luasnip.loaders.from_lua")
		if ok then
			loader.load({ paths = vim.fn.getcwd() .. "/.luasnippets" })
		end
	end,
})

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
