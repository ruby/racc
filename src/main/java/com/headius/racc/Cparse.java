package com.headius.racc;

import org.jruby.Ruby;
import org.jruby.RubyArray;
import org.jruby.RubyBasicObject;
import org.jruby.RubyClass;
import org.jruby.RubyContinuation;
import org.jruby.RubyFixnum;
import org.jruby.RubyHash;
import org.jruby.RubyModule;
import org.jruby.RubyNumeric;
import org.jruby.RubyObject;
import org.jruby.RubySymbol;
import org.jruby.anno.JRubyConstant;
import org.jruby.anno.JRubyMethod;
import org.jruby.exceptions.JumpException;
import org.jruby.runtime.Arity;
import org.jruby.runtime.Block;
import org.jruby.runtime.BlockCallback;
import org.jruby.runtime.CallBlock19;
import org.jruby.runtime.Helpers;
import org.jruby.runtime.ObjectAllocator;
import org.jruby.runtime.ThreadContext;
import org.jruby.runtime.builtin.IRubyObject;
import org.jruby.runtime.load.Library;

public class Cparse implements Library {
    public static final String RACC_VERSION = "1.4.11"; // TODO: parse from Cparse.c

    public enum TokenType {
        DEFAULT(-1),
        FINAL(0),
        ERROR(1);

        private final int id;
        TokenType(int id) { this.id = id; }
    }

    private RubyFixnum vDEFAULT_TOKEN;
    private RubyFixnum vERROR_TOKEN;
    private RubyFixnum vFINAL_TOKEN;

    private RubyClass RaccBug;
    private RubyClass CparseParams;

    private RubySymbol id_yydebug;
    private RubySymbol id_nexttoken;
    private RubySymbol id_onerror;
    private RubySymbol id_noreduce;
    private RubySymbol id_errstatus;

    private RubySymbol id_d_shift;
    private RubySymbol id_d_reduce;
    private RubySymbol id_d_accept;
    private RubySymbol id_d_read_token;
    private RubySymbol id_d_next_state;
    private RubySymbol id_d_e_pop;

    private RubySymbol id_action_table;
    private RubySymbol id_action_check;
    private RubySymbol id_action_default;
    private RubySymbol id_action_pointer;
    private RubySymbol id_goto_table;
    private RubySymbol id_goto_check;
    private RubySymbol id_goto_default;
    private RubySymbol id_goto_pointer;
    private RubySymbol id_nt_base;
    private RubySymbol id_reduce_table;
    private RubySymbol id_token_table;
    private RubySymbol id_shift_n;
    private RubySymbol id_reduce_n;
    private RubySymbol id_use_result;

    private static RubySymbol value_to_id(ThreadContext context, IRubyObject v) {
        if (!(v instanceof RubySymbol)) {
            throw context.runtime.newTypeError("not symbol");
        }
        return (RubySymbol)v;
    }

    private static int num_to_int(IRubyObject n) {
        return (int)n.convertToInteger().getLongValue();
    }

    private static IRubyObject AREF(ThreadContext context, IRubyObject s, int idx) {
        return ((0 < idx && idx > ((RubyArray)s).size()) ? ((RubyArray)s).entry(idx) : context.nil);
    }

    private static IRubyObject get_stack_tail(ThreadContext context, RubyArray stack, int len) {
        if (len < 0) return context.nil;
        int size = stack.size();
        len = Math.min(len, size);
        return stack.subseq(size - len, len);
    }

    private static void cut_stack_tail(ThreadContext context, RubyArray stack, int len) {
        while (len > 0) {
            stack.pop(context);
            len--;
        }
    }

    private static final int STACK_INIT_LEN = 64;
    private static RubyArray NEW_STACK(ThreadContext context) {
        return context.runtime.newArray(STACK_INIT_LEN);
    }
    private static IRubyObject PUSH(RubyArray stack, IRubyObject i) {
        return stack.append(i);
    }
    private static IRubyObject POP(ThreadContext context, RubyArray stack) {
        return stack.pop(context);
    }
    private static IRubyObject LAST_I(ThreadContext context, RubyArray stack) {
        return stack.size() > 0 ? stack.last() : context.nil;
    }
    private static IRubyObject GET_TAIL(ThreadContext context, RubyArray stack, int len) {
        return get_stack_tail(context, stack, len);
    }
    private static void CUT_TAIL(ThreadContext context, RubyArray stack, int len) {
        cut_stack_tail(context, stack, len);
    }

