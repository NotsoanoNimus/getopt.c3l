// Copyright (c) 2025 Zack Puhl <github@xmit.xyz>. All rights reserved.
// Use of this source code is governed by the MIT license,
// a copy of which can be found in the LICENSE_STDLIB file.
//
// Provides some comprehensive tests of argument parsing capabilities with the opt module.
module opt_tests;

import opt;
import std::io;


faultdef TEST_FAILURE;

<*
 @require @typeis(left, $typeof(right))
*>
macro bool struct_cmp(left, right)
{
    $foreach $member : $typeof(left).membersof:
        $assert $defined($member.get(left) != $member.get(right)) : "All struct members must support the == operator";
        if ($member.get(left) != $member.get(right)) return false;
    $endforeach
    return true;
}

struct TestResult (Printable)
{
    bool has_alpha;
    bool has_bravo;
    isz charlie;
    float delta;
    ZString echo;
    uint fox;
    char[3] golf;
    String[3] hotel;
    char india;
    int128 juliet;
    bool has_kilo;
}

TestResult t;
int longopt_index, golf_index, hotel_index;

fn void? get_india_value(String arg)
{
    if (arg.len < 3) return TEST_FAILURE?;

    t.india = arg[2];
}


fn bool TestResult.eq(self, TestResult other) @operator(==) => struct_cmp(self, other);

fn usz? TestResult.to_format(&self, Formatter* f) @dynamic
    => f.printf(
        "[A(%s) B(%s) C(%s) D(%s) E(%s) F(%s) G(%s) H(%s) I(%s) J(%s) K(%s)]",
        self.has_alpha, self.has_bravo, self.charlie, self.delta, self.echo, self.fox, self.golf, self.hotel, self.india, self.juliet, self.has_kilo
    )!;


fn void fresh()
{
    opt::@reset();
    t = {};
    longopt_index = golf_index = hotel_index = 0;
}


const OPTION_STR = "abc:d:e::fg:h:i:k";   // notice no 'juliet' here

const LongOption[] LONGOPTS = {
    { "alpha",      NO_ARGUMENT,        null,   'a' },
    { "bravo",      NO_ARGUMENT,        null,   'b' },
    { "charlie",    REQUIRED_ARGUMENT,  null,   'c' },
    { "delta",      REQUIRED_ARGUMENT,  null,   'd' },
    { "echo",       OPTIONAL_ARGUMENT,  null,   'e' },
    { "fox",        NO_ARGUMENT,        null,   'f' },
    { "golf",       REQUIRED_ARGUMENT,  null,   'g' },
    { "hotel",      REQUIRED_ARGUMENT,  null,   'h' },
    { "india",      REQUIRED_ARGUMENT,  null,   'i' },
    { "juliet",     REQUIRED_ARGUMENT,  null,   'x' },   // ... but juliet is indicated by 'x'
    // notice no 'kilo' here -- short opt only
};


fn int? parse_test(String[] args) =>
    opt::@parse(
        args,
        "a" ,   "alpha",    &t.has_alpha,
        "b" ,   "bravo",    &t.has_bravo,
        "c" ,   "charlie",  &t.charlie,
        "d" ,   "delta",    &t.delta,
        "e?",   "echo",     &t.echo,
        "f" ,   "fox+",     &t.fox,
        "g" ,   "golf",     &t.golf,
        "h" ,   "hotel",    &t.hotel,
        "i" ,   "india",    &get_india_value,
        ""  ,   "juliet",   &t.juliet,   // empty shortopt
        "k"  ,  "",         &t.has_kilo,   // empty longopt
    )!;

fn void? getopt_test(String[] args)
{
    int retval;
    while (-1 != (retval = opt::get(args, OPTION_STR))) common_switch(retval)!;
}

fn void? getopt_long_test(String[] args)
{
    int retval;
    while (-1 != (retval = opt::get_long(args, OPTION_STR, LONGOPTS, &longopt_index))) common_switch(retval)!;
}

