#include <ruby.h>
#include <ruby/encoding.h>
#include "teptris/teptris.h"

/* flags: bit0 = datetimes as strings, bit1 = forbid Time, bit2 = forbid Date */
#define FMT_STRING_DATES 1
#define FMT_FORBID_TIME 2
#define FMT_FORBID_DATE 4

static VALUE eParseError, eError, cDate;

static VALUE dt_string(const teptris_datetime *d, int kind) {
    char buf[48];
    int l;
    if (kind == TEPTRIS_DATE_LOCAL) {
        l = snprintf(buf, sizeof buf, "%04d-%02u-%02u", d->year, d->month, d->day);
    } else {
        const char *head = (kind == TEPTRIS_TIME_LOCAL) ? "" : "";
        (void)head;
        if (kind == TEPTRIS_TIME_LOCAL) {
            l = snprintf(buf, sizeof buf, "%02u:%02u:%02u", d->hour, d->minute, d->second);
        } else {
            l = snprintf(buf, sizeof buf, "%04d-%02u-%02uT%02u:%02u:%02u",
                         d->year, d->month, d->day, d->hour, d->minute, d->second);
            if (kind == TEPTRIS_DATETIME_OFFSET) {
                if (d->offset_seconds == 0) {
                    buf[l++] = 'Z';
                } else {
                    int off = d->offset_seconds, neg = off < 0;
                    if (neg) off = -off;
                    l += snprintf(buf + l, sizeof buf - l, "%c%02d:%02d",
                                  neg ? '-' : '+', off / 3600, (off % 3600) / 60);
                }
            }
        }
    }
    return rb_enc_str_new(buf, l, rb_utf8_encoding());
}

static VALUE obj_from_node(const teptris_node *n, unsigned flags) {
    switch (teptris_node_kind(n)) {
    case TEPTRIS_TABLE: {
        size_t len = teptris_node_table_length(n);
        VALUE h = rb_hash_new();
        for (size_t i = 0; i < len; i++) {
            teptris_view key;
            const teptris_node *v = teptris_node_table_at(n, i, &key);
            rb_hash_aset(h,
                rb_enc_str_new(key.ptr, (long)key.len, rb_utf8_encoding()),
                obj_from_node(v, flags));
        }
        return h;
    }
    case TEPTRIS_ARRAY: {
        size_t len = teptris_node_array_length(n);
        VALUE a = rb_ary_new_capa((long)len);
        for (size_t i = 0; i < len; i++)
            rb_ary_push(a, obj_from_node(teptris_node_array_at(n, i), flags));
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
    default: {
        teptris_datetime d; teptris_node_datetime(n, &d);
        int kind = teptris_node_kind(n);
        if (flags & FMT_STRING_DATES) return dt_string(&d, kind);
        if (kind == TEPTRIS_DATETIME_OFFSET || kind == TEPTRIS_DATETIME_LOCAL) {
            if (flags & FMT_FORBID_TIME)
                rb_raise(eError, "value materializes Time, which is not in "
                                 "permitted_classes (use datetime_policy: :string)");
            double sec = (double)d.second + (double)d.nanosecond / 1e9;
            VALUE args[7] = { INT2FIX(d.year), INT2FIX(d.month), INT2FIX(d.day),
                              INT2FIX(d.hour), INT2FIX(d.minute), DBL2NUM(sec) };
            if (kind == TEPTRIS_DATETIME_OFFSET) {
                args[6] = INT2FIX(d.offset_seconds);
                return rb_funcallv(rb_cTime, rb_intern("new"), 7, args);
            }
            return rb_funcallv(rb_cTime, rb_intern("local"), 6, args);
        }
        if (kind == TEPTRIS_DATE_LOCAL) {
            if (flags & FMT_FORBID_DATE)
                rb_raise(eError, "value materializes Date, which is not in "
                                 "permitted_classes (use datetime_policy: :string)");
            return rb_funcall(cDate, rb_intern("new"), 3,
                              INT2FIX(d.year), INT2FIX(d.month), INT2FIX(d.day));
        }
        return dt_string(&d, kind); /* local time: canonical string */
    }}
}

static teptris_document *parse_or_raise(VALUE str) {
    teptris_document *doc = NULL;
    teptris_status st = teptris_parse(RSTRING_PTR(str), (size_t)RSTRING_LEN(str), NULL, &doc);
    if (st != TEPTRIS_OK) {
        const teptris_error *e = teptris_document_error(doc);
        VALUE ex = rb_exc_new(eParseError, e->message, (long)strlen(e->message));
        rb_iv_set(ex, "@line", SIZET2NUM(e->line));
        rb_iv_set(ex, "@column", SIZET2NUM(e->column));
        teptris_document_free(doc);
        rb_exc_raise(ex);
    }
    return doc;
}

static VALUE ext_load(int argc, VALUE *argv, VALUE self) {
    VALUE str, opts;
    rb_scan_args(argc, argv, "11", &str, &opts);
    StringValue(str);
    unsigned flags = 0;
    if (!NIL_P(opts)) {
        VALUE sd = rb_hash_aref(opts, ID2SYM(rb_intern("string_datetimes")));
        VALUE ft = rb_hash_aref(opts, ID2SYM(rb_intern("forbid_time")));
        VALUE fd = rb_hash_aref(opts, ID2SYM(rb_intern("forbid_date")));
        if (RTEST(sd)) flags |= FMT_STRING_DATES;
        if (RTEST(ft)) flags |= FMT_FORBID_TIME;
        if (RTEST(fd)) flags |= FMT_FORBID_DATE;
    }
    teptris_document *doc = parse_or_raise(str);
    VALUE out = obj_from_node(teptris_document_root(doc), flags);
    teptris_document_free(doc);
    return out;
}

static VALUE ext_version(VALUE self) {
    return rb_str_new_cstr(teptris_version_string());
}

void Init_teptris_ext(void) {
    VALUE m = rb_define_module("TeptrisExt");
    rb_define_module_function(m, "load", ext_load, -1);
    rb_define_module_function(m, "engine_version", ext_version, 0);
    /* error/version load first (teptris.rb), then the ext bundle */
    VALUE t = rb_const_get(rb_cObject, rb_intern("Teptris"));
    eError = rb_const_get(t, rb_intern("Error"));
    eParseError = rb_const_get(t, rb_intern("ParseError"));
    rb_funcall(rb_mKernel, rb_intern("require"), 1, rb_str_new_cstr("date"));
    cDate = rb_const_get(rb_cObject, rb_intern("Date"));
}