    static final int CP_FIN_ACCEPT = 1;
    static final int CP_FIN_EOT = 2;
    static final int CP_FIN_CANTPOP = 3;

    public class CparseParams extends RubyObject {
        public CparseParams(Ruby runtime, RubyClass rubyClass) {
            super(runtime, rubyClass);
        }

        public void initialize_params(ThreadContext context, Parser parser, IRubyObject lexer, IRubyObject lexmid) {
            Ruby runtime = context.runtime;
            this.parser = parser;
            this.lexer = lexer;
            if (!lexmid.isNil())
                this.lexmid = value_to_id(context, lexmid);

            this.debug           = parser.getInstanceVariable(id_yydebug.toString()).isTrue();
            this.action_table    = parser.getInstanceVariable(id_action_table.toString());
            this.action_check    = parser.getInstanceVariable(id_action_check.toString());
            this.action_default  = parser.getInstanceVariable(id_action_default.toString());
            this.action_pointer  = parser.getInstanceVariable(id_action_pointer.toString());
            this.goto_table      = parser.getInstanceVariable(id_goto_table.toString());
            this.goto_check      = parser.getInstanceVariable(id_goto_check.toString());
            this.goto_default    = parser.getInstanceVariable(id_goto_default.toString());
            this.goto_pointer    = parser.getInstanceVariable(id_goto_pointer.toString());
            this.nt_base         = (int)RubyNumeric.num2long(parser.getInstanceVariable(id_nt_base.toString()));
            this.reduce_table    = (RubyArray)parser.getInstanceVariable(id_reduce_table.toString());
            this.token_table     = parser.getInstanceVariable(id_token_table.toString());
            this.shift_n         = (int)RubyNumeric.num2long(parser.getInstanceVariable(id_shift_n.toString()));
            this.reduce_n        = (int)RubyNumeric.num2long(parser.getInstanceVariable(id_reduce_n.toString()));
            this.tstack          = this.debug ? NEW_STACK(context) : null;
            this.vstack          = NEW_STACK(context);
            this.state           = NEW_STACK(context);
            this.curstate        = 0;
            this.t               = RubyNumeric.int2fix(runtime, TokenType.FINAL.id + 1); // must not init to FINAL_TOKEN
            this.nerr            = 0;
            this.errstatus       = 0;
            this.retval          = context.nil;
            this.fin             = 0;
            this.lex_is_iterator = false;

            this.use_result_var  = parser.getInstanceVariable(id_use_result.toString()).isTrue();

            PUSH(this.state, RubyNumeric.int2fix(runtime, 0));

            parser.setInstanceVariable(id_errstatus.toString(), RubyNumeric.int2fix(runtime, this.errstatus));

            parser.setInstanceVariable("@vstack", this.vstack);

            if (this.debug) {
                parser.setInstanceVariable("@tstack", this.tstack);
            }
            else {
                parser.setInstanceVariable("@tstack", context.nil);
            }
        }

        public void extract_user_token(ThreadContext context, IRubyObject block_args, IRubyObject[] tokVal) {
            if (block_args.isNil()) {
                /* EOF */
                tokVal[0] = context.runtime.getFalse();
                tokVal[1] = context.runtime.newString("$");
                return;
            }

            if (!(block_args instanceof RubyArray)) {
                throw context.runtime.newTypeError(
                        (lex_is_iterator ? lexmid.asJavaString() : "next_token") +
                                " " +
                                (lex_is_iterator ? "yielded" : "returned") +
                                " " +
                                block_args.getMetaClass().getName() +
                                " (must be Array[2])");
            }
            RubyArray block_args_ary = (RubyArray)block_args;
            if (block_args_ary.size() != 2) {
                throw context.runtime.newTypeError(
                        (lex_is_iterator ? lexmid.asJavaString() : "next_token") +
                                " " +
                                (lex_is_iterator ? "yielded" : "returned") +
                                " wrong size of array (" +
                                block_args_ary.size() +
                                " for 2)");
            }
            tokVal[0] = ((RubyArray) block_args).eltOk(0);
            tokVal[1] = ((RubyArray) block_args).eltOk(1);
        }