fn void? getopt_long_only_test(String[] args)
{
    int retval;
    while (-1 != (retval = opt::get_long_only(args, OPTION_STR, LONGOPTS, &longopt_index))) common_switch(retval)!;
}

fn void? common_switch(int retval) @local
{
    io::printf("[consume opt retval] ==> '%d' ... ", retval);

    switch (retval)
    {
        case ':':
        case '?':
            io::printn("(MISSING_ARGUMENT)");
            return opt::MISSING_ARGUMENT?;

        case 'a': t.has_alpha = true; io::printn("(alpha)");
        case 'b': t.has_bravo = true; io::printn("(bravo)");
        case 'c': t.charlie = opt::arg.to_integer(isz.typeid)!; io::printn("(charlie)");
        case 'd': t.delta = opt::arg.to_float()!; io::printn("(delta)");
        case 'e': if (opt::arg.ptr != null) t.echo = (ZString)opt::arg.ptr; io::printn("(echo)");
        case 'f': ++t.fox; io::printn("(fox)");

        case 'g':
            io::printf("(golf:%d)\n", golf_index);
            if (golf_index >= t.golf.len) return opt::OUT_OF_BOUNDS?;
            if (opt::arg.len == 0 || !opt::arg.ptr) return opt::MISSING_ARGUMENT?;
            t.golf[golf_index] = opt::arg[0];
            ++golf_index;

        case 'h':
            io::printf("(hotel:%d)\n", hotel_index);
            if (hotel_index >= t.hotel.len) return opt::OUT_OF_BOUNDS?;
            if (opt::arg.len == 0 || !opt::arg.ptr) return opt::MISSING_ARGUMENT?;
            t.hotel[hotel_index] = opt::arg;
            ++hotel_index;

        case 'i':
            io::printn("(india)");
            if (opt::arg.len > 0 && *opt::arg.ptr)
            {
                get_india_value(opt::arg)!;
            }
            else
            {
                return opt::MISSING_ARGUMENT?;
            }

        case 'x':   // juliet
            t.juliet = opt::arg.to_integer(int128.typeid)!;
            io::printn("(juliet)");

        case 'k':
            t.has_kilo = true;
            io::printn("(kilo)");
    }
}


// =====================================================================================================================
// =====================================================================================================================
// =====================================================================================================================
module opt_tests @test;

import opt;
import std::io;

enum CallType : const inline int @local
{
    SHORT,
    LONG,
    LONG_ONLY,
    PARSE,
}


faultdef NON_FAULT;


