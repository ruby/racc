/*----------------------------------------------------

  parse.y -

  $Author$
  $Date$
  created at: Fri May 28 18:02:42 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto


  e.racc.y

  modified for racc

     1999/01/17 Minero Aoki.


 changes for token

tCONSTANT     -> tIDENTIFIER
tFLOAT        -> tNUM
tINTEGER      -> tNUM
numeric       -> tNUM
ret_args      -> call_args
resword       -> tRESWORD
op            -> tFNAME_OP
opt_call_args -> opt_call_args
mlhs_entry    -> mlhs

tFNAME_OP
tRESWORD  -> tFNAME_OP

tNUM
tREGEXP
tSTRING
tDSTRING
tXSTRING
tDXSTRING
tDREGEXP  -> tOBJECT

-------------------------------------------------------*/


class RaccParser


# precedence table

preclow

  left     kIF_MOD kUNLESS_MOD kWHILE_MOD kUNTIL_MOD
  left     kOR kAND
  right    kNOT
  nonassoc kDEFINED
  right    '=' tOP_ASGN
  right    '?' ':'
  nonassoc tDOT2 tDOT3
  left     tOROP
  left     tANDOP
  nonassoc tCMP tEQ tEQQ tNEQ tMATCH tNMATCH
  left     '>' tGEQ '<' tLEQ
  left     '|' '^'
  left     '&'
  left     tLSHFT tRSHFT
  left     '+' '-'
  left     '*' '/' '%'
  right    '!' '~' tUPLUS tUMINUS
  right    tPOW

prechigh


###################### rule ####################################

rule


compstmt        : stmts opt_terms ;

stmts           :
                | stmt
                | stmts terms stmt
                ;

stmt            : iterator iter_do_block
                | kALIAS fname mode_fname fname
                | kALIAS tGVAR tGVAR
                | kALIAS tGVAR tBACK_REF
                | kUNDEF undef_list
                | stmt kIF_MOD expr
                | stmt kUNLESS_MOD expr
                | stmt kWHILE_MOD expr
                | stmt kUNTIL_MOD expr
                | klBEGIN '{' compstmt '}'
                | klEND '{' compstmt '}'
                | expr
                ;

expr            : mlhs '=' mrhs
                | kRETURN call_args
                | kYIELD call_args
                | command_call
                | expr kAND expr
                | expr kOR expr
                | kNOT expr
                | '!' command_call
                | arg
                ;

command_call    : operation call_args
                | primary '.' operation call_args
                | primary tCOLON2 operation call_args
                | kSUPER call_args
                ;

mlhs            : mlhs_basic
                | tLPAREN mlhs ')'
                ;

mlhs_basic      : mlhs_head
                | mlhs_head tSTAR lhs
                | mlhs_head mlhs_tail
                | mlhs_head mlhs_tail ',' tSTAR lhs
                | tSTAR lhs
                ;

mlhs_item       : lhs
                | tLPAREN mlhs ')'
                ;

mlhs_head       : mlhs_item ',' ;

mlhs_tail       : mlhs_item
                | mlhs_tail ',' mlhs_item
                ;

lhs             : variable
                | primary '[' opt_call_args ']'
                | primary '.' tIDENTIFIER
                | backref
                ;

fname           : tIDENTIFIER
                | tFID
                | tFNAME_OP
								.
								  @scanner.mode = :EXPR_END
								.
                ;

undef_list      : fname
                | undef_list ',' mode_fname fname
                ;


arg             : variable '=' arg
                | primary '[' opt_call_args ']' '=' arg
                | primary '.' tIDENTIFIER '=' arg
                | backref '=' arg
                | variable tOP_ASGN arg
                | primary '[' opt_call_args ']' tOP_ASGN arg
                | primary '.' tIDENTIFIER tOP_ASGN arg
                | backref tOP_ASGN arg
                | arg tARG_OP arg
                | tUPLUS arg
                | tUMINUS arg
                | '!' arg
                | '~' arg
                | kDEFINED opt_nl arg
                | arg '?' arg ':' arg
                | primary
                ;


opt_call_args   :  # none
                | call_args opt_nl
                ;

call_args       : command_call
                | args opt_block_arg
                | args ',' tSTAR arg opt_block_arg
                | assocs opt_block_arg
                | assocs ',' tSTAR arg opt_block_arg
                | args ',' assocs opt_block_arg
                | args ',' assocs ',' tSTAR arg opt_block_arg
                | tSTAR arg opt_block_arg
                | block_arg
                ;

block_arg       : tAMPER arg ;

opt_block_arg   : ',' block_arg
                |  # none
                ;

opt_list        : args
                |  # none
                ;

args            : arg
                | args ',' arg
                ;

mrhs            : args
                | tSTAR arg
                | args ',' tSTAR arg
                ;

array           :   # none
                | args trailer
								;