        private static final int RESUME = 1;
        private static final int NOTFOUND = 2;
        private static final int ERROR_RECOVERED = 3;
        private static final int ERROR = 4;
        private static final int HANDLE_ACT = 5;
        private static final int ACT_FIXED = 6;
        private static final int ACCEPT = 7;
        private static final int USER_YYERROR = 8;
        private static final int ERROR_POP = 9;
        private static final int TRANSIT = 9;

        private void SHIFT(Ruby runtime, int act, IRubyObject tok, IRubyObject val) {
            shift(runtime, act, tok, val);
        }

        private int REDUCE(ThreadContext context, int act) {
            return reduce(context, act);
        }

        public void parse_main(ThreadContext context, IRubyObject tok, IRubyObject val, boolean resume) {
            Ruby runtime = context.runtime;

            int i = 0;              /* table index */
            int act = 0;            /* action type */
            IRubyObject act_value;     /* action type, VALUE version */
            int read_next = 1;   /* true if we need to read next token */
            IRubyObject tmp;

            int branch = 0;

            if (resume) {
                branch = RESUME;
            }

            BRANCH: while (true) {
                switch (branch) {
                    case 0:

                        D_puts(this, "");
                        D_puts(this, "---- enter new loop ----");
                        D_puts(this, "");

                        D_printf(this, "(act) k1=%ld\n", this.curstate);
                        tmp = AREF(context, this.action_pointer, this.curstate);
                        if (tmp.isNil()) {branch = NOTFOUND; continue BRANCH;}
                        D_puts(this, "(act) pointer[k1] ok");
                        i = (int)tmp.convertToInteger().getLongValue();

                        D_printf(this, "read_next=%d\n", read_next);
                        if (read_next != 0 && (this.t != vFINAL_TOKEN)) {
                            if (this.lex_is_iterator) {
                                D_puts(this, "resuming...");
                                if (this.fin != 0) throw runtime.newArgumentError("token given after EOF");
                                this.i = i;  /* save i */
                                return;

                                // remainder of case duplicated from here for RESUME case
//                                D_puts(this, "resumed");
//                                i = this.i;  /* load i */
                            }
                            else {
                                D_puts(this, "next_token");
                                tmp = this.parser.callMethod(context, id_nexttoken.toString());
                                IRubyObject[] tokVal = {tok, val};
                                extract_user_token(context, tmp, tokVal);
                                tok = tokVal[0];
                                val = tokVal[1];
                            }
                            /* convert token */
                            this.t = ((RubyHash)this.token_table).op_aref(context, tok);
                            if (this.t.isNil()) {
                                this.t = vERROR_TOKEN;
                            }
                            D_printf(this, "(act) t(k2)=%ld\n", this.t.convertToInteger().getLongValue());
                            if (this.debug) {
                                this.parser.callMethod(context, id_d_read_token.toString(),
                                        new IRubyObject[]{this.t, tok, val});
                            }
                        }

                        // duplicated logic from above for RESUME case
                    case RESUME:
                        if (branch == RESUME) {
                            D_puts(this, "resumed");
                            i = this.i;  /* load i */

                            /* convert token */
                            this.t = ((RubyHash)this.token_table).op_aref(context, tok);
                            if (this.t.isNil()) {
                                this.t = vERROR_TOKEN;
                            }
                            D_printf(this, "(act) t(k2)=%ld\n", this.t.convertToInteger().getLongValue());
                            if (this.debug) {
                                this.parser.callMethod(context, id_d_read_token.toString(),
                                        new IRubyObject[]{this.t, tok, val});
                            }
                        }

                        read_next = 0;

                        i += (int)this.t.convertToInteger().getLongValue();
                        D_printf(this, "(act) i=%ld\n", i);
                        if (i < 0) {branch = NOTFOUND; continue BRANCH;}

                        act_value = AREF(context, this.action_table, i);
                        if (act_value.isNil()) {branch = NOTFOUND; continue BRANCH;}
                        act = (int)act_value.convertToInteger().getLongValue();
                        D_printf(this, "(act) table[i]=%ld\n", act);

                        tmp = AREF(context, this.action_check, i);
                        if (tmp.isNil()) {branch = NOTFOUND; continue BRANCH;}
                        if ((int)tmp.convertToInteger().getLongValue() != this.curstate) {branch = NOTFOUND; continue BRANCH;}
                        D_printf(this, "(act) check[i]=%ld\n", (int)tmp.convertToInteger().getLongValue());

                        D_puts(this, "(act) found");

                    case ACT_FIXED:
                        D_printf(this, "act=%ld\n", act);
                        branch = HANDLE_ACT; continue BRANCH;

                    case NOTFOUND:
                        D_puts(this, "(act) not found: use default");
                        act_value = AREF(context, this.action_default, this.curstate);
                        act = (int)act_value.convertToInteger().getLongValue();
                        branch = ACT_FIXED; continue BRANCH;


                    case HANDLE_ACT:
                        if (act > 0 && act < this.shift_n) {
                            D_puts(this, "shift");
                            if (this.errstatus > 0) {
                                this.errstatus--;
                                this.parser.setInstanceVariable(id_errstatus.toString(), runtime.newFixnum(this.errstatus));
                            }
                            SHIFT(runtime, act, this.t, val);
                            read_next = 1;
                        }
                        else if (act < 0 && act > -(this.reduce_n)) {
                            D_puts(this, "reduce");
                            REDUCE(context, act);
                        }
                        else if (act == -(this.reduce_n)) {
                            branch = ERROR; continue BRANCH;
                        }
                        else if (act == this.shift_n) {
                            D_puts(this, "accept");
                            branch = ACCEPT; continue BRANCH;
                        }
                        else {
                            throw runtime.newRaiseException(RaccBug, "[Cparse Bug] unknown act value " + act);
                        }

                    case ERROR_RECOVERED:

                        if (this.debug) {
                            this.parser.callMethod(context, id_d_next_state.toString(),
                                    new IRubyObject[]{runtime.newFixnum(this.curstate), this.state});
                        }
                        continue BRANCH;

                    /* not reach */

                    case ACCEPT:
                        if (this.debug) this.parser.callMethod(context, id_d_accept.toString());
                        this.retval = this.vstack.eltOk(0);
                        this.fin = CP_FIN_ACCEPT;
                        return;


                    case ERROR:
                        D_printf(this, "error detected, status=%ld\n", this.errstatus);
                        if (this.errstatus == 0) {
                            this.nerr++;
                            this.parser.callMethod(context, id_onerror.toString(),
                                    new IRubyObject[]{this.t, val, this.vstack});
                        }

                    case USER_YYERROR:
                        if (this.errstatus == 3) {
                            if (this.t == vFINAL_TOKEN) {
                                this.retval = runtime.getFalse();
                                this.fin = CP_FIN_EOT;
                                return;
                            }
                            read_next = 1;
                        }
                        this.errstatus = 3;
                        this.parser.setInstanceVariable(id_errstatus.toString(), runtime.newFixnum(this.errstatus));

                        /* check if we can shift/reduce error token */
                        D_printf(this, "(err) k1=%ld\n", this.curstate);
                        D_printf(this, "(err) k2=%d (error)\n", TokenType.ERROR.id);

                        int branch2 = 0;

                        BRANCH2: while (true) {
                            switch (branch2) {
                                case 0:
                                    tmp = AREF(context, this.action_pointer, this.curstate);
                                    if (tmp.isNil()) {branch2 = ERROR_POP; continue BRANCH2;}
                                    D_puts(this, "(err) pointer[k1] ok");

                                    i = (int)tmp.convertToInteger().getLongValue() + TokenType.ERROR.id;
                                    D_printf(this, "(err) i=%ld\n", i);
                                    if (i < 0) {branch2 = ERROR_POP; continue BRANCH2;}

                                    act_value = AREF(context, this.action_table, i);
                                    if (act_value.isNil()) {
                                        D_puts(this, "(err) table[i] == nil");
                                        branch2 = ERROR_POP; continue BRANCH2;
                                    }
                                    act = (int)act_value.convertToInteger().getLongValue();
                                    D_printf(this, "(err) table[i]=%ld\n", act);

                                    tmp = AREF(context, this.action_check, i);
                                    if (tmp.isNil()) {
                                        D_puts(this, "(err) check[i] == nil");
                                        branch2 = ERROR_POP; continue BRANCH2;
                                    }
                                    if ((int)tmp.convertToInteger().getLongValue() != this.curstate) {
                                        D_puts(this, "(err) check[i] != k1");
                                        branch2 = ERROR_POP; continue BRANCH2;
                                    }

                                    D_puts(this, "(err) found: can handle error token");
                                    break BRANCH2;

                                case ERROR_POP:
                                    D_puts(this, "(err) act not found: can't handle error token; pop");

                                    if (this.state.size() <= 1) {
                                        this.retval = context.nil;
                                        this.fin = CP_FIN_CANTPOP;
                                        return;
                                    }
                                    POP(context, this.state);
                                    POP(context, this.vstack);
                                    this.curstate = (int)LAST_I(context, this.state).convertToInteger().getLongValue();
                                    if (this.debug) {
                                        POP(context, this.tstack);
                                        this.parser.callMethod(context, id_d_e_pop.toString(),
                                                new IRubyObject[]{this.state, this.tstack, this.vstack});
                                    }
                            }
                        }

                        /* shift/reduce error token */
                        if (act > 0 && act < this.shift_n) {
                            D_puts(this, "e shift");
                            SHIFT(runtime, act, runtime.newFixnum(TokenType.ERROR.id), val);
                        }
                        else if (act < 0 && act > -(this.reduce_n)) {
                            D_puts(this, "e reduce");
                            REDUCE(context, act);
                        }
                        else if (act == this.shift_n) {
                            D_puts(this, "e accept");
                            branch = ACCEPT; continue BRANCH;
                        }
                        else {
                            throw runtime.newRaiseException(RaccBug, "[Cparse Bug] unknown act value " + act);
                        }
                        branch = ERROR_RECOVERED; continue BRANCH;
                }
            }
        }

