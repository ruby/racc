/* vi:set ts=4 sw=4: */

#include <stdio.h>
#include "ruby.h"


static ID id_yydebug;
static ID id_nexttoken;
static ID id_onerror;

static ID id_actiontable;
static ID id_actionptr;
static ID id_gototable;
static ID id_gotoptr;
static ID id_reducetable;
static ID id_tokentable;
static ID id_staten;
static ID id_shiftn;
static ID id_reducen;
static ID id_tostable;

static ID id__shift;
static ID id__reduce;
static ID id__accept;


static void
repbug(parser, mes)
	VALUE parser;
	char *mes;
{
	rb_funcall(parser, rb_intern("bug!"), 1, rb_str_new2(mes));
}


#define FETCH_NEXT_TOKEN \
	tmp = rb_funcall(parser, id_nexttoken, 0); \
	Check_Type(tmp, T_ARRAY); \
	if (RARRAY(tmp)->len < 2) \
		rb_raise(rb_eArgError, "next_token returns too little array"); \
	tok = RARRAY(tmp)->ptr[0]; \
	val = RARRAY(tmp)->ptr[1]; \
	tmp = rb_hash_aref(token_table, tok); \
	t = FIX2INT(tmp)

#define STACK_INIT_LEN 64
#define INIT_STACK(s) \
	s = rb_ary_new2(STACK_INIT_LEN);

#define PUSH(s, i) \
	rb_ary_store(s, RARRAY(s)->len, i)

#define GET_TAIL(s, leng) \
	rb_ary_new4(leng, RARRAY(s)->ptr + RARRAY(s)->len - leng)

#define CUT_TAIL(arr, leng) \
do { \
	long i; \
	for (i = leng; i; i--) \
		rb_ary_pop(arr); \
} while (0)
/* this is LITTLE fast but not safe
   RARRAY(arr)->len -= leng */

#define SEARCH_ERROR -1
#define SEARCH(pointer, table, state, token, retvar) \
do {                                                             \
	long i, ii;                                                  \
	tmp = RARRAY(pointer)->ptr[state];                           \
	i = FIX2LONG(tmp);                                           \
	if (i == SEARCH_ERROR) { puts("ptr is -1"); return Qnil; }   \
	while (1) {                                                  \
/* printf("i=%ld\n", i); */ \
		tmp = RARRAY(table)->ptr[i];                             \
		ii = FIX2LONG(tmp);                                      \
		if (ii == token || ii == 0) {                            \
			retvar = RARRAY(table)->ptr[i+1];                    \
			break;                                               \
		}                                                        \
		i += 2;                                                  \
	}                                                            \
} while (0)


