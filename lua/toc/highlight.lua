-- highlight.lua
-- プラグイン固有のハイライトグループを定義する。
-- default = true により、ユーザーのカラースキームが同名グループを定義していれば
-- そちらが優先される（上書きされない）。

local M = {}

--- ハイライトグループをすべて設定する
--- M.open() の初回呼び出し時に一度だけ実行される
function M.setup()
	local groups = {
		TocLevel1 = { bold = true, default = true, link = "Title" },
		TocLevel2 = { default = true },
		TocLevel3 = { default = true },
		TocLevel4 = { default = true, link = "NonText" },
		TocCharCount = { default = true, link = "Special" },
		TocTreeLine = { default = true, link = "NonText" },
		TocPreview = { default = true, link = "Comment" },
		TocDocTitle = { bold = true, default = true, link = "Title" },
		TocBarBlock = { default = true, link = "Function" },
		TocBarCurrent = { default = true, link = "WarningMsg" },
		TocBarLabel = { bold = true, default = true, link = "Number" },
	}
	for name, opts in pairs(groups) do
		vim.api.nvim_set_hl(0, name, opts)
	end
end

return M