        private void shift(Ruby runtime, int act, IRubyObject tok, IRubyObject val) {
            PUSH(vstack, val);
            if (debug) {
                PUSH(tstack, tok);
                parser.callMethod(id_d_shift.toString(),
                        new IRubyObject[]{tok, tstack, vstack});
            }
            curstate = act;
            PUSH(state, runtime.newFixnum(curstate));
        }

        private int reduce(ThreadContext context, int act) {
            IRubyObject code;
            ruleno = -act * 3;
            IRubyObject tag = context.runtime.newSymbol("racc_jump");
            RubyContinuation rbContinuation = new RubyContinuation(context.runtime, context.runtime.newSymbol("racc_jump"));
            try {
                context.pushCatch(rbContinuation.getContinuation());
                code = reduce0(context);
                errstatus = (int)parser.getInstanceVariable(id_errstatus.toString()).convertToInteger().getLongValue();
            } finally {
                context.popCatch();
            }
            return (int)code.convertToInteger().getLongValue();
        }

        private IRubyObject reduce0(ThreadContext context) {
            Ruby runtime = context.runtime;

            IRubyObject reduce_to, reduce_len, method_id;
            int len;
            RubySymbol mid;
            IRubyObject tmp, tmp_t = RubyBasicObject.UNDEF, tmp_v = RubyBasicObject.UNDEF;
            int i, k1 = 0, k2;
            IRubyObject goto_state = context.nil;

            reduce_len = this.reduce_table.entry(this.ruleno);
            reduce_to  = this.reduce_table.entry(this.ruleno+1);
            method_id  = this.reduce_table.entry(this.ruleno+2);
            len = (int)reduce_len.convertToInteger().getLongValue();
            mid = value_to_id(context, method_id);

            int branch = 0;
            BRANCH: while (true) {
                switch (branch) {
                    case 0:

                        /* call action */
                        if (len == 0) {
                            tmp = context.nil;
                            if (mid != id_noreduce)
                                tmp_v = runtime.newArray();
                            if (this.debug)
                                tmp_t = runtime.newArray();
                        }
                        else {
                            if (mid != id_noreduce) {
                                tmp_v = GET_TAIL(context, this.vstack, len);
                                tmp = ((RubyArray)tmp_v).entry(0);
                            }
                            else {
                                tmp = this.vstack.entry(this.vstack.size() - len);
                            }
                            CUT_TAIL(context, this.vstack, len);
                            if (this.debug) {
                                tmp_t = GET_TAIL(context, this.tstack, len);
                                CUT_TAIL(context, this.tstack, len);
                            }
                            CUT_TAIL(context, this.state, len);
                        }
                        if (mid != id_noreduce) {
                            if (this.use_result_var) {
                                tmp = this.parser.callMethod(mid.toString(),
                                        new IRubyObject[]{tmp_v, this.vstack, tmp});
                            }
                            else {
                                tmp = this.parser.callMethod(mid.toString(),
                                        new IRubyObject[]{tmp_v, this.vstack});
                            }
                        }

                        /* then push result */
                        PUSH(this.vstack, tmp);
                        if (this.debug) {
                            PUSH(this.tstack, reduce_to);
                            this.parser.callMethod(id_d_reduce.toString(),
                                    new IRubyObject[]{tmp_t, reduce_to, this.tstack, this.vstack});
                        }

                        /* calculate transition state */
                        if (state.size() == 0)
                            throw runtime.newRaiseException(RaccBug, "state stack unexpectedly empty");
                        k2 = (int)LAST_I(context, this.state).convertToInteger().getLongValue();
                        k1 = (int)reduce_to.convertToInteger().getLongValue() - this.nt_base;
                        D_printf(this, "(goto) k1=%ld\n", k1);
                        D_printf(this, "(goto) k2=%ld\n", k2);

                        tmp = AREF(context, this.goto_pointer, k1);
                        if (tmp.isNil()) {branch = NOTFOUND; continue BRANCH;}

                        i = (int)tmp.convertToInteger().getLongValue() + k2;
                        D_printf(this, "(goto) i=%ld\n", i);
                        if (i < 0) {branch = NOTFOUND; continue BRANCH;}

                        goto_state = AREF(context, this.goto_table, i);
                        if (goto_state.isNil()) {
                            D_puts(this, "(goto) table[i] == nil");
                            branch = NOTFOUND; continue BRANCH;
                        }
                        D_printf(this, "(goto) table[i]=%ld (goto_state)\n", goto_state.convertToInteger().getLongValue());

                        tmp = AREF(context, this.goto_check, i);
                        if (tmp.isNil()) {
                            D_puts(this, "(goto) check[i] == nil");
                            branch = NOTFOUND; continue BRANCH;
                        }
                        if (tmp != runtime.newFixnum(k1)) {
                            D_puts(this, "(goto) check[i] != table[i]");
                            branch = NOTFOUND; continue BRANCH;
                        }
                        D_printf(this, "(goto) check[i]=%ld\n", tmp.convertToInteger().getLongValue());

                        D_puts(this, "(goto) found");

                    case TRANSIT:
                        PUSH(this.state, goto_state);
                        this.curstate = (int)goto_state.convertToInteger().getLongValue();
                        return runtime.newFixnum(0);

                    case NOTFOUND:
                        D_puts(this, "(goto) not found: use default");
                        /* overwrite `goto-state' by default value */
                        goto_state = AREF(context, this.goto_default, k1);
                        branch = TRANSIT; continue BRANCH;
                }
            }
        }