primary         : tOBJECT
                | tSYMBEG symbol
                | primary tCOLON2 tIDENTIFIER
                | tCOLON3 tIDENTIFIER
                | variable
                | backref
                | primary '[' opt_call_args ']'
                | tLBRACK array ']'
                | tLBRACE assoc_list '}'
                | kRETURN '(' call_args ')'
                | kRETURN '(' ')'
                | kRETURN
                | kYIELD '(' call_args ')'
                | kYIELD '(' ')'
                | kYIELD
                | kDEFINED opt_nl '(' in_defined expr ')'
                | tFID
                | operation iter_block
                | method_call
                | method_call iter_block
                | kIF expr then compstmt if_tail kEND
                | kUNLESS expr then compstmt opt_else kEND
                | kWHILE expr do compstmt kEND
                | kUNTIL expr do compstmt kEND
                | kCASE compstmt case_body kEND
                | kFOR iter_var kIN expr do compstmt kEND
                | kBEGIN compstmt rescue ensure kEND
                | tLPAREN compstmt ')'
                | kCLASS tIDENTIFIER superclass compstmt kEND
                | kCLASS tLSHFT expr term compstmt kEND
                | kMODULE tIDENTIFIER compstmt kEND
                | kDEF fname f_arglist compstmt kEND
                | kDEF singleton '.'
								    mode_fname fname
                    mode_end f_arglist compstmt kEND
                | kBREAK
                | kNEXT
                | kREDO
                | kRETRY
                ;

then            : term
                | kTHEN
                | term kTHEN
                ;

do              : term
                | kDO
                | term kDO
                ;

if_tail         : opt_else
                | kELSIF expr then compstmt if_tail
                ;

opt_else        :  # none
                | kELSE compstmt
                ;

iter_var        : lhs
                | mlhs
                ;

opt_iter_var    :  # none
                | '|' '|'
                | tOROP
                | '|' iter_var '|'
                ;

iter_do_block   : kDO opt_iter_var compstmt kEND ;

iter_block      : '{' opt_iter_var compstmt '}' ;

iterator        : tIDENTIFIER
                | tFID
                | method_call
                | command_call
                ;

method_call     : operation '(' opt_call_args ')'
                | primary '.' operation '(' opt_call_args ')'
                | primary '.' operation
                | primary tCOLON2 operation '(' opt_call_args ')'
                | kSUPER '(' opt_call_args ')'
                | kSUPER
                ;


case_body       : kWHEN args then compstmt cases ;

cases           : opt_else
                | case_body
                ;

rescue          : kRESCUE opt_list do compstmt rescue
                |  # empty
                ;

ensure          :  # empty
                | kENSURE compstmt
                ;

symbol          : fname
                | tIVAR
                | tGVAR
                ;

variable        : tIDENTIFIER
                | tIVAR
                | tGVAR
                | kNIL
                | kSELF
                | kTRUE
                | kFALSE
                | k__FILE__
                | k__LINE__
                ;

backref         : tNTH_REF
                | tBACK_REF
                ;

superclass      : term
                | '<' mode_beg expr term
                ;

f_arglist       : '(' f_args opt_nl ')'
                .
                  @scanner.mode = :EXPR_BEG
                .
                | f_args term
                ;

f_args          : f_arg ',' f_optarg ',' f_rest_arg opt_f_block_arg
                | f_arg ',' f_optarg opt_f_block_arg
                | f_arg ',' f_rest_arg opt_f_block_arg
                | f_arg opt_f_block_arg
                | f_optarg ',' f_rest_arg opt_f_block_arg
                | f_optarg opt_f_block_arg
                | f_rest_arg opt_f_block_arg
                | f_block_arg
                |  # none
                ;

f_arg           : tIDENTIFIER
                | f_arg ',' tIDENTIFIER
                ;

f_opt           : tIDENTIFIER '=' arg ;

f_optarg        : f_opt
                | f_optarg ',' f_opt
                ;

f_rest_arg      : tSTAR tIDENTIFIER ;

f_block_arg     : tAMPER tIDENTIFIER ;

opt_f_block_arg : ',' f_block_arg
                |  # empty
                ;

singleton       : variable
                | tLPAREN expr opt_nl ')'
                ;

assoc_list      :  # empty
                | assocs trailer
                | args trailer
                ;

assocs          : assoc
                | assocs ',' assoc
								;

assoc           : arg tASSOC arg ;

operation       : tIDENTIFIER
                | tFID
                ;

opt_terms       :  # empty
                | terms
                ;

opt_nl          :  # empty
                | '\n'
                ;

trailer         :  # empty
                | '\n'
                | ','
                ;

term            : ';'
                | '\n'
                ;

terms           : term
                | terms ';'
                ;


mode_fname      :
                .
                  @scanner.mode = :EXPR_FNAME
                .
								;

mode_beg        :
                .
                  @scanner.mode = :EXPR_BEG
                .
								;

in_defined      :
                .
								  @scanner.in_defined = true
								.
								;


end   # rule

end   # class
