j
<h1>Raccコマンドリファレンス</h1>
e
<h1>Racc Command Reference</h1>
.
<p>
racc [-o<var>filename</var>] [--output-file=<var>filename</var>]
     [-e<var>rubypath</var>] [--embedded=<var>rubypath</var>]
     [-v] [--verbose]
     [-O<var>filename</var>] [--log-file=<var>filename</var>]
     [-g] [--debug]
     [-E] [--embedded]
     [-l] [--no-line-convert]
     [-c] [--line-convert-all]
     [-a] [--no-omit-actions]
     [-C] [--check-only]
     [-S] [--output-status]
     [--version] [--copyright] [--help] <var>grammarfile</var>
</p>

<dl>
<dt><var>filename</var>
<dd>
j
Raccの文法ファイルを指定します。拡張子には特に制限はありません。
e
Racc grammar file. Any extention is permitted.
.
</dd>
<dt>-o<var>outfile</var>, --output-file=<var>outfile</var>
<dd>
j
作成するクラスをかきこむファイル名を指定します。デフォルトは<filename>.tab.rbです。
e
A filename for output. default is &lt;filename&gt;.tab.rb
.
</dd>
<dt>-O<var>filename</var>, --log-file=<var>filename</var>
<dd>
j
-v オプションをつけた時に生成するログファイルの名前を
<var>filename</var> に変更します。
デフォルトは <var>filename</var>.output です。
e
Place logging output in file <var>filename</var>.
Default log file name is <var>filename</var>.output.
.
</dd>
<dt>-e<var>rubypath</var>, --executable=<var>rubypath</var>
<dd>
j
実行可能ファイルを生成します。<var>rubypath</var>は Ruby 本体のパスです。
<var>rubypath</var>を単に 'ruby' にした時には Racc が動作している
Ruby のパスを使用します。
e
output executable file(mode 755). <var>path</var> is a path of ruby interpreter.
.
</dd>
<dt>-v, --verbose
<dd>
j
ファイル "filename".output に詳細な解析情報を出力します。
e
verbose mode. create &lt;filename&gt;.output file, like yacc's y.output file.
.
</dd>
<dt>-g, --debug
<dd>
j
出力するコードにデバッグ用コードを加えます。-g をつけて生成したパーサで
@yydebug を true にセットすると、デバッグ用のコードが出力されます。<br>
-g をつけるだけでは何もおこりませんので注意してください。
e
add debug code to parser class. To display debuggin information,
use this '-g' option and set @yydebug true in parser class.
.
</dd>
<dt>-E, --embedded
<dd>
j
ランタイムルーチンをすべて含んだコードを生成します。
つまり、このオプションをつけて生成したコードは Ruby さえあれば動きます。
e
Output parser which doesn't need runtime files (racc/parser.rb).
.
</dd>
<dt>-C, --check-only
<dd>
j
(文法ファイルの) 文法のチェックだけをして終了します。
e
Check syntax of racc grammer file and quit.
.
</dd>
<dt>-S, --output-status
<dd>
j
進行状況を逐一報告します。
e
Print messages time to time while compiling.
.
</dd>
<dt>-l, --no-line-convert
<dd>
j
<p>
Ruby では例外が発生した時のファイル名や行番号を表示してくれますが、
Racc の生成したパーサは、デフォルトではこの場合のファイル名・行番号を
文法ファイルでのものに置きかえます。このフラグはその機能をオフにします。
</p>
<p>
ruby 1.4.3 以前のバージョンではバグのために定数の参照に失敗する
場合があるので、定数参照に関してなにかおかしいことがおこったらこのフラグを
試してみてください。
</p>
e
turns off line number converting.
.
</dd>
<dt>-c, --line-convert-all
<dd>
j
アクションと inner に加え header footer の行番号も変換します。
header と footer がつながっているような場合には使わないでください。
e
Convert line number of actions, inner, header and footer.
.
<dt>-a, --no-omit-actions
<dd>
j
全てのアクションに対応するメソッド定義と呼び出しを行います。
例えアクションが省略されていても空のメソッドを生成します。
e
Call all actions, even if an action is empty.
.
</dd>
<dt>--version
<dd>
j
Racc のバージョンを出力して終了します。
e
print Racc version and quit.
.
</dd>
<dt>--copyright
<dd>
j
著作権表示を出力して終了します。
e
Print copyright and quit.
.
<dt>--help
<dd>
j
オプションの簡単な説明を出力して終了します。
e
Print usage and quit.
.
</dd>
</dl>
