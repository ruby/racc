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

static VALUE findbug;


#define DEFAULT 0
#define FINAL_TOKEN 1
#define ERROR_TOKEN 2
#define TRY_N 3


struct cstack {
    long *ptr;
    long capa;
    long len;
}

#define STACK_INIT_LEN 64

/* C stack macros */

#define INIT_C_STACK(s) {\
    s.ptr = ALLOC_N(long, INIT_STACK_LEN); \
    s.capa = INIT_STACK_LEN;               \
    s.len = 0;                             \
}

#define FREE_C_STACK(s) \
    free(s.ptr);

#define C_PUSH(s, i) {\
    if (s.len == s->capa)                     \
        s.ptr = REALLOC_N(s.ptr, s.capa * 2); \
    s.ptr[s.len] = i;                         \
    s.len++;                                  \
}

#define C_POP(s) \
    if (s.len) s.len--;

#define C_CUT_TAIL(s, leng) {\
    if (s->len > leng) s->len -= leng; \
    else { \
        ENSURE_DO; \
        rb_raise(findbug, "[Racc Bug] c stack unexpected empty"); \
}

#define MUST_NOT_EMPTY(s) \
    if (s.len == 0) { \
        ENSURE_DO; \
        rb_raise(findbug, "[Racc Bug] state stack unexpected empty"); \
    }


/* Ruby stack macros */

#define INIT_R_STACK(s) \
    s = rb_ary_new2(STACK_INIT_LEN);

#define R_PUSH(s, i) \
    rb_ary_store(s, RARRAY(s)->len, i);

#define R_POP(s) \
    rb_ary_pop(s);

#define R_GET_TAIL(s, leng) \
    rb_ary_new4(leng, RARRAY(s)->ptr + RARRAY(s)->len - leng);

#define R_CUT_TAIL(arr, leng) {\
    long i;                \
    for (i = leng; i; i--) \
        rb_ary_pop(arr);   \
}



static char*
value_class(val)
    VALUE val;
{
    VALUE tmp;

    tmp = rb_class_of(val);
    tmp = rb_class_path(tmp);
    return STR2CSTR(tmp);
}


static void
chk_params(val, type, tag)
    VALUE val;
    int type;
    char *tag;
{
    if (TYPE(val) != type) {
        rb_raise(rb_eTypeError, "[Racc Bug] illegal param type %s for %s",
                 value_class(val), tag);
    }
}


#define CHECK_TOKEN_TYPE(tok) \
    if (TYPE(tok) != T_ARRAY)                                    \
        rb_raise(rb_eTypeError,                                  \
            "next_token returns wrong type %s (Array required)", \
            value_class(tok));

#define CONV_ERR(tok) {\
    ENSURE_DO;                                                         \
    if (NIL_P(tok))                                                    \
        rb_raise(rb_eTypeError,                                        \
                 "can't convert token simbol(%s) into internal value", \
                 value_class(tok));                                    \
    else                                                               \
        rb_raise(findbug, "token table include non Fixnum: %s",        \
                 value_class(tok));                                    \
}

#define FETCH_NEXT_TOKEN \
    tmp = rb_funcall(parser, id_nexttoken, 0);                         \
    CHECK_TOKEN_TYPE(tmp);                                             \
    if (RARRAY(tmp)->len < 2)                                          \
        rb_raise(rb_eArgError, "next_token returns too little array"); \
    tok = RARRAY(tmp)->ptr[0];                                         \
    val = RARRAY(tmp)->ptr[1];                                         \
    tmp = rb_hash_aref(token_table, tok);                              \
    if (!FIXNUM_P(tmp)) CONV_ERR(tmp);                                 \
    t = FIX2INT(tmp)

#define SEARCH_ERROR -1

#define SEARCH(table, i, t, retvar) \
    while (1) {                               \
        long ii;                              \
/* printf("i=%ld\n", i); */                   \
        tmp = RARRAY(table)->ptr[i];          \
        ii = FIX2LONG(tmp);                   \
        if (ii == t || ii == DEFAULT) {       \
            retvar = RARRAY(table)->ptr[i+1]; \
            break;                            \
        }                                     \
        i += 2;                               \
    }

#define ACCEPT {\
    ENSURE_DO;                     \
    return RARRAY(vstack)->ptr[0]; \
}

#define ENSURE_DO {\
    FREE_C_STACK(state); \
}

