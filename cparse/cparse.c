/* vi:set ts=4 sw=4:

  cparse.c version 0.2.1
  
    Copyright (c) 1999 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
  
    This library is free software.
    You can distribute/modify this program under the terms of
    the GNU Lesser General Public Lisence version 2 or later.

*/

#include <stdio.h>
#include "ruby.h"

#define DFLT_TOK -1
#define ERR_TOK   1
#define FINAL_TOK 0

static VALUE FindBug;

static ID id_yydebug;
static ID id_nexttoken;
static ID id_onerror;
static ID id_noreduce;

static ID id__shift;
static ID id__reduce;
static ID id__accept;


#ifdef DEBUG
# define D(code) if (in_debug) code
#else
# define D(code)
#endif


#define STACK_INIT_LEN 64
#define INIT_STACK(s) \
    s = rb_ary_new2(STACK_INIT_LEN);

#define PUSH(s, i) \
    rb_ary_store(s, RARRAY(s)->len, i)

#define POP(s) \
    rb_ary_pop(s)

#define LAST_I(s) \
    RARRAY(s)->ptr[RARRAY(s)->len - 1];

#define GET_TAIL(s, leng) \
    rb_ary_new4(leng, RARRAY(s)->ptr + RARRAY(s)->len - leng)

#define CUT_TAIL(arr, leng) \
if (1) {                    \
    long i;                 \
    for (i = leng; i; i--)  \
        rb_ary_pop(arr);    \
}

/* this is fast but not safe
   RARRAY(arr)->len -= leng */


#define GET_POINTER(pointer, table, state, retvar) \
if (1) {                                                              \
    if (state < 0 || state >= RARRAY(pointer)->len)                   \
      rb_raise(FindBug, "[Racc Bug] illegal state: %ld", state);      \
    tmp = RARRAY(pointer)->ptr[state];                                \
    retvar = FIX2LONG(tmp);                                           \
    if (retvar < 0 || retvar > RARRAY(table)->len - 2)                \
      rb_raise(FindBug, "[Racc Bug] illegal table ptr: %ld", retvar); \
}

#define SEARCH(table, i, t, retvar) \
if (1) {                                                         \
    if (i < 0 || i > RARRAY(table)->len - 2)                     \
      rb_raise(FindBug, "[Racc Bug] illegal table ptr: %ld", i); \
    while (1) {                                                  \
        long lt;                                                 \
        tmp = RARRAY(table)->ptr[i];                             \
        lt = FIX2LONG(tmp);                                      \
        if (lt == t || lt == DFLT_TOK) {                         \
            tmp = RARRAY(table)->ptr[i+1];                       \
            retvar = FIX2LONG(tmp);                              \
            break;                                               \
        }                                                        \
        i += 2;                                                  \
    }                                                            \
}


struct cp_params {
    VALUE parser;
    VALUE action_table;
    VALUE action_ptr;
    VALUE goto_table;
    VALUE goto_ptr;
    VALUE reduce_table;
    VALUE token_table;

    VALUE state;
    long curstate;
    VALUE vstack;
    VALUE tstack;
};


