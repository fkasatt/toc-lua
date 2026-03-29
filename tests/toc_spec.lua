local assert = require("luassert")
local h = require("tests.helpers")

describe("ToC module", function()
	local toc

	before_each(function()
		-- toc.* モジュールをすべてリセットしてフレッシュな状態でテストする
		for k in pairs(package.loaded) do
			if k:match("^toc") then
				package.loaded[k] = nil
			end
		end
		toc = require("toc")
	end)

	after_each(function()
		pcall(vim.api.nvim_del_augroup_by_name, "toc_scroll_sync")
		h.close_extra_wins()
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "nofile" then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
	end)

	local function find_toc_buf()
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			local ok, ft = pcall(function()
				return vim.bo[b].filetype
			end)
			if ok and ft == "toc" then
				return b
			end
		end
		return nil
	end

	local function find_toc_win(toc_buf)
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(win) == toc_buf then
				return win
			end
		end
		return nil
	end

	describe("markdown", function()
		it("#, ##, ### の全レベルのヘッダーを検出してToCを生成する", function()
			local buf = h.scratch_buf({
				"# ドキュメントタイトル",
				"",
				"## 第1章",
				"ここは第1章の内容です。",
				"日本語テキストの例文。",
				"",
				"### セクション1.1",
				"セクション1.1の内容。",
				"",
				"## 第2章",
				"第2章の短い内容。",
			}, "markdown")

			toc.open()

			local toc_buf = find_toc_buf()
			assert.is_not_nil(toc_buf, "ToCバッファが作成されていない")

			local lines = h.buf_lines(toc_buf)
			assert.equals(4, #lines, "エントリ数が4（#×1 + ##×2 + ###×1）であること")

			-- レベル1タイトル（headlessモードではウィンドウ幅が狭く切り詰められるため前半部分でマッチ）
			assert.is_truthy(lines[1]:match("ドキュメント"), "1行目にレベル1タイトル")
			assert.is_truthy(lines[1]:match("字"), "1行目に文字数表示がある")

			-- レベル2
			assert.is_truthy(lines[2]:match("第1章"), "2行目に第1章")

			-- レベル3
			assert.is_truthy(lines[3]:match("セクション1.1"), "3行目にセクション1.1")

			-- 第2章
			assert.is_truthy(lines[4]:match("第2章"), "4行目に第2章")

			h.cleanup_buf(buf)
		end)

		it("ヘッダーが全くない場合はToCを表示しない", function()
			local buf = h.scratch_buf({
				"本文だけのファイル",
				"ヘッダーなし",
			}, "markdown")

			toc.open()

			local toc_buf = find_toc_buf()
			assert.is_nil(toc_buf, "ヘッダーがない場合ToCバッファは作成されない")
			h.cleanup_buf(buf)
		end)
	end)

	describe("typst", function()
		it("=, ==, === の全レベルのヘッダーを検出する", function()
			local buf = h.scratch_buf({
				"= ドキュメント",
				"",
				"== はじめに",
				"導入文のテキスト。",
				"",
				"=== 背景",
				"背景の説明文。",
				"",
				"== 方法",
				"方法の説明。",
			}, "typst")

			toc.open()

			local toc_buf = find_toc_buf()
			assert.is_not_nil(toc_buf, "ToCバッファが作成されている")

			local lines = h.buf_lines(toc_buf)
			assert.equals(4, #lines, "エントリ数が4（=×1 + ==×2 + ===×1）")
			assert.is_truthy(lines[1]:match("ドキュメント"), "1行目にドキュメントタイトル")

			h.cleanup_buf(buf)
		end)
	end)

	describe("txt", function()
		it("+, ++, +++ の全レベルのヘッダーを検出する", function()
			local buf = h.scratch_buf({
				"+ メモ",
				"",
				"++ セクションA",
				"内容A",
				"",
				"+++ サブA1",
				"サブ内容",
				"",
				"++ セクションB",
				"内容B",
			}, "text")

			toc.open()

			local toc_buf = find_toc_buf()
			assert.is_not_nil(toc_buf, "ToCバッファが作成されている")

			local lines = h.buf_lines(toc_buf)
			assert.equals(4, #lines, "エントリ数が4（+×1 + ++×2 + +++×1）")

			h.cleanup_buf(buf)
		end)
	end)

	describe("非対応filetype", function()
		it("luaファイルではToCを表示しない", function()
			local buf = h.scratch_buf({
				"-- コメント",
				"local M = {}",
			}, "lua")

			toc.open()

			local toc_buf = find_toc_buf()
			assert.is_nil(toc_buf, "lua filetypeではToCバッファは作成されない")
			h.cleanup_buf(buf)
		end)
	end)

	describe("文字数計算", function()
		it("日本語を含むテキストの文字数が正しく計算される", function()
			local buf = h.scratch_buf({
				"## テスト章",
				"あいうえお", -- 5文字
				"かきくけこ", -- 5文字
			}, "markdown")

			toc.open()

			local toc_buf = find_toc_buf()
			assert.is_not_nil(toc_buf)
			local lines = h.buf_lines(toc_buf)
			assert.is_truthy(lines[1]:match("%[10字%]"), "文字数が10字と表示される")

			h.cleanup_buf(buf)
		end)
	end)

	describe("コードフェンス内の見出し除外", function()
		it("コードブロック内の見出しマーカーは無視される", function()
			local buf = h.scratch_buf({
				"# 章タイトル",
				"通常テキスト",
				"```",
				"# これはコードブロック内",
				"## これも除外",
				"```",
				"## セクション",
			}, "markdown")

			toc.open()

			local toc_buf = find_toc_buf()
			assert.is_not_nil(toc_buf)

			local lines = h.buf_lines(toc_buf)
			assert.equals(2, #lines, "コードフェンス内の見出しを除いて2エントリ")
			assert.is_truthy(lines[1]:match("章タイトル"), "1行目に章タイトル")
			assert.is_truthy(lines[2]:match("セクション"), "2行目にセクション")

			h.cleanup_buf(buf)
		end)
	end)

	describe("ツリー表示", function()
		it("罫線記号でレベルの系統関係が表現される", function()
			local buf = h.scratch_buf({
				"# タイトル",
				"## 章A",
				"内容A",
				"### 節A1",
				"内容A1",
				"### 節A2",
				"内容A2",
				"## 章B",
				"内容B",
			}, "markdown")

			toc.open()

			local toc_buf = find_toc_buf()
			assert.is_not_nil(toc_buf)

			local lines = h.buf_lines(toc_buf)
			-- レベル2は├─ または └─ で始まる
			assert.is_truthy(
				lines[2]:match("├─") or lines[2]:match("└─"),
				"レベル2にツリー罫線がある"
			)

			-- レベル3は│ + ├─ または │ + └─ を含む
			assert.is_truthy(
				lines[4]:match("├─") or lines[4]:match("└─"),
				"レベル3にツリー罫線がある"
			)

			h.cleanup_buf(buf)
		end)
	end)

	describe("ハイライト", function()
		it("ToCバッファにハイライトが適用されている", function()
			local buf = h.scratch_buf({
				"# タイトル",
				"## 章",
				"内容",
			}, "markdown")

			toc.open()

			local toc_buf = find_toc_buf()
			assert.is_not_nil(toc_buf)

			local toc_ns = vim.api.nvim_create_namespace("toc_highlight")
			local extmarks = vim.api.nvim_buf_get_extmarks(toc_buf, toc_ns, 0, -1, { details = true })
			assert.is_true(#extmarks > 0, "ハイライト用のextmarkが存在する")

			h.cleanup_buf(buf)
		end)
	end)

	describe("UIレイアウト", function()
		it("ウィンドウが作成され適切な設定がされる", function()
			local buf = h.scratch_buf({
				"## テスト",
				"内容",
			}, "markdown")

			local win_count_before = #vim.api.nvim_list_wins()
			toc.open()
			local win_count_after = #vim.api.nvim_list_wins()

			-- toc_win + title_win の2ウィンドウが追加される
			assert.equals(win_count_before + 2, win_count_after, "ウィンドウが2つ増える（toc_win + title_win）")

			local toc_buf = find_toc_buf()
			local toc_win = find_toc_win(toc_buf)
			assert.is_not_nil(toc_win)
			assert.is_false(vim.wo[toc_win].number, "行番号が非表示")
			assert.is_true(vim.wo[toc_win].cursorline, "カーソルラインが有効")
			assert.is_false(vim.wo[toc_win].spell, "スペルチェック無効")

			h.cleanup_buf(buf)
		end)
	end)

	describe("リフレッシュ", function()
		it("Rキーでソース変更がToCに反映される", function()
			local buf = h.scratch_buf({
				"## 章A",
				"内容A",
			}, "markdown")

			toc.open()

			local toc_buf = find_toc_buf()
			assert.is_not_nil(toc_buf)

			-- ソースバッファに章を追加
			vim.api.nvim_buf_set_lines(buf, 2, 2, false, { "## 章B", "内容B" })

			-- ToCウィンドウでRキーを実行
			local toc_win = find_toc_win(toc_buf)
			vim.api.nvim_set_current_win(toc_win)
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("R", true, false, true), "mx", false)

			local lines = h.buf_lines(toc_buf)
			assert.equals(2, #lines, "リフレッシュ後にエントリが2つになる")
			assert.is_truthy(lines[2]:match("章B"), "新しい章Bが含まれる")

			h.cleanup_buf(buf)
		end)
	end)

	describe("ジャンプ", function()
		it("ToCバッファでEnterを押すとソース行にジャンプする", function()
			local buf = h.scratch_buf({
				"# タイトル",
				"",
				"## 第1章",
				"内容1",
				"",
				"## 第2章",
				"内容2",
			}, "markdown")

			toc.open()

			local toc_buf = find_toc_buf()
			assert.is_not_nil(toc_buf)

			local toc_win = find_toc_win(toc_buf)
			assert.is_not_nil(toc_win)

			-- ToCバッファの3行目にカーソルを移動（「第2章」）
			vim.api.nvim_set_current_win(toc_win)
			vim.api.nvim_win_set_cursor(toc_win, { 3, 0 })

			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "mx", false)

			-- ソースバッファのウィンドウでカーソルが6行目（## 第2章）にあることを確認
			local src_win = nil
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				if vim.api.nvim_win_get_buf(win) == buf then
					src_win = win
					break
				end
			end

			if src_win then
				local cursor = vim.api.nvim_win_get_cursor(src_win)
				assert.equals(6, cursor[1], "カーソルが6行目（## 第2章）にある")
			end

			h.cleanup_buf(buf)
		end)
	end)

	describe("typst #include", function()
		local tmpdir
		local root_path
		local inc1_path
		local inc2_path

		before_each(function()
			-- 一時ディレクトリにテスト用typstファイルを作成
			tmpdir = vim.fn.tempname()
			vim.fn.mkdir(tmpdir, "p")
			vim.fn.mkdir(tmpdir .. "/sub", "p")

			inc1_path = tmpdir .. "/chapter1.typ"
			inc2_path = tmpdir .. "/sub/chapter2.typ"
			root_path = tmpdir .. "/main.typ"

			-- インクルードファイル1
			local f1 = io.open(inc1_path, "w")
			f1:write("= 第1章\n\n== はじめに\n導入文。\n\n== 方法\n方法の説明。\n")
			f1:close()

			-- インクルードファイル2（サブディレクトリ）
			local f2 = io.open(inc2_path, "w")
			f2:write("= 第2章\n\n== 結果\n結果の説明。\n")
			f2:close()

			-- ルートファイル
			local fr = io.open(root_path, "w")
			fr:write("#set document(title: [テスト文書])\n\n")
			fr:write('#include "chapter1.typ"\n\n')
			fr:write('#include "sub/chapter2.typ"\n')
			fr:close()
		end)

		after_each(function()
			vim.fn.delete(tmpdir, "rf")
		end)

		it("includeファイルのヘッダーがToCに表示される", function()
			vim.cmd("edit " .. root_path)
			local buf = vim.api.nvim_get_current_buf()

			toc.open()

			local toc_buf = find_toc_buf()
			assert.is_not_nil(toc_buf, "ToCバッファが作成されている")

			local lines = h.buf_lines(toc_buf)
			-- エントリ: 第1章(=), はじめに(==), 方法(==), 第2章(=), 結果(==) = 5エントリ
			-- タイトルバッファは別ウィンドウなので toc_buf の行数 = エントリ数
			assert.equals(5, #lines, "includeファイルのエントリも含めて5つ")

			assert.is_truthy(lines[1]:match("第1章"), "1番目: 第1章")
			assert.is_truthy(lines[2]:match("はじめに"), "2番目: はじめに")
			assert.is_truthy(lines[3]:match("方法"), "3番目: 方法")
			assert.is_truthy(lines[4]:match("第2章"), "4番目: 第2章")
			assert.is_truthy(lines[5]:match("結果"), "5番目: 結果")

			h.cleanup_buf(buf)
		end)

		it("include順にエントリがインターリーブされる", function()
			-- ルートファイルにもヘッダーを追加
			local fr = io.open(root_path, "w")
			fr:write("#set document(title: [テスト文書])\n")
			fr:write("= 前書き\n前書き内容。\n\n")
			fr:write('#include "chapter1.typ"\n\n')
			fr:write("= 中間\n中間内容。\n\n")
			fr:write('#include "sub/chapter2.typ"\n')
			fr:write("= 後書き\n後書き内容。\n")
			fr:close()

			vim.cmd("edit! " .. root_path)
			local buf = vim.api.nvim_get_current_buf()

			toc.open()

			local toc_buf = find_toc_buf()
			assert.is_not_nil(toc_buf)

			local lines = h.buf_lines(toc_buf)
			-- エントリ: 前書き, 第1章, はじめに, 方法, 中間, 第2章, 結果, 後書き = 8
			assert.equals(8, #lines, "ルート+includeで8エントリ")

			-- 順序確認
			assert.is_truthy(lines[1]:match("前書き"), "1番目: 前書き")
			assert.is_truthy(lines[2]:match("第1章"), "2番目: 第1章")
			assert.is_truthy(lines[5]:match("中間"), "5番目: 中間")
			assert.is_truthy(lines[6]:match("第2章"), "6番目: 第2章")
			assert.is_truthy(lines[8]:match("後書き"), "8番目: 後書き")

			h.cleanup_buf(buf)
		end)

		it(
			"ToCでincludeファイルのエントリに移動するとソースバッファが切り替わる",
			function()
				vim.cmd("edit " .. root_path)
				local root_buf = vim.api.nvim_get_current_buf()
				local src_win = vim.api.nvim_get_current_win()

				toc.open()

				local toc_buf = find_toc_buf()
				assert.is_not_nil(toc_buf)

				local toc_win = find_toc_win(toc_buf)
				assert.is_not_nil(toc_win)

				-- ToCの1行目（第1章）に移動
				vim.api.nvim_set_current_win(toc_win)
				vim.api.nvim_win_set_cursor(toc_win, { 1, 0 })
				-- 初回 CursorMoved は suppress_scroll で抑制されるため 2 回発火する
				vim.api.nvim_exec_autocmds("CursorMoved", { buffer = toc_buf })
				vim.api.nvim_exec_autocmds("CursorMoved", { buffer = toc_buf })

				-- ソースウィンドウのバッファが chapter1.typ に変わっている
				local shown_buf = vim.api.nvim_win_get_buf(src_win)
				local shown_name = vim.api.nvim_buf_get_name(shown_buf)
				assert.is_truthy(
					shown_name:match("chapter1%.typ$"),
					"ソースウィンドウが chapter1.typ を表示: " .. shown_name
				)

				-- 2行目（はじめに）でEnter → ジャンプ
				vim.api.nvim_set_current_win(toc_win)
				vim.api.nvim_win_set_cursor(toc_win, { 2, 0 })
				vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "mx", false)

				-- ジャンプ後はソースウィンドウにフォーカスが移る
				local cur_win = vim.api.nvim_get_current_win()
				local jumped_buf = vim.api.nvim_win_get_buf(cur_win)
				local jumped_name = vim.api.nvim_buf_get_name(jumped_buf)
				assert.is_truthy(
					jumped_name:match("chapter1%.typ$"),
					"Enterジャンプ後も chapter1.typ を表示: " .. jumped_name
				)

				-- カーソルが「はじめに」の行（3行目）にある
				local cursor = vim.api.nvim_win_get_cursor(cur_win)
				assert.equals(3, cursor[1], "カーソルが3行目（== はじめに）にある")

				h.cleanup_buf(root_buf)
			end
		)

		it("存在しないincludeファイルは無視される", function()
			local fr = io.open(root_path, "w")
			fr:write("= タイトル\n内容。\n\n")
			fr:write('#include "nonexistent.typ"\n\n')
			fr:write("== セクション\nセクション内容。\n")
			fr:close()

			vim.cmd("edit! " .. root_path)
			local buf = vim.api.nvim_get_current_buf()

			toc.open()

			local toc_buf = find_toc_buf()
			assert.is_not_nil(toc_buf)

			local lines = h.buf_lines(toc_buf)
			-- エントリ2つ（タイトル + セクション）= 2行
			assert.equals(2, #lines, "存在しないincludeは無視されエントリは2つ")

			h.cleanup_buf(buf)
		end)
	end)
end)
