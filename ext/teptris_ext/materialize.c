#include <ruby.h>
#include <time.h>
#include "teptris/teptris.h"
#include <ruby/encoding.h>

static VALUE cParseError, cDate;

static VALUE obj_from_node(const teptris_node *n) {
    switch (teptris_node_kind(n)) {
    case TEPTRIS_TABLE: {
        size_t len = teptris_node_table_length(n);
        VALUE h = rb_hash_new();
        
        for (size_t i = 0; i < len; i++) {
            teptris_view key;
            const teptris_node *v = teptris_node_table_at(n, i, &key);
            rb_hash_aset(h,
                rb_enc_str_new(key.ptr, (long)key.len, rb_utf8_encoding()),
                obj_from_node(v));
        }
        return h;
    }
    case TEPTRIS_ARRAY: {
        size_t len = teptris_node_array_length(n);
        VALUE a = rb_ary_new_capa((long)len);
        for (size_t i = 0; i < len; i++)
            rb_ary_push(a, obj_from_node(teptris_node_array_at(n, i)));
        return a;
    }
    case TEPTRIS_STRING: {
        teptris_view s;
        teptris_node_string(n, &s);
        return rb_enc_str_new(s.ptr, (long)s.len, rb_utf8_encoding());
    }
    case TEPTRIS_INTEGER: {
        int64_t v = 0; teptris_node_integer(n, &v);
        return LL2NUM(v);
    }
    case TEPTRIS_FLOAT: {
        double v = 0; teptris_node_float(n, &v);
        return DBL2NUM(v);
    }
    case TEPTRIS_BOOLEAN: {
        bool v = false; teptris_node_boolean(n, &v);
        return v ? Qtrue : Qfalse;
    }
    default: { /* datetime kinds: tomlib contract */
        teptris_datetime d; teptris_node_datetime(n, &d);
        double sec = (double)d.second + (double)d.nanosecond / 1e9;
        VALUE args[7] = { INT2FIX(d.year), INT2FIX(d.month), INT2FIX(d.day),
                          INT2FIX(d.hour), INT2FIX(d.minute), DBL2NUM(sec) };
        switch (teptris_node_kind(n)) {
        case TEPTRIS_DATETIME_OFFSET:
            args[6] = INT2FIX(d.offset_seconds);
            return rb_funcallv(rb_cTime, rb_intern("new"), 7, args);
        case TEPTRIS_DATETIME_LOCAL:
            return rb_funcallv(rb_cTime, rb_intern("local"), 6, args);
        case TEPTRIS_DATE_LOCAL:
            return rb_funcall(cDate, rb_intern("new"), 3, args[0], args[1], args[2]);
        default: { /* local time: canonical string */
            char buf[32];
            int l = snprintf(buf, sizeof buf, "%02u:%02u:%02u", d.hour, d.minute, d.second);
            return rb_str_new(buf, l);
        }}
    }}
}

static VALUE ext_load(VALUE self, VALUE str) {
    StringValue(str);
    teptris_document *doc = NULL;
    teptris_status st = teptris_parse(RSTRING_PTR(str), (size_t)RSTRING_LEN(str), NULL, &doc);
    if (st != TEPTRIS_OK) {
        const teptris_error *e = teptris_document_error(doc);
        VALUE ex = rb_exc_new(cParseError, e->message, (long)strlen(e->message));
        rb_iv_set(ex, "@line", SIZET2NUM(e->line));
        rb_iv_set(ex, "@column", SIZET2NUM(e->column));
        teptris_document_free(doc);
        rb_exc_raise(ex);
    }
    VALUE out = obj_from_node(teptris_document_root(doc));
    teptris_document_free(doc);
    return out;
}

void Init_teptris_ext(void) {
    VALUE m = rb_define_module("TeptrisExt");
    rb_define_module_function(m, "load", ext_load, 1);
    cParseError = rb_const_get(rb_const_get(rb_cObject, rb_intern("Teptris")), rb_intern("ParseError"));
    cDate = rb_const_get(rb_const_get(rb_cObject, rb_intern("Date")), rb_intern("Date")); /* required by teptris.rb */
    
}
