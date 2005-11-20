= NEWS

== 1.4.5 (2005-11-21)
j
  * [FEATURE CHANGE] --no-extensions オプションを削除
  * [fix] racc パッケージのみで -E を使えるように修正
  * [fix] --no-omit-actions が動作していなかったのを修正
  * setup.rb 3.4.1.
e
  * [FEATURE CHANGE] --no-extensions option was removed.
  * [fix] racc command should not depend on `raccrt' package.
  * [fix] --no-omit-actions did not work.
  * setup.rb 3.4.1.
.
== 1.4.4 (2003-10-12)
j
  * Ruby 1.8.0 に対応するリリース。本体に変更はなし
  * -all パッケージに strscan, amstd の同梱するのをやめた
  * setup.rb 3.2.1
e
  * document changed.
  * -all packages does not include amstd and strscan.
  * setup.rb 3.2.1.
.

== 1.4.3 (2002-11-14)
j
  * [fix] ruby 1.8 の警告を消した
e
  * [fix] reduce ruby 1.8 warnings.
.

== 1.4.2 (2002-01-29)
j
  * [new] 新しいオプション --no-extentions
e
  * [new] new option --no-extentions
.

== 1.4.1 (2001-12-02)
j
  * amstd 非依存になった (ただし -all パッケージへバンドルは継続)
  * y2racc racc2y を 1.4 対応にした
e
  * now Racc does not depend on amstd library.
  * update y2racc and racc2y for racc 1.4.1
.

== 1.4.0 (2001-11-30)
j
  * ランタイムを Ruby の CVS に入れたのにあわせてマイナーバージョンアップ
  * RaccParser, RaccScanner → GrammarFileParser, GrammarFileScanner
  * ハズい typo を修正 (grammer → grammar)
e
  * minor version up for checking in runtime library into ruby CVS repositry.
  * RaccParser, RaccScanner -&gt; GrammarFileParser, GrammarFileScanner
  * modify typo (grammer -&gt; grammar)
.

== 1.3.12 (2001-11-22)
j
  * インストーラのバグを修正 (thanks Tanaka Akira)
  * アクション中の正規表現や % 文字列、グローバル変数の検出を向上させた
e
  * modify installer bug (thanks Tanaka Akira)
  * enhance regexp/%-strings/gvar detection in action block
.

== 1.3.11 (2001-08-28)
j
  * アクション中の $' $` $/ などを正しくスキャン
e
  * modify scan error on $' $` $/ etc.
.

== 1.3.10 (2001-08-12)
j
  * cparse.c のプロトタイプ違いを直した
e
  * modify prototype missmatch in cparse.c
.

== 1.3.9 (2001-04-07)
j
  * Ruby 1.4 に(再び)対応した
e
  * support Ruby 1.4 again.
.

== 1.3.8 (2001-03-17)
j
  * パースエラーの時に記号名も出力するようにした
  * Racc::Parser#token_to_s
e
  * output symbol name when error
  * Racc::Parser#token_to_str
.

== 1.3.7 (2001-02-04)
j
  * サンプルを増やした
e
  * allow nil for EndOfInput (experimental)
  * more sample grammar files
.

== 1.3.6 (2001-01-22)
j
  * cparse がスタティックリンクされても動くようにした
e
  * modify cparse.so for static link
.

== 1.3.5 (2001-01-18)
j
  * % 文字列のスキャンがバグってた
  * 新しい命令 expect
e
  * %-string scanning was wrong
  * new directive "expect"
.

== 1.3.4 (2001-01-11)
j
  * cparse: シンボルのタイプチェックを入れた
  * cparse: depend を消した
  * cparse: rb_iterate 中の GC で落ちるバグを修正
e
  * cparse: add type checks
  * cparse: rm depend
  * cparse: does not pass non-VALUE object to rb_iterate()
.

== 1.3.3 (2000-12-25)
j
  * ジェネレータに致命的なバグ。1.3.1 から混入 (format.rb)
  * racc --runtime-version
e
  * <em>critical bug</em> in generator (from 1.3.1)
  * racc --runtime-version
.

== 1.3.2 (2000-12-21)
j
  * -E が失敗するのを直した
  * 再度 strscan を同梱 (y2racc/racc2y に必要)
