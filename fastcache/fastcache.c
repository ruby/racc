/*
    $Id$

    Copyright (C) 2005 Minero Aoki

    This program is free software.
    You can distribute/modify this program under the terms of
    the GNU LGPL, Lesser General Public Licese version 2.1.
*/

#include "ruby.h"

static VALUE LALRcoreCache;

struct item_holder {
    unsigned long hashval;
    VALUE core;
    VALUE state;
    struct item_holder *next;
};

struct lalr_state_cache {
    struct item_holder **bin;
    long size;
    long num;
};

static void
lalrc_free(struct lalr_state_cache *p)
{
    struct item_holder *tmp;
    long i;

    for (i = 0; i < p->size; i++) {
        while (tmp = p->bin[i]) {
            p->bin[i] = tmp->next;
            free(tmp);
        }
    }
    free(p->bin);
    free(p);
}

#define INIT_BIN 256

static VALUE
lalrc_s_new(VALUE self)
{
    struct lalr_state_cache *cache;

    cache = ALLOC_N(struct lalr_state_cache, 1);
    cache->bin = ALLOC_N(struct item_holder*, INIT_BIN);
    cache->size = INIT_BIN;
    cache->num = 0;
    return Data_Wrap_Struct(LALRcoreCache, 0, lalrc_free, cache);
}

#define GET_LALRC(self, p) Data_Get_Struct(self, struct lalr_state_cache, p)

static void
lalrc_rehash(struct lalr_state_cache *p)
{
    struct item_holder *top = 0, *tmp = 0;
    long i;

    for (i = p->size / 2; i < p->size; i++) {
        p->bin[i] = 0;
    }
    for (i = 0; i < p->size / 2; i++) {
        if (!p->bin[i])
            continue;

        tmp = p->bin[i];
        while (tmp->next)
            tmp = tmp->next;
        tmp->next = top;
        top = p->bin[i];
        p->bin[i] = 0;
    }

    while (top) {
        tmp = top;
        top = tmp->next;
        tmp->next = 0;

        i = tmp->hashval % p->size;
        if (p->bin[i]) {
            tmp->next = p->bin[i];
            p->bin[i] = tmp;
        }
        else {
            p->bin[i] = tmp;
        }
    }
}

static int
coreeql(VALUE a, VALUE b)
{
    long i;

    /* Check_Type(a, T_ARRAY);
    Check_Type(b, T_ARRAY); */
    if (RARRAY(a)->len != RARRAY(b)->len)
        return 0;
    for (i = 0; i < RARRAY(a)->len; i++)
        if (RARRAY(a)->ptr[i] != RARRAY(b)->ptr[i])
            return 0;
    
    return 1;
}

static unsigned long
hashval(VALUE core)
{
    unsigned long v = 0;
    long i, j;

    for (i = 0; i < RARRAY(core)->len; i++) {
        v *= RARRAY(core)->ptr[i];
        v ^= RARRAY(core)->ptr[i];
    }
    return v;
}

static VALUE
lalrc_aref(VALUE self, VALUE core)
{
    struct lalr_state_cache *p;
    unsigned long v;
    long i;
    struct item_holder *ad;

    /* Check_Type(core, T_ARRAY); */
    GET_LALRC(self, p);
    v = hashval(core);
    i = v % p->size;
    ad = p->bin[i];
    while (ad) {
        if (ad->hashval == v) {
            if (coreeql(core, ad->core)) {
                return ad->state;
            }
            else {
printf(".");
            }
        }
        ad = ad->next;
    }
    return Qnil;
}

static VALUE
lalrc_add_direct(VALUE self, VALUE core, VALUE state)
{
    struct lalr_state_cache *p;
    struct item_holder *ad;
    long i;

    GET_LALRC(self, p);
    ad = ALLOC_N(struct item_holder, 1);
    ad->hashval = hashval(core);
    ad->core = core;
    ad->state = state;

    i = ad->hashval % p->size;
    ad->next = p->bin[i];
    p->bin[i] = ad;
    p->num++;
    if ((p->num / p->size) >= 1) {
        REALLOC_N(p->bin, struct item_holder*, p->size * 2);
        p->size *= 2;
        lalrc_rehash(p);
    }
    return Qnil;
}

void
Init_corecache(void)
{
    LALRcoreCache = rb_define_class("LALRcoreCache", rb_cObject);
    rb_define_singleton_method(LALRcoreCache, "new", lalrc_s_new, 0);
    rb_define_method(LALRcoreCache, "[]", lalrc_aref, 1);
    rb_define_method(LALRcoreCache, "[]=", lalrc_add_direct, 2);
}