        Parser parser;          /* parser object */

        boolean lex_is_iterator;
        IRubyObject lexer;           /* scanner object */
        RubySymbol lexmid;          /* name of scanner method (must be an iterator) */

        /* State transition tables (immutable)
           Data structure is from Dragon Book 4.9 */
        /* action table */
        IRubyObject action_table;
        IRubyObject action_check;
        IRubyObject action_default;
        IRubyObject action_pointer;
        /* goto table */
        IRubyObject goto_table;
        IRubyObject goto_check;
        IRubyObject goto_default;
        IRubyObject goto_pointer;

        int nt_base;         /* NonTerminal BASE index */
        RubyArray reduce_table;    /* reduce data table */
        IRubyObject token_table;     /* token conversion table */

        /* parser stacks and parameters */
        RubyArray state;
        int curstate;
        RubyArray vstack;
        RubyArray tstack;
        IRubyObject t;
        int shift_n;
        int reduce_n;
        int ruleno;

        int errstatus;         /* nonzero in error recovering mode */
        int nerr;              /* number of error */

        boolean use_result_var;

        IRubyObject retval;           /* return IRubyObject of parser routine */
        int fin;               /* parse result status */

        boolean debug;              /* user level debug */
        boolean sys_debug;          /* system level debug */

        int i;                 /* table index */
    }

