-- keymaps.lua
-- ToC バッファに対するすべてのキーマップを登録する。

local session = require("toc.session")
local config = require("toc.config")

local M = {}

--- ToC バッファ・タイトルバッファ・棒グラフバッファにキーマップを登録する
function M.setup_keymaps()
	local S = session.get()
	local buf = S.toc_buf
	local cfg = config.options

	-- <CR>: カーソル行のエントリのソース行にジャンプする
	vim.keymap.set("n", "<CR>", function()
		local entry = session.entry_at_cursor()
		if not entry then
			return
		end
		local win = session.find_src_win()
		if win then
			local target = entry.src_buf or S.src_buf
			if vim.api.nvim_win_get_buf(win) ~= target then
				S.src_buf = target
				vim.api.nvim_win_set_buf(win, target)
			end
			vim.api.nvim_set_current_win(win)
			vim.api.nvim_win_set_cursor(win, { entry.lnum, 0 })
			vim.cmd("normal! zt")
		end
	end, { buffer = buf, desc = "ToC: ソースへジャンプ" })

	-- R: ToC を手動リフレッシュする
	vim.keymap.set("n", "R", function()
		local new_entries = session.do_refresh()
		if #new_entries > 0 then
			vim.notify("ToC: 更新しました", vim.log.levels.INFO)
		end
	end, { buffer = buf, desc = "ToC: リフレッシュ" })

	-- e: カーソル行のエントリのタイトルをインプット編集する
	vim.keymap.set("n", "e", function()
		local entry, cursor_lnum = session.entry_at_cursor()
		if not entry then
			return
		end
		local new_title = vim.fn.input("タイトル: ", entry.title)
		if new_title == "" or new_title == entry.title then
			return
		end
		local target = entry.src_buf or S.src_buf
		local src_line = vim.api.nvim_buf_get_lines(target, entry.lnum - 1, entry.lnum, false)[1]
		local escaped = vim.pesc(S.marker)
		local new_line = src_line:gsub("^(" .. escaped .. "+%s+).+$", "%1" .. new_title)
		vim.api.nvim_buf_set_lines(target, entry.lnum - 1, entry.lnum, false, { new_line })
		session.do_refresh()
		pcall(vim.api.nvim_win_set_cursor, S.toc_win, { cursor_lnum, 0 })
	end, { buffer = buf, desc = "ToC: タイトル編集" })

	-- H/L: 棒グラフの横スクロール（棒が 30 本以上で表示される）
	if S.needs_hscroll and S.chart_win then
		vim.keymap.set("n", "H", function()
			vim.api.nvim_win_call(S.chart_win, function()
				vim.cmd("normal! 10zh")
			end)
		end, { buffer = buf, desc = "ToC: 棒グラフ左スクロール" })
		vim.keymap.set("n", "L", function()
			vim.api.nvim_win_call(S.chart_win, function()
				vim.cmd("normal! 10zl")
			end)
		end, { buffer = buf, desc = "ToC: 棒グラフ右スクロール" })
	end

	-- @ : ToC 幅指定（全角文字数 / +N増 / -N減）
	local function on_resize_toc()
		local input = vim.fn.input("幅(全角文字数): @")
		if input == "" then
			return
		end
		local current_width = vim.api.nvim_win_get_width(S.toc_win)
		local new_width
		local sign, num = input:match("^([+-])(%d+)$")
		if sign and num then
			local delta = tonumber(num) * 2
			new_width = sign == "+" and current_width + delta or current_width - delta
		else
			local abs = tonumber(input)
			if abs then
				new_width = abs * 2
			else
				vim.notify("ToC: 無効な入力（例: 30, +5, -5）", vim.log.levels.WARN)
				return
			end
		end
		new_width = math.max(20, math.min(new_width, vim.o.columns - cfg.src_min_width))
		S.toc_width = new_width
		vim.wo[S.toc_win].winfixwidth = false
		vim.api.nvim_win_set_width(S.toc_win, new_width)
		vim.wo[S.toc_win].winfixwidth = true
		session.do_refresh()
	end

	-- # : ソース幅指定（pad ウィンドウを使ってソース幅を狭める）
	local function on_resize_src()
		local input = vim.fn.input("ソース幅(全角文字数): #")
		if input == "" then
			return
		end
		local src_win = session.find_src_win()
		if not src_win then
			return
		end

		local current_src_width = vim.api.nvim_win_get_width(src_win)
		local new_src_width
		local sign, num = input:match("^([+-])(%d+)$")
		if sign and num then
			local delta = tonumber(num) * 2
			new_src_width = sign == "+" and current_src_width + delta or current_src_width - delta
		else
			local abs = tonumber(input)
			if abs then
				new_src_width = abs * 2
			else
				vim.notify("ToC: 無効な入力（例: 40, +5, -5）", vim.log.levels.WARN)
				return
			end
		end
		new_src_width = math.max(cfg.src_min_width, new_src_width)

		local toc_width = vim.api.nvim_win_get_width(S.toc_win)
		local available_for_src = vim.o.columns - toc_width
		if new_src_width >= available_for_src then
			-- pad が不要 → 閉じてソースを最大幅にする
			if S.pad_win and vim.api.nvim_win_is_valid(S.pad_win) then
				vim.api.nvim_win_close(S.pad_win, false)
				S.pad_win = nil
				S.pad_buf = nil
			end
			return
		end

		local pad_width = available_for_src - new_src_width - 1 -- -1 for separator
		if pad_width < 1 then
			if S.pad_win and vim.api.nvim_win_is_valid(S.pad_win) then
				vim.api.nvim_win_close(S.pad_win, false)
				S.pad_win = nil
				S.pad_buf = nil
			end
			return
		end

		-- pad バッファ・ウィンドウを作成または再利用する
		if not S.pad_buf or not vim.api.nvim_buf_is_valid(S.pad_buf) then
			S.pad_buf = vim.api.nvim_create_buf(false, true)
			vim.bo[S.pad_buf].buftype = "nofile"
			vim.bo[S.pad_buf].modifiable = false
		end

		if not S.pad_win or not vim.api.nvim_win_is_valid(S.pad_win) then
			-- ソースウィンドウの左に split して pad を配置する
			vim.api.nvim_set_current_win(src_win)
			vim.cmd("topleft vsplit")
			S.pad_win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_buf(S.pad_win, S.pad_buf)
			require("toc.util").setup_win_opts(S.pad_win)
			vim.wo[S.pad_win].cursorline = false
			vim.wo[S.pad_win].winfixwidth = true
			-- ToC ウィンドウにフォーカスを戻す
			vim.api.nvim_set_current_win(S.toc_win)
		end

		vim.api.nvim_win_set_width(S.pad_win, pad_width)
		vim.api.nvim_win_set_width(src_win, new_src_width)
		S.toc_width = vim.api.nvim_win_get_width(S.toc_win)
	end

	-- 全パネル共通のキーマップ（ToC・タイトル・棒グラフで共有）
	local shared_bufs = { buf }
	if S.title_buf then
		shared_bufs[#shared_bufs + 1] = S.title_buf
	end
	if S.chart_buf then
		shared_bufs[#shared_bufs + 1] = S.chart_buf
	end

	for _, b in ipairs(shared_bufs) do
		vim.keymap.set("n", "q", function()
			session.close()
		end, { buffer = b, desc = "ToC: 閉じる" })
		vim.keymap.set("n", "@", on_resize_toc, { buffer = b, desc = "ToC: 幅指定" })
		vim.keymap.set("n", "#", on_resize_src, { buffer = b, desc = "ToC: ソース幅指定" })
	end

	-- ?: ヘルプ表示
	vim.keymap.set("n", "?", function()
		local help = {
			"ToC キーバインド:",
			"  <CR>  ソースへジャンプ",
			"  e     タイトル編集",
			"  R     内容リフレッシュ",
			"  @N    ToC幅指定（全角N文字 / +N増 / -N減）",
			"  #N    ソース幅指定（全角N文字 / +N増 / -N減）",
			"  q     閉じる",
			"  ?     このヘルプ",
		}
		if S.needs_hscroll then
			help[#help + 1] = "  H/L   棒グラフ横スクロール"
		end
		help[#help + 1] = ""
		help[#help + 1] = "カーソル移動でソースが自動スクロール"
		vim.notify(table.concat(help, "\n"), vim.log.levels.INFO)
	end, { buffer = buf, desc = "ToC: ヘルプ" })

	-- タイトルバッファ固有: <CR> でソースウィンドウへ移動する
	if S.title_buf then
		vim.keymap.set("n", "<CR>", function()
			local win = session.find_src_win()
			if win then
				vim.api.nvim_set_current_win(win)
			end
		end, { buffer = S.title_buf, desc = "ToC: ソースウィンドウへ移動" })
	end
end

return M
