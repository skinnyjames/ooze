#ifndef MRUBY_UTF8PROC
#define MRUBY_UTF8PROC

#include <mruby.h>
#include <mruby/class.h>
#include <mruby/string.h>
#include "mruby/value.h"
#include "utf8proc.h"

/*
  From https://unicodefyi.com/glossary/code-space/
  The code space is the complete range of integer values available for Unicode code points: U+0000 through U+10FFFF,
*/
#define UNICODE_LIMIT 0x10FFFF
#define UNICODE_REPLACE 0xFFFD

static mrb_value mrb_utf8_char_width(mrb_state* mrb, mrb_value self)
{
  mrb_int ambiguous_size;
  mrb_bool option;
  mrb_get_args(mrb, "|i?", &ambiguous_size, &option);

  if (!option)
  {
    ambiguous_size = 2;
  }

  mrb_int width = 0;
  mrb_int codepoint = mrb_integer(self);
  if (codepoint >= 0 && codepoint <= UNICODE_LIMIT)
  {
    if (utf8proc_charwidth_ambiguous(codepoint))
    {
      width = ambiguous_size;
    }
    else
    {
      width = utf8proc_charwidth(codepoint);
    }

    return mrb_int_value(mrb, width);
  }
  else 
  {
    mrb_raise(mrb, E_RANGE_ERROR, "Codepoint not valid Unicode");
  }
}

static mrb_value mrb_utf8_str_codepoints(mrb_state* mrb, mrb_value self)
{
  if (!mrb_frozen_p(mrb_str_ptr(self)))
  {
    mrb_raise(mrb, E_RUNTIME_ERROR, "Cannot iterate codepoints on a mutable string");
  }

  mrb_int replace;
  mrb_bool option;
  mrb_value block;
  mrb_get_args(mrb, "|i?&!", &replace, &option, &block);
  
  if (!option)
  {
    replace = UNICODE_REPLACE;
  }

  const utf8proc_uint8_t* ref = (const utf8proc_uint8_t *)RSTRING_PTR(self);
  const utf8proc_ssize_t len = (utf8proc_ssize_t)RSTRING_LEN(self);

  utf8proc_int32_t codepoint;
  utf8proc_ssize_t read = 0;
  ssize_t cursor = 0;

  while (cursor < len)
  {
    // decode codepoint
    read = utf8proc_iterate(ref + cursor, len - cursor, &codepoint);
    // bad byte
    if (read < 0)
    {
      mrb_yield(mrb, block, mrb_int_value(mrb, replace));
      cursor += 1;
      continue;
    }

    mrb_yield(mrb, block, mrb_int_value(mrb, codepoint));
    cursor += read;
  }

  return mrb_nil_value();
}

static mrb_value mrb_utf8_str_width(mrb_state* mrb, mrb_value self)
{
  mrb_int ambiguous_size;
  mrb_bool option;
  mrb_get_args(mrb, "|i?", &ambiguous_size, &option);

  if (!option)
  {
    ambiguous_size = 2;
  }

  const utf8proc_uint8_t* ref = (const utf8proc_uint8_t *)RSTRING_PTR(self);
  const utf8proc_ssize_t len = (utf8proc_ssize_t)RSTRING_LEN(self);

  utf8proc_int32_t codepoint;
  utf8proc_ssize_t read = 0;
  ssize_t cursor = 0;
  mrb_int width = 0;

  while (cursor < len)
  {
    // decode codepoint
    read = utf8proc_iterate(ref + cursor, len - cursor, &codepoint);
    // bad byte
    if (read < 0)
    {
      width += 1;
      cursor += 1;
      continue;
    }

    if (utf8proc_charwidth_ambiguous(codepoint))
    {
      width += ambiguous_size;
    }
    else
    {
      width += utf8proc_charwidth(codepoint);
    }

    cursor += read;
  }

  return mrb_int_value(mrb, width);
}

void mrb_mruby_utf8proc_gem_init(mrb_state* mrb)
{
  struct RClass* strklass = mrb_class_get(mrb, "String");
  mrb_define_method(mrb, strklass, "width", mrb_utf8_str_width, MRB_ARGS_OPT(1));
  mrb_define_method(mrb, strklass, "codepoints_each", mrb_utf8_str_codepoints, MRB_ARGS_OPT(1) | MRB_ARGS_BLOCK());

  struct RClass* intklass = mrb_class_get(mrb, "Integer");
  mrb_define_method(mrb, intklass, "charwidth", mrb_utf8_char_width, MRB_ARGS_OPT(1));
}

void mrb_mruby_utf8proc_gem_final(mrb_state* mrb)
{

}

#endif