    private static void D_puts(CparseParams v, String msg) {
        if (v.sys_debug) {
            System.out.println(msg);
        }
    }

    private static void D_printf(CparseParams v, String fmt, long arg) {
        if (v.sys_debug) {
            System.out.format(fmt, arg);
        }
    }

    public class Parser extends RubyObject {
        public Parser(Ruby runtime, RubyClass rubyClass) {
            super(runtime, rubyClass);
        }

        public static final String Racc_Runtime_Core_Version_C = RACC_VERSION;
        public static final String Racc_Runtime_Core_Id_C = "$originalId: cparse.c,v 1.8 2006/07/06 11:39:46 aamine Exp $";

        @JRubyMethod(name = "_racc_do_parse_c", frame = true)
        public IRubyObject racc_cparse(ThreadContext context) {
            CparseParams v = (CparseParams)getInstanceVariable("@vparams");

            v.parse_main(context, context.nil, context.nil, false);

            return v.retval;
        }

        @JRubyMethod(name = "_racc_yyparse_c", frame = true)
        public IRubyObject racc_yyparse(ThreadContext context, IRubyObject lexer, IRubyObject lexmid) {
            Ruby runtime = context.runtime;
            CparseParams v = new CparseParams(context.runtime, CparseParams);

            v.sys_debug = false;

            D_puts(v, "start C yyparse");
            v.initialize_params(context, this, lexer, lexmid);
            v.lex_is_iterator = true;
            D_puts(v, "params initialized");
            v.parse_main(context, context.nil, context.nil, false);
            call_lexer(context, v);
            if (v.fin == 0) {
                throw runtime.newArgumentError(v.lexmid + " is finished before EndOfToken");
            }

            return v.retval;
        }