static VALUE
raccparse(parser, indebug)
	VALUE parser, indebug;
{
	int in_debug;
	VALUE parser_class;
	VALUE debugp;
	int debug;

	VALUE action_table, action_ptr;
	VALUE goto_ptr, goto_table;
	VALUE reduce_table, token_table;
	VALUE stn, shn, ren;
	long state_n, shift_n, reduce_n;

	long curstate;
	long act;
	VALUE tstack, vstack, state;
	VALUE tok, val;
	long t;

	VALUE reduce_to, reduce_len, method_id;
	long len, re;
	VALUE tmp_v;

	VALUE tmp;

	VALUE pass[5];

    /* --------------------------
	   initialize local values
	-------------------------- */

	in_debug = RTEST(indebug);

	parser_class = CLASS_OF(parser);
	debugp = rb_ivar_get(parser, id_yydebug);
	debug = RTEST(debugp);

	if (in_debug) puts("start cparse");

	action_table = rb_const_get(parser_class, id_actiontable);
	action_ptr   = rb_const_get(parser_class, id_actionptr);
	goto_table   = rb_const_get(parser_class, id_gototable);
	goto_ptr     = rb_const_get(parser_class, id_gotoptr);
	reduce_table = rb_const_get(parser_class, id_reducetable);
	token_table  = rb_const_get(parser_class, id_tokentable);
	Check_Type(action_table, T_ARRAY);
	Check_Type(action_ptr, T_ARRAY);
	Check_Type(goto_table, T_ARRAY);
	Check_Type(goto_ptr, T_ARRAY);
	Check_Type(reduce_table, T_ARRAY);
	Check_Type(token_table, T_HASH);

	/* stn = rb_const_get(parser_class, id_staten); */
	shn = rb_const_get(parser_class, id_shiftn);
	ren = rb_const_get(parser_class, id_reducen);
	/* state_n = FIX2INT(stn); */
	shift_n = FIX2INT(shn);
	reduce_n = FIX2INT(ren);

	if (debug) INIT_STACK(tstack);
	INIT_STACK(vstack);
	INIT_STACK(state);
	curstate = 0;
	PUSH(state, INT2FIX(0));

	FETCH_NEXT_TOKEN;

	if (in_debug) puts("params initialized");

    /* -----------------------------------
	   LALR parsing algorithm main loop
	----------------------------------- */
	
	while (1) {
		if (in_debug) puts("enter new loop");

		/* decide action */

		SEARCH(action_ptr, action_table, curstate, t, tmp);
		act = FIX2LONG(tmp);
		if (in_debug) printf("act=%ld\n", act);

		if (act >= 0 && act <= shift_n) {
			/* shift */
			
			PUSH(vstack, val);
			if (debug) {
				PUSH(tstack, INT2FIX(t));
				rb_funcall(parser, id__shift,
			               2, INT2FIX(t), tstack);
			}

			curstate = act;
			PUSH(state, INT2FIX(curstate));
			FETCH_NEXT_TOKEN;
		}
		else if (act < 0 && act >= -reduce_n) {
			/* reduce */

			act = -act * 3;
			reduce_len = RARRAY(reduce_table)->ptr[act];
			reduce_to  = RARRAY(reduce_table)->ptr[act+1];
			method_id  = RARRAY(reduce_table)->ptr[act+2];
			len = FIX2LONG(reduce_len);
			re = FIX2LONG(reduce_to);

			if (len == 0) {
				tmp_v = rb_ary_new();
			}
			else {
				tmp_v = GET_TAIL(vstack, len);
				CUT_TAIL(vstack, len);
				CUT_TAIL(state, len);
				if (debug) {
					CUT_TAIL(tstack, len);
				}
			}

			/* method call must be done before tstack.push */
			tmp = rb_funcall(parser, (ID)FIX2LONG(method_id),
			                 2, tmp_v, vstack);
			PUSH(vstack, tmp);
			if (debug) {
				PUSH(tstack, reduce_to);
				rb_funcall(parser, id__reduce,
			               3, tmp_t, reduce_to, tstack);
			}

			if (RARRAY(state)->len == 0) {
				repbug(parser, "state stack unexpected empty");
			}
			tmp = RARRAY(state)->ptr[RARRAY(state)->len - 1];
			curstate = FIX2LONG(tmp);
			SEARCH(goto_ptr, goto_table, curstate, re, tmp);
			curstate = FIX2LONG(tmp);
			PUSH(state, tmp);
		}
		else if (act == -reduce_n - 1) {
			/* accept */

			if (debug) rb_funcall(parser, id__accept, 0);
			break;
		}
		else if (act == shift_n + 1) {
			/* error */

			rb_funcall(parser, id_onerror,
			           3, INT2FIX(t), val, vstack);
		}
		else {
			fprintf(stderr, "racc c-parse: unknown act %ld\n", act);
			repbug(parser, "unknown act value");
		}
	}

	return RARRAY(vstack)->ptr[0];
}


void
Init_cparse()
{
	VALUE psr;

	psr = rb_eval_string("Parser");
	rb_define_private_method(psr, "_c_parse", raccparse, 1);

	id_yydebug      = rb_intern("@yydebug");
    id_nexttoken    = rb_intern("next_token");
	id_onerror      = rb_intern("on_error");

	id_actiontable  = rb_intern("LR_action_table");
	id_actionptr    = rb_intern("LR_action_table_ptr");
	id_gototable    = rb_intern("LR_goto_table");
	id_gotoptr      = rb_intern("LR_goto_table_ptr");
	id_reducetable  = rb_intern("LR_reduce_table");
	id_tokentable   = rb_intern("LR_token_table");
	id_staten       = rb_intern("LR_state_n");
	id_shiftn       = rb_intern("LR_shift_n");
	id_reducen      = rb_intern("LR_reduce_n");
	id_tostable     = rb_intern("LR_to_s_table");

	id__shift       = rb_intern("_shift");
	id__reduce      = rb_intern("_reduce");
	id__accept      = rb_intern("_accept");
}