macro void? @run_each(#args, #expected, fault expected_fault = NON_FAULT) @local
{
    @run(SHORT, #args, #expected, expected_fault)!;
    @run(LONG,  #args, #expected, expected_fault)!;
    @run(PARSE, #args, #expected, expected_fault)!;
}

macro void? @run_each_has_long(#args, #expected, fault expected_fault = NON_FAULT) @local
{
    @run(LONG,  #args, #expected, expected_fault)!;
    @run(PARSE, #args, #expected, expected_fault)!;
}

macro void? @run(CallType $test_type, #args, #expected, fault expected_fault = NON_FAULT) @local
{
    String[] args;
    TestResult expected;

    fresh();   // fresh test
    assert(t == (TestResult){}, "Static TestResult `t` was not cleared before another test started.");

    // 'args' is always prepended with a dummy value to mimic the ever-present '$0'
    args = { "program-name" , ...(String[])#args };   

    expected = #expected;   // set expected value from param expression

    io::printf("\n=== NEW RUN === >>> %s\n", $test_type);
    foreach(i, a : args) io::printf("---> ARG[%d]: %s\n", i, a);

    var $torun;
    $switch ($test_type) :
        $case PARSE : $torun = "parse_test";
        $case SHORT : $torun = "getopt_test";
        $case LONG : $torun = "getopt_long_test";
        $case LONG_ONLY : $torun = "getopt_long_only_test";

        $default : unreachable("Invalid $test_type CT enum value.");
    $endswitch

    if (NON_FAULT == expected_fault)
    {
        $eval($torun)(args)!;
        test::@check(t == expected, "\r\n\tExpected: %s\r\n\tActual t: %s", expected, t);
    }
    else
    {
        test::@error($eval($torun)(args), expected_fault);
    }

    io::printn("===============");
}


fn void sanity_check_result_comparisons()
{
    TestResult left = { true, true, 123, 0.012312, "zstr", 90, {'a', 'x', 'd' }, { "str", "123", "xyz" }, 'w', 123412341234123412341234, true };

    TestResult right = { true, true, 123, 0.012312, "zstr", 90, {'a', 'x', 'd' }, { "str", "___", "xyz" }, 'w', 123412341234123412341234, true };
    test::@check(left != right);

    right = { true, true, 123, 0.012312, "zstr", 90, {'a', 'x', 'd' }, { "str", "123", "xyz" }, 'w', 123412341234123412341234, true };
    test::@check(left == right);

    right = { true, false, 123, 0.012312, "zstr", 90, {'a', 'x', 'd' }, { "str", "123", "xyz" }, 'w', 123412341234123412341234, true };
    test::@check(left != right);

    right = { true, true, 123, 0.012312, "a zstr", 90, {'a', 'x', 'd' }, { "str", "123", "xyz" }, 'w', 123412341234123412341234, true };
    test::@check(left != right);
}


fn void simple_all()
{
    @run_each({ "-b" }, { .has_bravo = true })!!;
    test::@check(opt::ind == 2, "opt::ind must equal the length of the args slice +1 when all values are consumed.");   // only need to check this a few times

    @run_each({ "-a", "-c", "1234" }, { .has_alpha = true, .has_bravo = false, .charlie = 1234 })!!;
    test::@check(opt::ind == 4, "opt::ind must equal the length of the args slice +1 when all values are consumed.");
    @run_each({ "-ac", "1234" }, { .has_alpha = true, .has_bravo = false, .charlie = 1234 })!!;
    test::@check(opt::ind == 3, "opt::ind must equal the length of the args slice +1 when all values are consumed.");
    @run_each({ "-bc", "888" }, { .has_alpha = false, .has_bravo = true, .charlie = 888 })!!;
    test::@check(opt::ind == 3, "opt::ind must equal the length of the args slice +1 when all values are consumed.");

    @run_each({ "-d0.7", "-gg", "-go", "-i", "werp" }, { .delta = 0.7, .golf = { 'g', 'o', 0 }, .india = 'r' })!!;

    @run_each_has_long(
        { "-abc123", "--delta=0.74", "-e", "--fox", "--", "nonopt", "these options", "-c3", "-dont", "get", "parsed" },
        { .has_alpha = true, .has_bravo = true, .charlie = 123, .delta = 0.74, .fox = 1 }
    )!!;
    test::@check(opt::ind == 6, "opt::ind must equal the location where arguments are cut off or stopped with a single double-prefix.");

    @run_each_has_long({ `--echo=all by myself` }, { .echo = `all by myself` })!!;
    @run_each_has_long({ `-e'all by myself'` }, { .echo = `'all by myself'` })!!;
    @run_each_has_long({ `-be`, `all by myself` }, { .has_bravo = true, .echo = {} })!!;   // spaces after optionals do not apply the optional arg

    @run_each_has_long(
        { "-esomething", "-fff", "-haaa", "--fox", "-ad0.4", "--hotel", "beauty how it works innit" },
        { .has_alpha = true, .delta = 0.4, .echo = "something", .fox = 4, .hotel = { "aaa", "beauty how it works innit", "" } }
    )!!;
}


// Literally just `simple_all` w/ a different prefix
fn void different_prefix()
{
    opt::prefix = '/';

    @run_each({ "/b" }, { .has_bravo = true })!!;
    @run_each({ "/a", "/c", "1234" }, { .has_alpha = true, .has_bravo = false, .charlie = 1234 })!!;
    @run_each({ "/ac", "1234" }, { .has_alpha = true, .has_bravo = false, .charlie = 1234 })!!;
    @run_each({ "/bc", "888" }, { .has_alpha = false, .has_bravo = true, .charlie = 888 })!!;

    @run_each({ "/d0.7", "/gg", "/go", "/i", "werp" }, { .delta = 0.7, .golf = { 'g', 'o', 0 }, .india = 'r' })!!;

    @run_each_has_long(
        { "/abc123", "//delta=0.74", "/e", "//fox", "//", "nonopt", "these options", "/c3", "/dont", "get", "parsed" },
        { .has_alpha = true, .has_bravo = true, .charlie = 123, .delta = 0.74, .fox = 1 }
    )!!;
    test::@check(opt::ind == 6, "opt::ind must equal the location where arguments are cut off or stopped with a single double-prefix.");

    @run_each_has_long({ `//echo=all by myself` }, { .echo = `all by myself` })!!;
    @run_each_has_long({ `/e'all by myself'` }, { .echo = `'all by myself'` })!!;
    @run_each_has_long({ `/be`, `all by myself` }, { .has_bravo = true, .echo = {} })!!;   // spaces after optionals do not apply the optional arg

    @run_each_has_long(
        { "/esomething", "/fff", "/haaa", "//fox", "/ad0.4", "//hotel", "beauty how it works innit" },
        { .has_alpha = true, .delta = 0.4, .echo = "something", .fox = 4, .hotel = { "aaa", "beauty how it works innit", "" } }
    )!!;

    opt::prefix = opt::DEFAULT_PREFIX;   // set it back
}


// Test '+', ':', or '-' prefix to option_str.
fn void special_option_strings()
{
}


fn void callbacks()
{
    @run_each({ "-c456", "-ai", "xyzabc" }, { .charlie = 456, .has_alpha = true, .india = 'z' })!!;
    @run_each({ "-i", "xyzabc" }, { .india = 'z' })!!;

    @run_each_has_long({ "--india", "xyzabc" }, { .india = 'z' })!!;
    @run_each_has_long({ "-c3", "--india", "xyzabc" }, { .charlie = 3, .india = 'z' })!!;
}


fn void exclusive_short_long_opts()
{
    @run_each_has_long({ "-ab", "--juliet=500" }, { .has_alpha = true, .has_bravo = true, .juliet = 500 })!!;
    @run_each({ "-abk" }, { .has_alpha = true, .has_bravo = true, .has_kilo = true })!!;

    // Ensure long/short options which aren't supposed to be there... aren't.
    // @run_each({ "-ab", "-j5" }, { .has_alpha = true, .has_bravo = true, .juliet = 0 }, opt::MISSING_ARGUMENT)!!;
    // @run_each_has_long({ "-ab", "--kilo" }, { .has_alpha = true, .has_bravo = true, .has_kilo = false }, opt::MISSING_ARGUMENT)!!;

    @run(LONG, { "--alpha", "--juliet", "17000" }, { .has_alpha = true, .juliet = 17000 })!!;
    test::@check(opt::ind == 4, "opt::ind must equal the length of the args slice +1 when all values are consumed.");
}


fn void simple_failures()
{
    // Missing arguments.
    // @run(SHORT, { "-a", "-c", "1234" }, { .has_alpha = true, .has_bravo = false, .charlie = 1234 })!!;
    // @run(SHORT, { "-ac", "1234" }, { .has_alpha = true, .has_bravo = false, .charlie = 1234 })!!;
    // @run(SHORT, { "-bc", "888" }, { .has_alpha = false, .has_bravo = true, .charlie = 888 })!!;
}
