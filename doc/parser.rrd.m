= class Racc::Parser
j
Racc の生成するパーサはすべて Racc::Parser クラスを継承します。
Racc::Parser クラスにはパース中に使用するメソッドがいくつかあり、
そのようなメソッドをオーバーロードすると、パーサを初期化したり
することができます。
.

== Super Class

Object

j
== Constants

プリフィクス "Racc_" がついた定数はパーサの予約定数です。
そのような定数は使わないでください。動作不可能になります。
.
== Instance Methods
j
ここに載っているもののほか、プリフィクス "racc_" および "_racc_" が
ついたメソッドはパーサの予約名です。そのようなメソッドは使わないで
ください。
.

: do_parse -> Object
j
    パースを開始します。
    また、トークンが必要になった時は #next_token を呼び出します。
e
    The entry point of parser. This method is used with #next_token.
    If Racc wants to get token (and its value), calls next_token.
.

      --
      # Example
      ---- inner
        def parse
          @q = [[1,1],
                [2,2],
                [3,3],
                [false, '$']]
          do_parse
        end

        def next_token
          @q.shift
        end
      --

: next_token -> [Symbol, Object]
    [abstract method]

j
    パーサが次のトークンを読みこむ時に使います。
    [記号, その値] の形式の配列を返してください。
    記号はデフォルトでは

      * 文法中、引用符でかこまれていないもの
        → その名前の文字列のシンボル (例えば :ATOM )
      * 引用符でかこまれているもの<br>
        → その文字列そのまま (例えば '=' )

    で表します。これを変更する方法については、
    文法リファレンスを参照してください。

    また、もう送るシンボルがなくなったときには 
    [false, なにか] または nil を返してください。

    このメソッドは抽象メソッドなので、#do_parse を使う場合は
    必ずパーサクラス中で再定義する必要があります。
    定義しないままパースを始めると例外 NotImplementedError が
    発生します。
e
    The method to fetch next token.  If you use #do_parse method,
    you must implement #next_token.  The format of return value is
    [TOKEN_SYMBOL, VALUE].  token-symbol is represented by Ruby's symbol
    by default, e.g. :IDENT for 'IDENT'.  ";" (String) for ';'.

    The final symbol (End of file) must be false.
.

: yyparse( receiver, method_id )
j
    パースを開始します。このメソッドでは始めてトークンが
    必要になった時点で receiver に対して method_id メソッドを
    呼び出してトークンを得ます。

    receiver の method_id メソッドはトークンを yield しなければ
    なりません。形式は #next_token と同じで [記号, 値] です。
    つまり、receiver の method_id メソッドの概形は以下のように
    なるはずです。
      --
      def method_id
        until end_of_file
              :
          yield 記号, 値
              :
        end
      end
      --
    少し注意が必要なのは、method_id が呼び出されるのは始めて
    トークンが必要になった時点であるということです。method_id
    メソッドが呼び出されたときは既にパースが進行中なので、
    アクション中で使う変数を method_id の冒頭で初期化すると
    まず失敗します。

    トークンの終端を示す [false, なにか] を渡したらそれ以上は 
    yield しないでください。その場合には例外が発生します。

    最後に、method_id メソッドからは必ず yield してください。
    しない場合は何が起きるかわかりません。
e
    The another entry point of parser.
    If you use this method, you must implement RECEIVER#METHOD_ID method.

    RECEIVER#METHOD_ID is a method to get next token.
    It must 'yield's token, which format is [TOKEN-SYMBOL, VALUE].
.

: on_error( error_token_id, error_value, value_stack )
j
    パーサコアが文法エラーを検出すると呼び出します (yacc の yyerror)。
    エラーメッセージを出すなり、例外を発生するなりしてください。
    このメソッドから正常に戻った場合、パーサはエラー回復モード
    に移行します。

    error_token はパースエラーを起こした記号の内部表現 (整数) です。
    #token_to_str で文法ファイル上の文字列表現に直せます。

    error_value はその値です。

    value_stack はエラーの時点での値スタックです。
    value_stack を変更してはいけません。

    on_error のデフォルトの実装は例外 ParseError を発生します。
e
    This method is called when parse error is found.

    ERROR_TOKEN_ID is an internal ID of token which caused error.
    You can get string replesentation of this ID by calling
    #token_to_str.

    ERROR_VALUE is a value of error token.

    value_stack is a stack of symbol values.
    DO NOT MODIFY this object.

    This method raises ParseError by default.

    If this method returns, parsers enter "error recovering mode".
.

: token_to_str( t ) -> String
j
    Racc トークンの内部表現 (整数)
    を文法ファイル上の記号表現の文字列に変換します。

    t が整数でない場合は TypeError を発生します。
    t が範囲外の整数だった場合は nil を返します。
e
    Convert internal ID of token symbol to the string.
.

: yyerror
j
    エラー回復モードに入ります。このとき #on_error は呼ばれません。
    アクション以外からは呼び出さないでください。
e
    Enter error recovering mode.
    This method does not call #on_error.
.

: yyerrok
j
    エラー回復モードから復帰します。
    アクション以外からは呼び出さないでください。
e
    Leave error recovering mode.
.

: yyaccept
j
    すぐに値スタックの先頭の値を返して #do_parse、#yyparse を抜けます。
e
    Exit parser.
    Return value is Symbol_Value_Stack[0].
.