static VALUE
do_raccparse(parser)
    VALUE parser;
{
    int in_debug;
    VALUE parser_class;
    VALUE debugp;
    int debug;

    VALUE action_table, action_ptr;
    VALUE goto_ptr, goto_table;
    VALUE reduce_table, token_table;
    VALUE shn, ren;
    long state_n, reduce_n;

    long curstate;
    struct cstack state;
    long act;
    VALUE tstack, vstack;
    VALUE tok, val;
    long t;

    VALUE reduce_to, reduce_len, method_id, m_result;
    long len, re;
    VALUE tmp_t, tmp_v;

    long err_state, err_total;

    VALUE tmp;
    long i;

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
    chk_params(action_table, T_ARRAY, "action table");
    chk_params(action_ptr,   T_ARRAY, "action pointer");
    chk_params(goto_table,   T_ARRAY, "goto table");
    chk_params(goto_ptr,     T_ARRAY, "goto pointer");
    chk_params(reduce_table, T_ARRAY, "reduce table");
    chk_params(token_table,  T_HASH,  "token table");

    shn = rb_const_get(parser_class, id_shiftn);
    ren = rb_const_get(parser_class, id_reducen);
    shift_n = FIX2LONG(shn);
    reduce_n = FIX2LONG(ren);

    if (debug) INIT_R_STACK(tstack);
    INIT_R_STACK(vstack);
    INIT_C_STACK(state);
    curstate = 0;
    C_PUSH(state, 0);

    act = 0;

    err_state = 0;
    total_err = 0;

    if (in_debug) puts("params initialized");

    /* -----------------------------------
       LALR parsing algorithm main loop
    ----------------------------------- */
    
    while (1) {
        if (in_debug) puts("enter new loop");

        if (!act) {
            /* fetch action ID */

            while (1) {
                tmp = RARRAY(action_ptr)->ptr[state];
                i = FIX2LONG(tmp);
                if (RARRAY(action_table)->ptr[i] == 0) {
                    tmp = RARRAY(action_table)->ptr[i+1];
                    break;
                }
                if (t != FINAL_TOKEN)
                    FETCH_NEXT_TOKEN;
                SEARCH(action_table, i, t, tmp);
                break;
            }
            act = FIX2LONG(tmp);
            if (in_debug) printf("act=%ld\n", act);
        }


        /* decide action */

        if (act > 0 && act < shift_n) {
            /* shift */
            
            R_PUSH(vstack, val);
            if (debug) {
                R_PUSH(tstack, INT2FIX(t));
                rb_funcall(parser, id__shift,
                           2, INT2FIX(t), tstack);
            }

            curstate = act;
            C_PUSH(state, INT2FIX(curstate));

            act = 0;
        }
        else if (act < 0 && act > -reduce_n) {
            /* reduce */

            act = -act * 3;
            reduce_len = RARRAY(reduce_table)->ptr[act];
            reduce_to  = RARRAY(reduce_table)->ptr[act+1];
            method_id  = RARRAY(reduce_table)->ptr[act+2];
            len = FIX2LONG(reduce_len);
            re = FIX2LONG(reduce_to);

            if (len == 0) {
                tmp_v = rb_ary_new();
                m_result = Qnil;
            }
            else {
                tmp_v = R_GET_TAIL(vstack, len);
                m_result = RARRAY(tmp_v)->ptr[0];
                R_CUT_TAIL(vstack, len);
                C_CUT_TAIL(state, len);
                if (debug) {
                    tmp_t = R_GET_TAIL(tstack, len);
                    R_CUT_TAIL(tstack, len);
                }
            }

            /* method call must be done before tstack.push */
            tmp = rb_funcall(parser, (ID)FIX2LONG(method_id),
                             3, tmp_v, vstack, m_result);
            R_PUSH(vstack, tmp);
            if (debug) {
                R_PUSH(tstack, reduce_to);
                rb_funcall(parser, id__reduce,
                           3, tmp_t, reduce_to, tstack);
            }

            MUST_NOT_EMPTY(state);
            i = state.ptr[state.len - 1];
            tmp = RARRAY(goto_pointer)->ptr[i];
            i = FIX2LONG(tmp);
            if (i == SEARCH_ERROR) rb_raise(findbug, "pointer is -1");
            SEARCH(goto_table, i, re, tmp);
            curstate = FIX2LONG(tmp);
            C_PUSH(state, curstate);

            act = 0;
        }
        else if (act == shift_n) {
            /* error */

            if (err_state == 0) {
                err_total++;
                rb_funcall(parser, id_onerror,
                           3, INT2FIX(t), val, vstack);
            }
            if (err_state == 3) {
                FETCH_NEXT_TOKEN;
            }
            err_state = 3;

            while (1) {
                tmp = RARRAY(action_ptr)->ptr[state];
                i = FIX2LONG(tmp);
                SEARCH(action_table, i, ERROR_TOKEN, tmp);
                act = FIX2LONG(tmp);

                if (act > 0) {
                    if (act < shift_n) break;    /* shift */
                }
                if (act < 0) {
                    act = -act;
                    if (act == reduce_n) ACCEPT;
                    if (act < reduce_n)  break;  /* reduce */
                }

                /* error yet ... */

                MUST_NOT_EMPTY(state);

                if (debug) R_POP(tstack);
                R_POP(vstack);
                C_POP(state);
            }
        }
        else if (act == reduce_n) {
            /* accept */

            if (debug) rb_funcall(parser, id__accept, 0);
            ACCEPT;
        }
        else {
            /* racc error */

            rb_raise(findbug, "[Racc Bug] unknown act value %ld", act);
        }
    }

    return Qnil;  /* not reach */
}


void
Init_cparse()
{
    VALUE psr;

    psr = rb_eval_string("Parser");
    rb_define_private_method(psr, "_c_parse", raccparse, 1);

    findbug = rb_eval_string("FindBug");

    id_yydebug      = rb_intern("@yydebug");
    id_nexttoken    = rb_intern("next_token");
    id_onerror      = rb_intern("on_error");

    id_actiontable  = rb_intern("LR_action_table");
    id_actionptr    = rb_intern("LR_action_table_ptr");
    id_gototable    = rb_intern("LR_goto_table");
    id_gotoptr      = rb_intern("LR_goto_table_ptr");
    id_reducetable  = rb_intern("LR_reduce_table");
    id_tokentable   = rb_intern("LR_token_table");
    /* id_staten       = rb_intern("LR_state_n"); */
    id_shiftn       = rb_intern("LR_shift_n");
    id_reducen      = rb_intern("LR_reduce_n");
    id_tostable     = rb_intern("LR_to_s_table");

    id__shift       = rb_intern("_shift");
    id__reduce      = rb_intern("_reduce");
    id__accept      = rb_intern("_accept");
}