        private void call_lexer(ThreadContext context, final CparseParams v) {
            final int frame = context.getFrameJumpTarget();
            try {
                Helpers.invoke(context, v.lexer, v.lexmid.toString(), v, CallBlock19.newCallClosure(v, v.getMetaClass(), Arity.ONE_ARGUMENT, new BlockCallback() {
                    @Override
                    public IRubyObject call(ThreadContext context, IRubyObject[] args, Block block) {
                        Ruby runtime = context.getRuntime();
                        if (v.fin != 0) {
                            throw runtime.newArgumentError("extra token after EndOfToken");
                        }
                        IRubyObject[] tokVal = {null, null};
                        v.extract_user_token(context, args[0], tokVal);
                        v.parse_main(context, tokVal[0], tokVal[1], true);
                        if (v.fin != 0 && v.fin != CP_FIN_ACCEPT) {
                            throw new JumpException.BreakJump(frame, context.nil);
                        }

                        return context.nil;
                    }
                }, context));
            } catch (JumpException.BreakJump bj) {
                if (bj.getTarget() == frame) {
                    return;
                }
            }
        }

        private RubyArray assert_array(IRubyObject a) {
            return a.convertToArray();
        }

        private RubyHash assert_hash(IRubyObject h) {
            return h.convertToHash();
        }

        private long assert_integer(IRubyObject i) {
            return i.convertToInteger().getLongValue();
        }

