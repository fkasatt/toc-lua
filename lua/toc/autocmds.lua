-- autocmds.lua
-- ToC セッション中に有効なオートコマンドをすべて登録する。
-- close() 時に各オーグループを削除して副作用を残さない。

local session = require("toc.session")
local config = require("toc.config")

local M = {}

--- オートコマンドをすべて登録する
function M.setup_autocmds()
	local S = session.get()
	local cfg = config.options

	-- VimResized: ターミナルリサイズ時にソース幅を保護しつつ ToC 列幅を復元する
	vim.api.nvim_create_autocmd("VimResized", {
		group = vim.api.nvim_create_augroup("toc_vim_resized", { clear = true }),
		callback = function()
			if not session.get() then
				return true
			end
			session.adjust_toc_width()
		end,
	})

	-- TextChanged/TextChangedI: ルートまたはインクルードバッファの変更でリフレッシュする
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = vim.api.nvim_create_augroup("toc_auto_refresh", { clear = true }),
		callback = function()
			local s = session.get()
			if not s or not vim.api.nvim_win_is_valid(s.toc_win) then
				return true
			end
			local cur = vim.api.nvim_get_current_buf()
			if cur == s.root_buf or (s.included_bufs and s.included_bufs[cur]) then
				require("toc.util").log("TextChanged: buf=" .. cur .. " -> do_refresh")
				session.do_refresh()
			end
		end,
	})

	-- WinEnter: タイトルウィンドウに入ったとき
	--   - ソースをルートファイルに切り替える
	--   - タイトルを全文表示する
	--   - 棒グラフのカレントハイライトを解除する
	if S.title_buf then
		vim.api.nvim_create_autocmd("WinEnter", {
			group = vim.api.nvim_create_augroup("toc_title_enter", { clear = true }),
			callback = function()
				local s = session.get()
				if not s or not s.title_win then
					return true
				end
				if not vim.api.nvim_win_is_valid(s.title_win) then
					return true
				end
				if vim.api.nvim_get_current_win() ~= s.title_win then
					return
				end
				local win = session.find_src_win()
				if win and vim.api.nvim_win_get_buf(win) ~= s.root_buf then
					s.src_buf = s.root_buf
					vim.api.nvim_win_set_buf(win, s.root_buf)
					vim.api.nvim_win_set_cursor(win, { 1, 0 })
				end
				if s.chart_buf and vim.api.nvim_buf_is_valid(s.chart_buf) then
					vim.api.nvim_buf_clear_namespace(s.chart_buf, session.get_chart_ns(), 0, -1)
				end
				if s.title_buf and vim.api.nvim_buf_is_valid(s.title_buf) then
					local w = vim.api.nvim_win_get_width(s.toc_win)
					session.refresh_title(s.entries, w, true)
				end
			end,
		})

		-- WinLeave: タイトルバッファから離れたら切り詰め表示に戻す
		vim.api.nvim_create_autocmd("WinLeave", {
			group = vim.api.nvim_create_augroup("toc_title_leave", { clear = true }),
			callback = function()
				local s = session.get()
				if not s or not s.title_win then
					return true
				end
				if not vim.api.nvim_win_is_valid(s.title_win) then
					return true
				end
				if vim.api.nvim_get_current_win() ~= s.title_win then
					return
				end
				if s.title_buf and vim.api.nvim_buf_is_valid(s.title_buf) then
					local w = vim.api.nvim_win_get_width(s.toc_win)
					session.refresh_title(s.entries, w, false)
				end
			end,
		})
	end

	-- CursorMoved: ToC バッファ上でカーソルが動いたとき
	--   - 棒グラフのカレントハイライトを更新する
	--   - ソースウィンドウを対応行にスクロールさせる
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = vim.api.nvim_create_augroup("toc_scroll_sync", { clear = true }),
		buffer = S.toc_buf,
		callback = function()
			local t0 = vim.uv.hrtime()
			local entry, _, idx = session.entry_at_cursor()
			if not entry then
				return
			end
			session.update_chart_current(idx)
			local win = session.find_src_win()
			if win then
				local s = session.get()
				local target = entry.src_buf or s.src_buf
				if vim.api.nvim_win_get_buf(win) ~= target then
					s.src_buf = target
					vim.api.nvim_win_set_buf(win, target)
				end
				vim.api.nvim_win_set_cursor(win, { entry.lnum, 0 })
				vim.api.nvim_win_call(win, function()
					vim.cmd("normal! zt")
				end)
			end
			require("toc.util").log(
				string.format("CursorMoved(entry=%d): %.1fms", idx, (vim.uv.hrtime() - t0) / 1e6)
			)
		end,
	})

	-- BufEnter: ToC/chart 以外の通常バッファに移動したとき
	--   - 対応 filetype であれば新しいバッファを root として ToC をリフレッシュする
	--   - インクルードバッファへの移動は src_buf を更新して ToC を維持する
	--   - filetype 確定を待つため vim.schedule で遅延実行する
	vim.api.nvim_create_autocmd("BufEnter", {
		group = vim.api.nvim_create_augroup("toc_src_follow", { clear = true }),
		callback = function()
			local buf0 = vim.api.nvim_get_current_buf()
			local name0 = vim.api.nvim_buf_get_name(buf0)
			require("toc.util").log(
				string.format(
					"BufEnter: buf=%d name=%s (schedule pending)",
					buf0,
					vim.fn.fnamemodify(name0, ":t")
				)
			)
			vim.schedule(function()
				local s = session.get()
				if not s or not vim.api.nvim_win_is_valid(s.toc_win) then
					return
				end
				local win = vim.api.nvim_get_current_win()
				-- ToC / chart / title ウィンドウは無視する
				if win == s.toc_win or win == s.chart_win or win == s.title_win then
					require("toc.util").log("BufEnter(scheduled): toc/chart/title win, skip")
					return
				end
				local buf = vim.api.nvim_get_current_buf()
				local bname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
				local btype = vim.bo[buf].buftype
				-- 特殊バッファ（nofile, terminal 等）は無視する
				if btype ~= "" then
					require("toc.util").log(
						string.format("BufEnter(scheduled): buf=%s buftype=%s, skip", bname, btype)
					)
					return
				end
				-- ルートバッファまたはソースバッファなら ToC を維持する
				if buf == s.root_buf or buf == s.src_buf then
					require("toc.util").log(
						string.format("BufEnter(scheduled): buf=%s is root/src, skip", bname)
					)
					return
				end
				if s.included_bufs and s.included_bufs[buf] then
					require("toc.util").log(
						string.format("BufEnter(scheduled): buf=%s is included, update src_buf", bname)
					)
					s.src_buf = buf
					return
				end
				local new_ft = vim.bo[buf].filetype
				-- filetype 未確定の場合は無視する
				if new_ft == "" then
					require("toc.util").log(
						string.format("BufEnter(scheduled): buf=%s ft empty, skip", bname)
					)
					return
				end
				local new_marker = config.heading_markers[new_ft]
				if new_marker then
					require("toc.util").log(
						string.format("BufEnter(scheduled): buf=%s ft=%s -> do_refresh", bname, new_ft)
					)
					s.root_buf = buf
					s.src_buf = buf
					s.ft = new_ft
					s.marker = new_marker
					s.included_bufs = {}
					session.do_refresh()
				else
					require("toc.util").log(
						string.format("BufEnter(scheduled): buf=%s ft=%s no marker, skip", bname, new_ft)
					)
				end
				-- 非対応 filetype（nvim-tree 等のツールバッファを含む）は無視して ToC を維持する
			end)
		end,
	})
end

return M