e
  * bug with racc -E
  * package strscan togather (again)
.

== 1.3.1 (2000-12-17)
j
  * 正規表現の繰り返し指定の上限を動的に決定する (RE_DUP_MAX)
  * パースルーチンが常に Ruby 版になっていた (消し忘れ)
e
  * dynamically determine RE_DUP_MAX
  * ruby version routine was used always
.

== 1.3.0 (2000-11-30)
j
  * スキャナから yield でトークンを渡せるようになった
e
  * can yield(sym,val) from scanner (Parser#yyparse)
.

== 1.2.6 (2000-11-28)
j
  * class M::C を許した
e
  * class M::C
.

== 1.2.5 (2000-11-20)
j
  * オプションに大変動。非互換オプションは -h -f -p -i -n -c -A
  * ロングオプションをサポート
  * y2racc, racc2y はデフォルトでアクションを残すようにした
e
  * big changes in option; -h -f -p -i -n -c -A are incompatible
  * support long options
  * y2racc, racc2y leaves actions as default
.

== 1.2.4 (2000-09-13)
j
  * インストーラとドキュメントを更新
e
  * updates installer and documents
.

== 1.2.3 (2000-08-14)
j
  * 使われない規則と非終端記号を出力 (強力版)
  * S/R conflict の時 nonassoc で解決するならばエラー
e
  * output useless rules and nonterminals (version 2)
  * nonassoc makes error (never shift/reduce)
.

== 1.2.2 (2000-08-12)
j
  * 内部の変更
e
  * internal changes
.

== 1.2.1 (2000-08-05)
j
  * yacc との変換コマンド racc2y・y2racc を添付
e
  * racc2y, y2racc
.

== 1.2.0 (2000-08-02)
j
  * 先読みアルゴリズムを bison のものに変更
e
  * uses bison's lookahead algorithm
.

== 1.1.6 (2000-07-25)
j
  * 新たなキーワード options とその引数 no_result_var
e
  * new keyword "options" and its parameter "no_result_var"
.

== 1.1.5 (2000-07-21)
j
  * [重要] token を convert に変更
  * 「新たな」キーワード token (終端記号の宣言)
e
  * [IMPORTANT] change keyword "token" to "convert"
  * NEW keyword "token" for token declearation
.

== 1.1.4 (2000-07-13)
j
  * サンプルがバグってた
e
  * update installer
  * samples had bugs
.

== 1.1.3 (2000-06-30)
j
  * 空アクションの呼び出しを省略しないようにするオプション -a
e
  * new option -a; does not omit void action call
.

== 1.1.2 (2000-06-29)
j
  * スキャナで strscan を使わないようにした
  * ScanError -&gt; Racc::ScanError, ParseError -&gt; Racc::ParseError
  * エラーメッセージを強化
e
  * now racc does not use strscan.so
  * ScanError -&gt; Racc::ScanError, ParseError -&gt; Racc::ParseError
  * more friendly error messages
.

== 1.1.1 (2000-06-15)
j
  * requireミス (thanks Toshさん)
  * -v をつけるとconflictが報告されなくなっていた
e
  * require miss
  * conflicts were not reported with -v
.

== 1.1.0 (2000-06-12)
j
  * 新しい 状態遷移表生成アルゴリズム
e
  * use other algolithm for generating state table
.

== 1.0.4 (2000-06-04)
j
  * S/R conflict がおきると .output 出力で落ちるバグ修正 (Tosh さんの報告)
  * 使われない非終端記号・規則を表示
e
  * S/R conflict & -v flag causes unexpected exception (reported by Tosh)
  * output useless nonterminals/rules
.

== 1.0.3 (2000-06-03)
j
  * filter -&gt; collect!
e
  * use Array#collect! instead of #filter.
.

== 1.0.2 (2000-05-16)
j
  * インストーラをアップデート
e
  * update installer (setup.rb)
.

== 1.0.1 (2000-05-12)
j
  * state.rb:  先読みルーチンをちょっとだけ高速化 && 追加デバッグ
  * コードを整理した。著作権表示全体を全部のファイルにつけた。
  * amstd アップデート (1.7.0)
e
  * state.rb:  faster lookahead & debug lalr code
  * refine code
  * update amstd package (1.7.0)
.

== 1.0.0 (2000-05-06)
j
  * バージョン 1.0
e
  * version 1.0
.

== 0.14.6 (2000-05-05)
j
  * デバッグ出力を詳細にした
e
  * much more debug output
.

== 0.14.5 (2000-05-01)
j
  * インストーラを ruby 1.4.4 系の新しいパスに対応させた
e
.

== 0.14.4 (2000-04-09)
j
  * パーサの定数を削減(Racc_arg にまとめた)
  * state 生成を微妙に高速化(コアを文字列に変換)
e
  * Racc_* are included in Racc_arg
  * faster state generation (a little)
.

== 0.14.3 (2000-04-04)
j
  * cparse の SYM2ID と ID2SYM のチェックを分離 (thanks 小松さん)
e
  * check both of SYM2ID and ID2SYM (thanks Katsuyuki Komatsu)
.

== 0.14.2 (2000-04-03)
j
  * 一行目の class がパースエラーになっていた (thanks 和田さん)
  * 新しいフラグ racc -V
e
  * "class" on first line causes parse error (thanks Yoshiki Wada)
  * new option "racc -V"
.

== 0.14.1 (2000-03-31)
j
e
.

== 0.14.0 (2000-03-21)
j
  * 高速テーブルを実装
  * 一時的にファイル名/行番号の変換をやめた(Rubyのバグのため。)
e
  * implement "fast" table (same to bison)
  * stop line no. conversion temporaliry because of ruby bug
.

== 0.13.1 (2000-03-21)
j
  * --version --copyright などがうまく働いてなかった (thanks ふなばさん)
e
  * racc --version --copyright did not work (thanks Tadayoshi Funaba)
.

== 0.13.0 (2000-03-20)
j
  * yyerror/yyerrok/yyaccept を実装
e
  * implement yyerror/yyerrok/yyaccept
.

== 0.12.2 (2000-03-19)
j
  * -E フラグがバグってた (thanks ふなばさん)
e
  * -E flag had bug
.

== 0.12.1 (2000-03-16)
j
  * デフォルトアクションの決め方をちょっと修正(元に戻しただけ)
e
  * modify the way to decide default action
.

== 0.12.0 (2000-03-15)
j
  * 完全な LALR を実装したら遅くなったので SLR も併用するようにした。効果絶大。
e
  * implement real LALR
  * use both SLR and LALR to resolve conflicts
.

== 0.11.3 (2000-03-09)
j
  * 状態遷移表生成のバグの修正がまだ甘かった。さらに別のバグもあるようだ。
e
  * modify lookahead routine again
.

== 0.11.2 (2000-03-09)
j
  * cparse が Symbol に対応できてなかった
e
  * bug in lookahead routine
  * modify cparse.so for Symbol class of ruby 1.5
.

== 0.11.1 (2000-03-08)
j
  * ruby 1.5 の Symbol に対応
  * strscan を最新に
e
  * modify for Symbol
  * update strscan
.

== 0.11.0 (2000-02-19)
j
  * 例外のとき、元のファイルの行番号が出るようにした
e
  * if error is occured in action, ruby print line number of grammar file
.

== 0.10.9 (2000-01-19)
j
  * セットアップ方法など細かな変更
e
  * change package/setup
.

== 0.10.8 (2000-01-03)
j
  * 忘れてしまったけどたしかインストーラ関係の修正
  * (1/17 repacked) ドキュメントの追加と修正
e
  * (1-17 re-packed) add/modify documents
.

== 0.10.7 (2000-01-03)
j
  * setup.rb compile.rb amstd/inst などのバグ修正
e
  * modify setup.rb, compile.rb, amstd/inst. (thanks: Koji Arai)
.

== 0.10.6 (1999-12-24)
j
  * racc -e ruby でデフォルトパスを使用
  * 空のアクションの呼びだしは省略するようにした
e
  * racc -e ruby
  * omit void action call
.

== 0.10.5 (1999-12-21)
j
  * 埋めこみアクションの実装がすさまじくバグってた
  * setup.rb が inst.rb の変化に追従してなかった
  * calc.y calc2.y を 0.10 用に修正
e
  * critical bug in embedded action implement
  * bug in setup.rb
  * modify calc[2].y for 0.10
.

== 0.10.4 (1999-12-19)
j
  * エラー回復モードを実装
  * racc -E で単体で動作するパーサを生成
  * Racc は class から module になった
e
  * support error recover ('error' token)
  * can embed runtime by "racc -E"
  * Racc is module
.

== 0.10.3 (1999-12-01)
j
  * 埋めこみアクションをサポート
  * .output の出力内容にバグがあったのを修正
e
  * support embedded action
  * modify .output bug
.

== 0.10.2 (1999-11-27)
j
  * ドキュメントの訂正と更新
  * libracc.rb を分割
e
  * update document
  * separate libracc.rb
.

== 0.10.1 (1999-11-19)
j
  * C でランタイムを書きなおした
  * next_token が false を返したらもう読みこまない
  * アクションがトークンによらず決まるときは next_token を呼ばない
  * $end 廃止
  * LALRactionTable
e
  * rewrite runtime routine in C
  * once next_token returns [false, *], not call next_token
  * action is only default, not call next_token
  * $end is obsolute
  * LALRactionTable
.

== 0.10.0 (1999-11-06)
j
  * next_* を next_token に一本化、peep_token 廃止
  * @__debug__ -&lt; @yydebug など変数名を大幅変更
  * 文法ファイルの構造が class...rule...end に変わった
  * コアのコードを一新、高速化
  * strscan を併合
  * ライブラリを racc/ ディレクトリに移動
e
  * next_value, peep_token is obsolute
  * @__debug__ -&gt; @yydebug
  * class...rule...end
  * refine libracc.rb
  * unify strscan library
  * *.rb are installed in lib/ruby/VERSION/racc/
.

== 0.9.5 (1999-10-03)
j
  * 0.9.4 の変更がすごくバグってた
  * $end が通らなかったのを修正
  * __show_stack__ の引数が違ってた
e
  * too few arguments for __show_stack__
  * could not scan $end
  * typo in d.format.rb
.

== 0.9.4 (1999-09-??)
j
  * Parser::Reporter をなくしてメソッドに戻した
  * d.format.rb を再編成
e
.

== 0.9.3 (1999-09-03)
j
  * racc.rb -> racc
e
.

== 0.9.2 (1999-06-26)
j
  * strscan使用
e
.

== 0.9.1 (1999-06-08)
j
  * アクション中の正規表現に対応 ( /= にも注意だ)
  * アクション中の # コメントに対応
e
.

== 0.9.0 (1999-06-03)
j
  * アクションを { } 形式にした
  * ユーザーコードを '----' を使う形式にした
e
.

== 0.8.11 (?)
j
  * -g の出力をわかりやすくした
e
.

== 0.8.10 (?)
j
  * アクションからreturnできるようにした
e
.

== 0.8.9 (1999-03-21)
j
  * -g + @__debug__をつかったデバッグメッセージ操作
  * エラー発生時のバグを修正
  * TOKEN_TO_S_TABLEを付加するようにした
e
.

== 0.8.8 (1999-03-20)
j
  * 100倍程度の高速化
  * defaultトークンを加えた
  * デバッグ用ソースを出力するオプション-gをくわえた
  * user_initializeを廃止し、普通にinitializeを使えるようにした
  * parse_initialize/finalize,parseメソッドを廃止
  * next_token,next_value,peep_tokenのデフォルトを廃止
  * %precと同等の機能を加えた
e
.

== 0.8.7 (1999-03-01)
j
  * 内部構造が大幅に変化
  * マニュアルがHTMLになった
e
.

== 0.8.0 (1999-01-16)
j
  * 文法がブロック型に変化
e
.

== 0.5.0 (1999-01-07)
j
  * 演算子優先順位が実装されたようだ
  * スタート規則が実装されたようだ
  * トークン値の置換が実装されたようだ(後に致命的なバグ発見)
e
.

== 0.1.0 (1999-01-01)
j
  * とにかく動くようになった
e
.
