-- plugin/toc.lua
-- Neovim起動時に自動実行されるエントリポイント。
-- :Toc コマンドを登録するだけ。ロジック本体は require("toc") で遅延ロードされる。
-- vim.g.loaded_toc ガードにより二重読み込みを防止する。
if vim.g.loaded_toc then
	return
end
vim.g.loaded_toc = true

vim.api.nvim_create_user_command("Toc", function(args)
	local opts = {}
	if args.args ~= "" then
		local width = tonumber(args.args)
		if width then
			opts.width = width
		end
	end
	require("toc").open(opts)
end, {
	nargs = "?",
	desc = "Show Table of Contents",
})