static void
do_reduce(v, ruleno, debug)
    struct cp_params *v;
    long ruleno;
    int debug;
{
    VALUE reduce_to, reduce_len, method_id;
    long len, re;
    ID mid;
    VALUE tmp, tmp_t, tmp_v;
    long ltmp, i;

    reduce_len = RARRAY(v->reduce_table)->ptr[ruleno];
    reduce_to  = RARRAY(v->reduce_table)->ptr[ruleno+1];
    method_id  = RARRAY(v->reduce_table)->ptr[ruleno+2];
    len = FIX2LONG(reduce_len);
    re  = FIX2LONG(reduce_to);
    mid = (ID)FIX2LONG(method_id);

    if (len == 0) {
        tmp = Qnil;
        if (mid != id_noreduce)
            tmp_v = rb_ary_new();
        if (debug)
            tmp_t = rb_ary_new();
    }
    else {
        if (mid != id_noreduce) {
            tmp_v = GET_TAIL(v->vstack, len);
            tmp = RARRAY(tmp_v)->ptr[0];
        }
        else {
            tmp = RARRAY(v->vstack)->ptr[ RARRAY(v->vstack)->len - len ];
        }
        CUT_TAIL(v->vstack, len);
        if (debug) {
            tmp_t = GET_TAIL(v->tstack, len);
            CUT_TAIL(v->tstack, len);
        }
        CUT_TAIL(v->state, len);
    }

    /* method call must be done before tstack.push */
    if (mid != id_noreduce) {
        tmp = rb_funcall(v->parser, mid,
                         3, tmp_v, v->vstack, tmp);
    }
    PUSH(v->vstack, tmp);
    if (debug) {
        PUSH(v->tstack, reduce_to);
        rb_funcall(v->parser, id__reduce,
                   3, tmp_t, reduce_to, v->tstack);
    }

    if (RARRAY(v->state)->len == 0) {
        rb_raise(FindBug, "state stack unexpected empty");
    }
    tmp = LAST_I(v->state);
    ltmp = FIX2LONG(tmp);
    GET_POINTER(v->goto_ptr, v->goto_table, ltmp, i);
    SEARCH(v->goto_table, i, re, ltmp);
    if (ltmp < 0) {
        rb_raise(FindBug,
          "[Racc Bug] state=%d, goto < 0", v->curstate);
    }
    v->curstate = ltmp;
    PUSH(v->state, INT2FIX(ltmp));
}


#define REDUCE(v, act) \
    do_reduce(&v, -act * 3, debug)

#define SHIFT(v, st, tok, val) \
    PUSH(v.vstack, val);                       \
    if (debug) {                               \
        PUSH(v.tstack, INT2FIX(tok));          \
        rb_funcall(v.parser, id__shift,        \
                   2, INT2FIX(tok), v.tstack); \
    }                                          \
    v.curstate = st;                           \
    PUSH(v.state, INT2FIX(v.curstate));

#define ACCEPT(v) \
    if (debug) rb_funcall(v.parser, id__accept, 0); \
    return RARRAY(v.vstack)->ptr[0];