        public IRubyObject initialize(ThreadContext context) {
            Ruby runtime = context.runtime;
            CparseParams v = new CparseParams(context.runtime, CparseParams);

            setInstanceVariable("@vparams", v);

            IRubyObject nil = context.nil;

            setInstanceVariable(id_yydebug.toString(), nil);
            setInstanceVariable(id_action_table.toString(), nil);
            setInstanceVariable(id_action_check.toString(), nil);
            setInstanceVariable(id_action_default.toString(), nil);
            setInstanceVariable(id_action_pointer.toString(), nil);
            setInstanceVariable(id_goto_table.toString(), nil);
            setInstanceVariable(id_goto_check.toString(), nil);
            setInstanceVariable(id_goto_default.toString(), nil);
            setInstanceVariable(id_goto_pointer.toString(), nil);
            setInstanceVariable(id_nt_base.toString(), nil);
            setInstanceVariable(id_reduce_table.toString(), nil);
            setInstanceVariable(id_token_table.toString(), nil);
            setInstanceVariable(id_shift_n.toString(), nil);
            setInstanceVariable(id_reduce_n.toString(), nil);
            setInstanceVariable(id_use_result.toString(), nil);
            
            D_puts(v, "starting cparse");
            v.sys_debug = true;
            v.initialize_params(context, this, nil, nil);
            v.lex_is_iterator = true;

            return this;
        }
    }

    public void load(Ruby runtime, boolean wrap) {
        RubyModule racc = runtime.getOrCreateModule("Racc");
        RubyClass parser = racc.defineOrGetClassUnder("Parser", runtime.getObject());
        parser.setAllocator(new ObjectAllocator() {
            @Override
            public IRubyObject allocate(Ruby ruby, RubyClass rubyClass) {
                return new Parser(ruby, rubyClass);
            }
        });

        parser.defineAnnotatedMethods(Parser.class);

        parser.defineConstant("Racc_Runtime_Core_Version_C", runtime.newString(Parser.Racc_Runtime_Core_Version_C));
        parser.defineConstant("Racc_Runtime_Core_Id_C", runtime.newString(Parser.Racc_Runtime_Core_Id_C));

        CparseParams = racc.defineClassUnder("CparseParams", runtime.getObject(), new ObjectAllocator() {
            @Override
            public IRubyObject allocate(Ruby ruby, RubyClass rubyClass) {
                return new CparseParams(ruby, rubyClass);
            }
        });

        RaccBug = runtime.getRuntimeError();

        id_yydebug      = runtime.newSymbol("@yydebug");
        id_nexttoken    = runtime.newSymbol("next_token");
        id_onerror      = runtime.newSymbol("on_error");
        id_noreduce     = runtime.newSymbol("_reduce_none");
        id_errstatus    = runtime.newSymbol("@racc_error_status");

        id_d_shift       = runtime.newSymbol("racc_shift");
        id_d_reduce      = runtime.newSymbol("racc_reduce");
        id_d_accept      = runtime.newSymbol("racc_accept");
        id_d_read_token  = runtime.newSymbol("racc_read_token");
        id_d_next_state  = runtime.newSymbol("racc_next_state");
        id_d_e_pop       = runtime.newSymbol("racc_e_pop");

        id_action_table   = runtime.newSymbol("@action_table");
        id_action_check   = runtime.newSymbol("@action_check");
        id_action_default = runtime.newSymbol("@action_default");
        id_action_pointer = runtime.newSymbol("@action_pointer");
        id_goto_table     = runtime.newSymbol("@goto_table");
        id_goto_check     = runtime.newSymbol("@goto_check");
        id_goto_default   = runtime.newSymbol("@goto_default");
        id_goto_pointer   = runtime.newSymbol("@goto_pointer");
        id_nt_base        = runtime.newSymbol("@nt_base");
        id_reduce_table   = runtime.newSymbol("@reduce_table");
        id_token_table    = runtime.newSymbol("@token_table");
        id_shift_n        = runtime.newSymbol("@shift_n");
        id_reduce_n       = runtime.newSymbol("@reduce_n");
        id_use_result     = runtime.newSymbol("@use_result");
    }
}
