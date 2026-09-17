#include <ruby.h>
#include <ruby/encoding.h>
#include "teptris/teptris.h"
#include "teptris/plan.h"

/* flags: bit0 = datetimes as strings, bit1 = forbid Time, bit2 = forbid Date */
#define FMT_STRING_DATES 1
#define FMT_FORBID_TIME 2
#define FMT_FORBID_DATE 4

static VALUE eParseError, eError, cDate;

/* civil date -> days since epoch (Hinnant, inverse of the dump side) */
static int64_t days_from_civil(int32_t y, uint8_t m, uint8_t d) {
    y -= m <= 2;
    int64_t era = (y >= 0 ? y : y - 399) / 400;
    uint32_t yoe = (uint32_t)(y - era * 400);
    uint32_t doy = (uint32_t)(153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1;
    uint32_t doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + (int64_t)doe - 719468;
}

/* exact (no double) Time materialization: nsec stays nsec. Offset
 * datetimes go through timespec+fixed-offset; local datetimes through
 * Time.local with Rational seconds (rb_time_timespec_new's INT_MAX
 * treats the timespec as an absolute instant, not wall-clock local). */
static VALUE time_from_dt(const teptris_datetime *d, bool has_offset) {
    if (has_offset) {
        int64_t days = days_from_civil(d->year, d->month, d->day);
        int64_t secs =
            days * 86400 + d->hour * 3600 + d->minute * 60 + d->second;
        struct timespec ts;
        ts.tv_sec = (time_t)(secs - d->offset_seconds);
        ts.tv_nsec = (long)d->nanosecond;
        return rb_time_timespec_new(&ts, d->offset_seconds);
    }
    VALUE args[6] = {INT2FIX(d->year), INT2FIX(d->month), INT2FIX(d->day),
                     INT2FIX(d->hour), INT2FIX(d->minute),
                     rb_Rational(LL2NUM((int64_t)d->second * 1000000000 +
                                        d->nanosecond),
                                 LL2NUM(1000000000))};
    return rb_funcallv(rb_cTime, rb_intern("local"), 6, args);
}

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
            return time_from_dt(&d, kind == TEPTRIS_DATETIME_OFFSET);
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

/* ------------------------------------------------------------------ dump */

static ID id_utc_offset, id_to_s;

static void dump_check(teptris_status st) {
    if (st == TEPTRIS_OK) return;
    if (st == TEPTRIS_ERR_ALLOC)
        rb_raise(eError, "out of memory while dumping");
    rb_raise(eError, "cannot dump value (%s)", teptris_status_string(st));
}

/* days since 1970-01-01 -> proleptic-Gregorian y/m/d (Hinnant) */
static void civil_from_days(int64_t z, int32_t *y, uint8_t *m, uint8_t *d) {
    z += 719468;
    int64_t era = (z >= 0 ? z : z - 146096) / 146097;
    uint32_t doe = (uint32_t)(z - era * 146097);
    uint32_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    int64_t yy = (int64_t)yoe + era * 400;
    uint32_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    uint32_t mp = (5 * doy + 2) / 153;
    uint32_t dd = doy - (153 * mp + 2) / 5 + 1;
    uint32_t mm = mp < 10 ? mp + 3 : mp - 9;
    if (mm <= 2) yy++;
    *y = (int32_t)yy;
    *m = (uint8_t)mm;
    *d = (uint8_t)dd;
}

/* two crossings per Time: timespec + utc_offset; the civil fields come
 * from integer math (epoch + offset -> y/m/d h:m:s + tv_nsec) */
static void fill_dt_from_time(VALUE v, teptris_datetime *dt) {
    struct timespec ts = rb_time_timespec(v);
    dt->offset_seconds = NUM2INT(rb_funcall(v, id_utc_offset, 0));
    int64_t secs = (int64_t)ts.tv_sec + dt->offset_seconds;
    int64_t days = secs / 86400;
    int32_t rem = (int32_t)(secs % 86400);
    if (rem < 0) { /* floor division: keep rem in [0, 86400) */
        rem += 86400;
        days -= 1;
    }
    civil_from_days(days, &dt->year, &dt->month, &dt->day);
    dt->hour = (uint8_t)(rem / 3600);
    dt->minute = (uint8_t)((rem / 60) % 60);
    dt->second = (uint8_t)(rem % 60);
    dt->nanosecond = (uint32_t)ts.tv_nsec;
}

static void dump_scalar(teptris_builder *b, const char *key, size_t klen,
                        VALUE v) {
    switch (TYPE(v)) {
    case T_STRING:
        dump_check(teptris_builder_put_string(b, key, klen, RSTRING_PTR(v),
                                              (size_t)RSTRING_LEN(v)));
        return;
    case T_TRUE:
    case T_FALSE:
        dump_check(teptris_builder_put_boolean(b, key, klen, RTEST(v)));
        return;
    case T_FIXNUM: /* T_INTEGER on 3.2+; T_FIXNUM spans every ruby we build */
    case T_BIGNUM: /* NUM2LL raises RangeError outside int64 */
        dump_check(teptris_builder_put_integer(b, key, klen, NUM2LL(v)));
        return;
    case T_FLOAT:
        dump_check(teptris_builder_put_float(b, key, klen, RFLOAT_VALUE(v)));
        return;
    default:
        if (rb_obj_is_kind_of(v, rb_cTime)) {
            teptris_datetime dt = {0};
            fill_dt_from_time(v, &dt);
            dump_check(teptris_builder_put_datetime(
                b, key, klen, TEPTRIS_DATETIME_OFFSET, &dt));
            return;
        }
        if (rb_obj_is_kind_of(v, cDate)) {
            /* DateTime is a Date subclass: dumps its date part, as the
             * Ruby-era dump writers did. One crossing: jd -> civil. */
            teptris_datetime dt = {0};
            int64_t jd = NUM2LL(rb_funcall(v, rb_intern("jd"), 0));
            civil_from_days(jd - 2440588, &dt.year, &dt.month, &dt.day);
            dump_check(teptris_builder_put_datetime(b, key, klen,
                                                    TEPTRIS_DATE_LOCAL, &dt));
            return;
        }
        rb_raise(eError, "cannot dump %s", rb_obj_classname(v));
    }
}

static void build_value(teptris_builder *b, VALUE v);

static int table_each(VALUE key, VALUE val, VALUE data) {
    teptris_builder *b = (teptris_builder *)data;
    if (!RB_TYPE_P(key, T_STRING))
        key = rb_funcall(key, id_to_s, 0);
    const char *kp = RSTRING_PTR(key);
    size_t kl = (size_t)RSTRING_LEN(key);
    if (RB_TYPE_P(val, T_HASH)) {
        dump_check(teptris_builder_open_table(b, kp, kl));
        rb_hash_foreach(val, table_each, (VALUE)b);
        dump_check(teptris_builder_close(b));
    } else if (RB_TYPE_P(val, T_ARRAY)) {
        long n = RARRAY_LEN(val);
        bool all_hash = n > 0;
        for (long i = 0; i < n; i++) {
            if (!RB_TYPE_P(RARRAY_AREF(val, i), T_HASH)) {
                all_hash = false;
                break;
            }
        }
        dump_check(all_hash ? teptris_builder_open_array(b, kp, kl)
                            : teptris_builder_open_inline_array(b, kp, kl));
        for (long i = 0; i < n; i++)
            build_value(b, RARRAY_AREF(val, i));
        dump_check(teptris_builder_close(b));
    } else {
        dump_scalar(b, kp, kl, val);
    }
    return ST_CONTINUE;
}

/* element position: no key */
static void build_value(teptris_builder *b, VALUE v) {
    if (RB_TYPE_P(v, T_HASH)) {
        dump_check(teptris_builder_open_table(b, NULL, 0));
        rb_hash_foreach(v, table_each, (VALUE)b);
        dump_check(teptris_builder_close(b));
    } else if (RB_TYPE_P(v, T_ARRAY)) {
        long n = RARRAY_LEN(v);
        /* element arrays are inline territory: the builder pins them */
        dump_check(teptris_builder_open_array(b, NULL, 0));
        for (long i = 0; i < n; i++)
            build_value(b, RARRAY_AREF(v, i));
        dump_check(teptris_builder_close(b));
    } else {
        dump_scalar(b, NULL, 0, v);
    }
}

static VALUE ext_dump(VALUE self, VALUE obj) {
    if (!RB_TYPE_P(obj, T_HASH))
        rb_raise(rb_eArgError, "cannot dump %s (root must be a Hash)",
                 rb_obj_classname(obj));
    teptris_builder *b = teptris_builder_new();
    if (b == NULL)
        rb_raise(eError, "out of memory while dumping");
    rb_hash_foreach(obj, table_each, (VALUE)b);
    teptris_document *doc = NULL;
    teptris_status st = teptris_builder_finish(b, &doc);
    if (st != TEPTRIS_OK) {
        teptris_builder_free(b);
        rb_raise(eError, "cannot dump (%s)", teptris_status_string(st));
    }
    char *buf = NULL;
    size_t len = 0;
    st = teptris_document_emit(doc, &buf, &len);
    teptris_document_free(doc);
    teptris_builder_free(b); /* doc already transferred/freed */
    if (st != TEPTRIS_OK)
        rb_raise(eError, "dump failed (%s)", teptris_status_string(st));
    VALUE out = rb_enc_str_new(buf, (long)len, rb_utf8_encoding());
    free(buf);
    return out;
}

/* ------------------------------------------------- plan-walk (teptris#46) */

static void plan_free(void *p) { teptris_plan_free((teptris_plan *)p); }

static const rb_data_type_t plan_type = {
    "Teptris/plan",
    {0, plan_free, 0, {0, 0}},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

/* Native assembly over a walked result: plan row metadata drives a
 * recursive builder; RAW rows re-use obj_from_node; datetime scalars
 * mirror obj_from_node's native policy (Time/Date/canonical time
 * string). Unmatched rows materialize as nil. */
static VALUE asm_rows(const teptris_plan *p, const teptris_plan_result *res,
                      uint32_t plan_idx)
{
    uint32_t n = teptris_plan_row_count(p, plan_idx);
    VALUE h = rb_hash_new();
    for (uint32_t i = 0; i < n; i++) {
        VALUE k = rb_str_new_cstr(teptris_plan_row_name_at(p, plan_idx, i));
        VALUE val = Qnil;
        switch (teptris_plan_result_kind_at(res, i)) {
        case TEPTRIS_PLAN_SCALAR_RESULT: {
            teptris_datetime d;
            switch (teptris_plan_result_value_kind_at(res, i)) {
            case TEPTRIS_STRING: {
                teptris_view v;
                if (teptris_plan_result_string_at(res, i, &v) == TEPTRIS_OK) {
                    val = rb_enc_str_new(v.ptr, (long)v.len, rb_utf8_encoding());
                }
                break;
            }
            case TEPTRIS_INTEGER: {
                int64_t iv;
                if (teptris_plan_result_integer_at(res, i, &iv) == TEPTRIS_OK) {
                    val = LL2NUM(iv);
                }
                break;
            }
            case TEPTRIS_FLOAT: {
                double dv;
                if (teptris_plan_result_float_at(res, i, &dv) == TEPTRIS_OK) {
                    val = DBL2NUM(dv);
                }
                break;
            }
            case TEPTRIS_BOOLEAN: {
                bool bv;
                if (teptris_plan_result_boolean_at(res, i, &bv) == TEPTRIS_OK) {
                    val = bv ? Qtrue : Qfalse;
                }
                break;
            }
            case TEPTRIS_DATETIME_OFFSET:
            case TEPTRIS_DATETIME_LOCAL:
                if (teptris_plan_result_datetime_at(res, i, &d) == TEPTRIS_OK) {
                    val = time_from_dt(&d,
                                       teptris_plan_result_value_kind_at(res, i) ==
                                           TEPTRIS_DATETIME_OFFSET);
                }
                break;
            case TEPTRIS_DATE_LOCAL:
                if (teptris_plan_result_datetime_at(res, i, &d) == TEPTRIS_OK) {
                    val = rb_funcall(cDate, rb_intern("new"), 3,
                                     INT2FIX(d.year), INT2FIX(d.month),
                                     INT2FIX(d.day));
                }
                break;
            case TEPTRIS_TIME_LOCAL:
                if (teptris_plan_result_datetime_at(res, i, &d) == TEPTRIS_OK) {
                    val = dt_string(&d, TEPTRIS_TIME_LOCAL);
                }
                break;
            default:
                break;
            }
            break;
        }
        case TEPTRIS_PLAN_ARRAY: {
            uint32_t n2 = teptris_plan_result_array_len_at(res, i);
            val = rb_ary_new_capa(n2);
            for (uint32_t j = 0; j < n2; j++) {
                switch (teptris_plan_result_array_kind_at(res, i, j)) {
                case TEPTRIS_PLAN_SCALAR_RESULT: {
                    teptris_datetime d;
                    switch (teptris_plan_result_array_value_kind_at(res, i,
                                                                    j)) {
                    case TEPTRIS_STRING: {
                        teptris_view v;
                        if (teptris_plan_result_array_string_at(res, i, j, &v) ==
                            TEPTRIS_OK) {
                            rb_ary_push(val, rb_enc_str_new(
                                                 v.ptr, (long)v.len,
                                                 rb_utf8_encoding()));
                        }
                        break;
                    }
                    case TEPTRIS_INTEGER: {
                        int64_t iv;
                        if (teptris_plan_result_array_integer_at(res, i, j,
                                                                 &iv) ==
                            TEPTRIS_OK) {
                            rb_ary_push(val, LL2NUM(iv));
                        }
                        break;
                    }
                    case TEPTRIS_FLOAT: {
                        double dv;
                        if (teptris_plan_result_array_float_at(res, i, j, &dv) ==
                            TEPTRIS_OK) {
                            rb_ary_push(val, DBL2NUM(dv));
                        }
                        break;
                    }
                    case TEPTRIS_BOOLEAN: {
                        bool bv;
                        if (teptris_plan_result_array_boolean_at(res, i, j,
                                                                 &bv) ==
                            TEPTRIS_OK) {
                            rb_ary_push(val, bv ? Qtrue : Qfalse);
                        }
                        break;
                    }
                    case TEPTRIS_DATETIME_OFFSET:
                    case TEPTRIS_DATETIME_LOCAL:
                    case TEPTRIS_DATE_LOCAL:
                    case TEPTRIS_TIME_LOCAL:
                        if (teptris_plan_result_array_datetime_at(res, i, j,
                                                                  &d) ==
                            TEPTRIS_OK) {
                            rb_ary_push(
                                val,
                                teptris_plan_result_array_value_kind_at(
                                    res, i, j) == TEPTRIS_DATE_LOCAL
                                    ? rb_funcall(cDate, rb_intern("new"), 3,
                                                 INT2FIX(d.year),
                                                 INT2FIX(d.month),
                                                 INT2FIX(d.day))
                                    : dt_string(&d, TEPTRIS_TIME_LOCAL));
                        }
                        break;
                    default:
                        rb_ary_push(val, Qnil);
                        break;
                    }
                    break;
                }
                case TEPTRIS_PLAN_TABLE: {
                    teptris_plan_result *sub =
                        teptris_plan_result_array_entry_at(res, i, j);
                    if (sub != NULL) {
                        rb_ary_push(val, asm_rows(
                                             p, sub,
                                             teptris_plan_row_sub_at(p, plan_idx,
                                                                  i)));
                        teptris_plan_result_view_free(sub);
                    }
                    break;
                }
                default:
                    rb_ary_push(val, Qnil);
                    break;
                }
            }
            break;
        }
        case TEPTRIS_PLAN_TABLE: {
            teptris_plan_result *sub = teptris_plan_result_row_view(res, i);
            if (sub != NULL) {
                val = asm_rows(p, sub, teptris_plan_row_sub_at(p, plan_idx, i));
                teptris_plan_result_view_free(sub);
            }
            break;
        }
        case TEPTRIS_PLAN_RAW_RESULT: {
            const teptris_node *raw = teptris_plan_result_raw_at(res, i);
            if (raw != NULL) {
                val = obj_from_node(raw, 0);
            }
            break;
        }
        default:
            break;
        }
        rb_hash_aset(h, k, val);
    }
    return h;
}

static VALUE ext_plan_build(VALUE self, VALUE rows, VALUE first_row)
{
    Check_Type(rows, T_ARRAY);
    Check_Type(first_row, T_ARRAY);
    long nrows = RARRAY_LEN(rows);
    long nplans = RARRAY_LEN(first_row) - 1;
    if (nplans < 1 || nrows < 1) {
        rb_raise(eError, "plan needs >= 1 plan and >= 1 row");
    }
    teptris_plan_row *crows = calloc((size_t)nrows, sizeof(*crows));
    /* bytes-vs-count: this must be (nplans+1) * sizeof(uint32_t) — the
     * byte-sized malloc overflows the heap and musl's allocator segfaults
     * where glibc/darwin absorb it */
    uint32_t *cfirst = malloc(((size_t)nplans + 1) * sizeof(*cfirst));
    if (crows == NULL || cfirst == NULL) {
        free(crows);
        free(cfirst);
        rb_raise(eError, "out of memory building plan");
    }
    for (long i = 0; i < nrows; i++) {
        VALUE row = rb_ary_entry(rows, i);
        Check_Type(row, T_ARRAY);
        VALUE name = rb_ary_entry(row, 0);
        SafeStringValue(name);
        crows[i].name = strdup(StringValueCStr(name));
        crows[i].kind = (uint8_t)NUM2UINT(rb_ary_entry(row, 1));
        crows[i].sub = (uint32_t)NUM2UINT(rb_ary_entry(row, 2));
    }
    for (long i = 0; i <= nplans; i++) {
        cfirst[i] = (uint32_t)NUM2UINT(rb_ary_entry(first_row, i));
    }
    teptris_plan_spec spec = {TEPTRIS_PLAN_ABI_VERSION, (uint32_t)nplans,
                              crows, cfirst};
    teptris_status st;
    teptris_plan *plan = teptris_plan_build(&spec, &st);
    free(crows);
    free(cfirst);
    if (plan == NULL) {
        rb_raise(eError, "invalid plan spec (status %d)", (int)st);
    }
    return TypedData_Wrap_Struct(rb_cObject, &plan_type, plan);
}

static VALUE ext_plan_emit(VALUE self, VALUE rb_plan, VALUE toml)
{
    teptris_plan *plan;
    TypedData_Get_Struct(rb_plan, teptris_plan, &plan_type, plan);
    StringValue(toml);
    teptris_document *doc = NULL;
    teptris_status st =
        teptris_parse(RSTRING_PTR(toml), (size_t)RSTRING_LEN(toml), NULL, &doc);
    if (st != TEPTRIS_OK) {
        const teptris_error *e = teptris_document_error(doc);
        VALUE ex = rb_exc_new(eParseError, e->message, (long)strlen(e->message));
        rb_iv_set(ex, "@line", SIZET2NUM(e->line));
        rb_iv_set(ex, "@column", SIZET2NUM(e->column));
        teptris_document_free(doc);
        rb_exc_raise(ex);
    }
    teptris_plan_result *res =
        teptris_plan_walk(plan, teptris_document_root(doc), &st);
    if (res == NULL) {
        teptris_document_free(doc);
        rb_raise(eError, "plan walk failed (status %d)", (int)st);
    }
    VALUE out = asm_rows(plan, res, 0);
    teptris_plan_result_free(res);
    teptris_document_free(doc);
    return out;
}

void Init_teptris_ext(void) {
    VALUE m = rb_define_module("TeptrisExt");
    rb_define_module_function(m, "load", ext_load, -1);
    rb_define_module_function(m, "dump", ext_dump, 1);
    rb_define_module_function(m, "engine_version", ext_version, 0);
    rb_define_module_function(m, "plan_build", ext_plan_build, 2);
    rb_define_module_function(m, "plan_emit", ext_plan_emit, 2);
    /* error/version load first (teptris.rb), then the ext bundle */
    VALUE t = rb_const_get(rb_cObject, rb_intern("Teptris"));
    eError = rb_const_get(t, rb_intern("Error"));
    eParseError = rb_const_get(t, rb_intern("ParseError"));
    rb_funcall(rb_mKernel, rb_intern("require"), 1, rb_str_new_cstr("date"));
    cDate = rb_const_get(rb_cObject, rb_intern("Date"));
    id_utc_offset = rb_intern("utc_offset");
    id_to_s = rb_intern("to_s");
}