static VALUE
raccparse(parser,
          action_table, action_ptr, goto_table, goto_ptr,
          reduce_table, token_table, shn, rdn, indebug)
    VALUE parser,
          action_table, action_ptr, goto_table, goto_ptr,
          reduce_table, token_table, shn, rdn, indebug;
{
    VALUE debugp;
    int debug, in_debug;
    struct cp_params v;
    long shift_n, reduce_n;

    long act;
    int read_next;
    VALUE tok, val;
    long t;

    long nerr, errstatus;

    /* --------------------------
       initialize local values
    -------------------------- */

    D(in_debug = RTEST(indebug));

    debugp = rb_ivar_get(parser, id_yydebug);
    debug = RTEST(debugp);

    D(puts("start cparse"));

    Check_Type(action_table, T_ARRAY);
    Check_Type(action_ptr, T_ARRAY);
    Check_Type(goto_table, T_ARRAY);
    Check_Type(goto_ptr, T_ARRAY);
    Check_Type(reduce_table, T_ARRAY);
    Check_Type(token_table, T_HASH);
    v.parser = parser;
    v.action_table = action_table;
    v.action_ptr   = action_ptr;
    v.goto_table   = goto_table;
    v.goto_ptr     = goto_ptr;
    v.reduce_table = reduce_table;
    v.token_table  = token_table;

    shift_n  = NUM2LONG(shn);
    reduce_n = NUM2LONG(rdn);

    if (debug) INIT_STACK(v.tstack);
    INIT_STACK(v.vstack);
    INIT_STACK(v.state);
    v.curstate = 0;
    PUSH(v.state, INT2FIX(0));

    tok = val = Qnil;
    t = FINAL_TOK + 1; /* must not init to FINAL_TOK */

    read_next = 1;   /* causes yylex */
    nerr = 0;
    errstatus = 0;

    D(puts("params initialized"));

    /* -----------------------------------
       LALR parsing algorithm main loop
    ----------------------------------- */
    
    while (1) {
        long i;
        VALUE tmp;

        D(puts("enter new loop"));

        /* decide action */

        GET_POINTER(v.action_ptr, v.action_table, v.curstate, i);
        if (RARRAY(v.action_table)->ptr[i] == DFLT_TOK) {
            tmp = RARRAY(v.action_table)->ptr[i+1];
            act = FIX2LONG(tmp);
        }
        else {
            if (read_next) {
                if (t != FINAL_TOK) {
                    tmp = rb_funcall(v.parser, id_nexttoken, 0);
                    Check_Type(tmp, T_ARRAY);
                    if (RARRAY(tmp)->len < 2)
                        rb_raise(rb_eArgError,
                                 "next_token returns too short array");
                    tok = RARRAY(tmp)->ptr[0];
                    val = RARRAY(tmp)->ptr[1];
                    tmp = rb_hash_aref(v.token_table, tok);
                    t = NIL_P(tmp) ? ERR_TOK : FIX2INT(tmp);
                    D(printf("read token %ld\n", t));
                }
                read_next = 0;
            }
            SEARCH(v.action_table, i, t, act);
        }
        D(printf("act=%ld\n", act));


        if (act > 0 && act < shift_n) {
            D(puts("shift"));

            if (errstatus > 0) errstatus--;
            SHIFT(v, act, t, val);
            read_next = 1;
        }
        else if (act < 0 && act > -reduce_n) {
            D(puts("reduce"));

            REDUCE(v, act);
        }
        else if (act == -reduce_n) {
            D(printf("error detected, status=%ld\n", errstatus));

            if (errstatus == 0) {
                nerr++;
                rb_funcall(v.parser, id_onerror,
                           3, INT2FIX(t), val, v.vstack);
            }
            else if (errstatus == 3) {
                if (t == FINAL_TOK)
                    return Qfalse;
                read_next = 1;
            }
            errstatus = 3;

            /* check if We can shift/reduce error token */
            while (1) {
                GET_POINTER(v.action_ptr, v.action_table, v.curstate, i);
                while (1) {
                    long lt;
                    tmp = RARRAY(v.action_table)->ptr[i];
                    lt = FIX2LONG(tmp);
                    if (lt == DFLT_TOK) {
                        D(puts("can't found error tok"));
                        break;
                    }
                    if (lt == ERR_TOK) {
                        D(puts("found error tok"));
                        tmp = RARRAY(v.action_table)->ptr[i+1];
                        act = FIX2LONG(tmp);
                        D(printf("e act=%ld\n", act));
                        break;
                    }
                    i += 2;
                }

                if (act != -reduce_n) { /* We can do. */
                    D(puts("can handle error tok"));
                    break;
                }
                else { /* We cannot: pop stack and try again */
                    D(puts("can't handle error tok: pop"));
                    if (RARRAY(v.state)->len == 0)
                        return Qnil;
                    POP(v.state);
                    POP(v.vstack);
                    tmp = LAST_I(v.state);
                    v.curstate = FIX2LONG(tmp);
                    if (debug) POP(v.tstack);
                }
            }

            /* shift|reduce error token */

            if (act > 0 && act < shift_n) {
                D(puts("e shift"));
                SHIFT(v, act, ERR_TOK, Qnil);
            }
            else if (act < 0 && act > -reduce_n) {
                D(puts("e reduce"));
                REDUCE(v, act);
            }
            else if (act == shift_n) {
                D(puts("e accept"));
                ACCEPT(v);
            }
            else {
                rb_raise(FindBug, "[Racc Bug] unknown act value %ld", act);
            }
        }
        else if (act == shift_n) {
            D(puts("accept"));
            ACCEPT(v);
        }
        else {
            rb_raise(FindBug, "[Racc Bug] unknown act value %ld", act);
        }
    }
}


void
Init_cparse()
{
    VALUE parser;

    parser = rb_eval_string("::Racc::Parser");
    rb_define_private_method(parser, "_c_parse", raccparse, 9);

    FindBug = rb_eval_string("FindBug");

    id_yydebug      = rb_intern("@yydebug");
    id_nexttoken    = rb_intern("next_token");
    id_onerror      = rb_intern("on_error");
    id_noreduce     = rb_intern("_reduce_none");

    id__shift       = rb_intern("_shift");
    id__reduce      = rb_intern("_reduce");
    id__accept      = rb_intern("_accept");
}
