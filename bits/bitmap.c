/*
    $Id$

    Copyright (C) 2005 Minero Aoki

    This program is free software.
    You can distribute/modify this program under the terms of
    the GNU LGPL, Lesser General Public License version 2.1.
*/

#include "ruby.h"

#define BITS 8

struct bmap {
    unsigned char *ptr;
    long len;
    long capa;
};

static VALUE Bitmap;

static void
bitmap_free(void *ptr)
{
    struct bmap *p = (struct bmap *)ptr;
    free(p->ptr);
    free(p);
}

static void
bmcheck(VALUE v)
{
    Check_Type(v, T_DATA);
    if (RDATA(v)->dfree == bitmap_free) return;
    rb_raise(rb_eTypeError, "not Bitmap");
}

static VALUE
bitmap_s_new(VALUE klass, VALUE len)
{
    struct bmap *p;

    p = ALLOC(struct bmap);
    p->len = NUM2LONG(len);
    p->capa = p->len / BITS + 1;
    if (p->capa <= 0)
        rb_raise(rb_eIndexError, "negative index for Bitmap.new");
    p->ptr = ALLOC_N(char, p->capa);
    memset(p->ptr, 0, p->capa);
    return Data_Wrap_Struct(klass, 0, bitmap_free, p);
}

static VALUE
bitmap_size(VALUE self)
{
    struct bmap *p;

    Data_Get_Struct(self, struct bmap, p);
    return INT2NUM(p->len);
}

static VALUE
bitmap_aref(VALUE self, VALUE idx)
{
    struct bmap *p;
    long i;

    Data_Get_Struct(self, struct bmap, p);
    i = NUM2LONG(idx);
    if (i < 0)
        rb_raise(rb_eIndexError, "negative index for Bitmap#[]");
    if (i >= p->len)
        rb_raise(rb_eIndexError, "too big index for Bitmap#[]");
    i = (p->ptr[i/BITS] & (1 << (i%BITS))) ? 1 : 0;
    return INT2FIX(i);
}

static VALUE
bitmap_set(VALUE self, VALUE idx)
{
    struct bmap *p;
    long i;

    Data_Get_Struct(self, struct bmap, p);
    i = NUM2LONG(idx);
    if (i < 0)
        rb_raise(rb_eIndexError, "negative index for Bitmap#set");
    if (i >= p->len)
        rb_raise(rb_eIndexError, "too big index for Bitmap#set");
    p->ptr[i/BITS] |= (1 << (i%BITS));

    return idx;
}

static VALUE
bitmap_updor(VALUE self, VALUE other)
{
    struct bmap *dest, *src;
    long i;

    Data_Get_Struct(self, struct bmap, dest);
    bmcheck(other);
    Data_Get_Struct(other, struct bmap, src);
    if (src->capa > dest->capa)
        rb_raise(rb_eArgError, "src is bigger than dest");
    for (i = 0; i < src->capa; i++)
        dest->ptr[i] |= src->ptr[i];

    return self;
}

static VALUE
bitmap_clear(VALUE self)
{
    struct bmap *p;

    Data_Get_Struct(self, struct bmap, p);
    memset(p->ptr, 0, p->capa);

    return Qnil;
}

static VALUE
bitmap_inspect(VALUE self)
{
    struct bmap *p;
    VALUE result;
    int mask;
    long b, i, j;

    Data_Get_Struct(self, struct bmap, p);
    result = rb_str_new2("#<Bitmap ");
    b = 0;
    for (i = 0; i < p->capa; i++) {
        mask = 1;
        for (j = 0; j < BITS && b < p->len; j++, b++) {
            if (p->ptr[i] & mask)
                rb_str_cat(result, "1", 1);
            else
                rb_str_cat(result, "0", 1);
            mask <<= 1;
        }
    }
    rb_str_cat(result, ">", 1);

    return result;
}

void
Init_bitmap(void)
{
    Bitmap = rb_define_class("Bitmap", rb_cObject);
    rb_define_singleton_method(Bitmap, "new", bitmap_s_new, 1);
    rb_define_method(Bitmap, "size", bitmap_size, 0);
    rb_define_method(Bitmap, "length", bitmap_size, 0);
    rb_define_method(Bitmap, "[]", bitmap_aref, 1);
    rb_define_method(Bitmap, "set", bitmap_set, 1);
    rb_define_method(Bitmap, "updor", bitmap_updor, 1);
    rb_define_method(Bitmap, "clear", bitmap_clear, 0);
    rb_define_method(Bitmap, "inspect", bitmap_inspect, 0);
}
