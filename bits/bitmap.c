/* vi:set sw=4: */

#include <stdio.h>
#include <stdlib.h>

#include "ruby.h"


#define BITS 8

struct bmap {
    long size;
    long bits;
    char *p;
};

static VALUE Bitmap;


static void
bitmap_free(p)
    struct bmap *p;
{
    free(p->p);
    free(p);
}

static void
bmcheck(v)
    VALUE v;
{
    Check_Type(v, T_DATA);
    if (RDATA(v)->dfree == bitmap_free) return;
    rb_raise(rb_eTypeError, "not Bitmap");
}


static VALUE
bitmap_s_new(klass, len)
    VALUE klass, len;
{
    struct bmap *p;

    p = ALLOC(struct bmap);
    p->bits = NUM2LONG(len);
    p->size = p->bits / BITS + 1;
    if (p->size <= 0)
        rb_raise(rb_eIndexError, "negative index for Bitmap.new");
    p->p = ALLOC_N(char, p->size);
    memset(p->p, 0, p->size);
    return Data_Wrap_Struct(klass, 0, bitmap_free, p);
}

static VALUE
bitmap_size(self)
    VALUE self;
{
    struct bmap *p;

    Data_Get_Struct(self, struct bmap, p);
    return INT2NUM(p->bits);
}

static VALUE
bitmap_aref(self, idx)
    VALUE self, idx;
{
    struct bmap *p;
    int mask;
    long i;

    Data_Get_Struct(self, struct bmap, p);
    i = NUM2LONG(idx);
    if (i < 0)
        rb_raise(rb_eIndexError, "negative index for Bitmap#[]");
    if (i >= p->bits)
        rb_raise(rb_eIndexError, "too big index for Bitmap#[]");
    mask = 1;
    mask <<= (i % BITS);
    i = (*(p->p + (i / BITS)) & mask) ? 1 : 0;
    return INT2FIX(i);
}

static VALUE
bitmap_set(self, idx)
    VALUE self, idx;
{
    struct bmap *p;
    long i;
    int mask;

    Data_Get_Struct(self, struct bmap, p);
    i = NUM2LONG(idx);
    if (i < 0)
        rb_raise(rb_eIndexError, "negative index for Bitmap#set");
    if (i >= p->bits)
        rb_raise(rb_eIndexError, "too big index for Bitmap#set");
    mask = 1;
    mask <<= (i % BITS);
    *(p->p + (i / BITS)) |= mask;

    return idx;
}

static VALUE
bitmap_updor(self, other)
    VALUE self, other;
{
    struct bmap *dest, *src;
    long i;

    Data_Get_Struct(self, struct bmap, dest);
    bmcheck(other);
    Data_Get_Struct(other, struct bmap, src);
    if (src->size > dest->size)
        rb_raise(rb_eArgError, "src is bigger than dest");
    for (i = 0; i < src->size; i++)
        dest->p[i] |= src->p[i];

    return self;
}

static VALUE
bitmap_clear(self)
    VALUE self;
{
    struct bmap *p;

    Data_Get_Struct(self, struct bmap, p);
    memset(p->p, 0, p->size);

    return Qnil;
}

static VALUE
bitmap_inspect(self)
    VALUE self;
{
    struct bmap *p;
    VALUE ret;
    int mask;
    long b, i, j;

    Data_Get_Struct(self, struct bmap, p);
    ret = rb_str_new2("#<Bitmap ");
    b = 0;
    for (i = 0; i < p->size; i++) {
        mask = 1;
        for (j = 0; j < BITS && b < p->bits; j++, b++) {
            if (p->p[i] & mask)
                rb_str_cat(ret, "1", 1);
            else
                rb_str_cat(ret, "0", 1);
            mask <<= 1;
        }
    }
    rb_str_cat(ret, ">", 1);

    return ret;
}

void
Init_bitmap()
{
    Bitmap = rb_define_class("Bitmap", rb_cObject);
    rb_define_singleton_method(Bitmap, "new", bitmap_s_new, 1);
    rb_define_method(Bitmap, "size", bitmap_size, 0);
    rb_define_method(Bitmap, "[]", bitmap_aref, 1);
    rb_define_method(Bitmap, "set", bitmap_set, 1);
    rb_define_method(Bitmap, "updor", bitmap_updor, 1);
    rb_define_method(Bitmap, "clear", bitmap_clear, 0);
    rb_define_method(Bitmap, "inspect", bitmap_inspect, 0);
}
