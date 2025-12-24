# getopt.c3l - A Familiar Args Parser
A GNU getopt library analog for parsing command-line arguments in C3 projects, with some extra C3 spice on top.


## Usage
To use the options parser, start by importing `opt` into your module.

You now have 4 functions to choose from for parsing command-line options:
- `opt::get` - An equivalent to the C `getopt` library function, for quick parsing of short options (`-a -b 123 -c somestr` or `-ab123 -csomestr`).
- `opt::get_long` - An equivalent for [GNU's `getopt_long` function](https://www.gnu.org/software/libc/manual/html_node/Getopt-Long-Options.html), for getting mixed long and short options (`--alpha --bravo=123 -csomestr` or `-ab123 --charlie somestr`).
- `opt::get_long_only` - Also [from GNU](https://www.gnu.org/software/libc/manual/html_node/Getopt-Long-Options.html#index-getopt_005flong_005fonly), but supports POSIX-style long options and doesn't attempt to collate short options (`--alpha --bravo 123` or `-alpha -bravo 123` or `-a -b 123`, but __not__ `-ab123`).
- `opt::@parse` - A C3 macro designed to cut out a lot of the typical `getopt` ceremony and consume option values straight into destination variables.


## "C3 Spice"? wat
Enter the compile-time `opt::@parse` macro, inspired by [D-lang's std.getopt module](https://dlang.org/phobos/std_getopt.html), but not exactly the same.

```c3
macro int? opt::@parse(#args, ...);
```

Provide a `String[]` slice of command-line arguments as the first parameter, then variadic arguments must come in sets of 3 at a time for each defined option (this is checked at compile-time):
- An _optional_ short-name value (or `""` or `null`).
- An _optional_ long-name value (or `""` or `null`).
- A _required_ reference to a properly-typed variable or an arg-parsing callback with the signature `fn void? (String)`.

There must be at least one of the two names for any option definition.

The generated code behaves according to the _pointer types_ you've given to each triple.

```c3
bool has_short_name;
String optional_val;
uint ctr;

if (catch err = opt::@parse(
	args,
	"s" , "short-name", &has_short_name,
	"o?", "optional"  , &optional_val,
	null, "counter+"  , &ctr,
	null, "help*"     , null
)) {
	switch (err)
	{
		case opt::HELP_REQUESTED:
		case opt::MISSING_ARGUMENT:
		case opt::ILLEGAL_OPTION:
			show_help();
		default:
			// i.e., INVALID_INTEGER, OUT_OF_BOUNDS, etc.
			something_else_is_wrong();
	}
	return err;
}
```

#### Option Type Specifiers
You may notice the `*`, `?`, and `+` characters on the tail end of some options in the above sample. These are referenced in the code as "option type specifiers", and they give the compiler a bit more information about the behavior of the storage variable.

```
   '+' : Incremental - Every time the flag appears, increment the specified [numeric] type.
   '?' : Optional - Inherits the classic "optional argument" behavior from GNU getopt.
                     When the flag is seen, it may or may not have an argument with it.
   '*' : Help - When this flag is encountered, it indicates an explicit request for help/usage.
```

## Examples
The below usage examples reference/populate this struct:

```c3
// Look at all these different types we can auto-populate.
struct ArgsResult
{
	bool        has_alpha;
	bool        has_bravo;
	isz         charlie;
	float       delta;
	ZString     echo;
	uint        fox;
	char[3]     golf;
	String[3]   hotel;
	char        india;
	int128      juliet;
	bool        has_kilo;
	SomeEnum    lima;
}

ArgsResult t;
```

### C3-style `opt::@parse`
For your convenience. :tm:

Take a look at my own usage of this in a CLI application [here](https://github.com/NotsoanoNimus/mftah_cli/blob/3dc5bc69a26b297db025b7deebf53d03f82340c9/src/main.c3#L81). It summarized away the entire hellish arguments parsing loop, without a ton of mystery about what's going on.

```c3
int end_index = opt::@parse(
	args,
	"a" ,   "alpha",    &t.has_alpha,   // bool/flag
	"b" ,   "bravo",    &t.has_bravo,   // bool/flag
	"c" ,   "charlie",  &t.charlie,   // integer
	"d" ,   "delta",    &t.delta,   // float
	"e?",   "echo",     &t.echo,   // '?' means 'optional argument'
	"f" ,   "fox+",     &t.fox,   // '+' means 'incremental argument' (val++ each time flag is seen)
	"g" ,   "golf",     &t.golf,   // char array
	"h" ,   "hotel",    &t.hotel,   // string array
	"i" ,   "india",    &get_india_value,   // callback
	null,   "juliet",   &t.juliet,   // empty shortopt
	"k" ,   null,       &t.has_kilo,   // empty longopt
	"l" ,   "lima",     &t.lima,   // an enum
	"Z*",   "help",     null,   // explicit request for help/usage
)!;
```

```
Input :  { "program-name", "-abc123", "--delta=0.74", "-e", "--fox",
           "--", "nonopt", "these options", "-c3", "-dont", "get", "parsed" },

Output:  { .has_alpha = true, .has_bravo = true,
           .charlie = 123, .delta = 0.74, .fox = 1 }

Return:  6   // indexof("--") + 1 - the would-be index of the first value
             //   after the stop marker, if any are present
```

### opt::get
Short options only.

```c3
// intentionally leaves out 'juliet' which, following the example, is supposed to a longopt ONLY
int retval;
while (-1 != (retval = opt::get(args, "abc:d:e::fg:h:i:kZ")))
{
	switch (retval) {
		case 'Z': // fallthrough - help request
		case ':': // fallthrough - getopt error
		case '?': help(); /* or return a fault */
		case 'a': t.has_alpha = true;
		case 'b': t.has_bravo = true;
		case 'c': t.charlie = opt::arg.to_integer(isz.typeid)!;
		case 'd': t.delta = opt::arg.to_float()!;
		case 'e': if (opt::arg.ptr != null) t.echo = (ZString)opt::arg.ptr;   // note: optional arg!
		case 'f': ++t.fox;
		case 'g':
			if (golf_index >= t.golf.len) return opt::OUT_OF_BOUNDS?;
			t.golf[golf_index++] = opt::arg[0];
		case 'h':
			if (hotel_index >= t.hotel.len) return opt::OUT_OF_BOUNDS?;
			t.hotel[hotel_index++] = opt::arg;
		// `get_india_value` just grabs the third character from the arg
		case 'i': get_india_value(opt::arg)!;   // custom callback function to set t.india from arg
		/* not listed */ case 'x': t.juliet = opt::arg.to_integer(int128.typeid)!;
		case 'k': t.has_kilo = true;
	}
}
```

```
Input :  { "program-name", "-ad0.7", "-gg", "-go", "-i", "werp" }
Output:  { .has_alpha = true, .delta = 0.7, .golf = { 'g', 'o', 0 }, .india = 'r' }
Return:  6   // args.len
```

### opt::get_long & opt::get_long_only
Long options, or long options with POSIX support (`--longopt` + `-longopt`). These are used the exact same way, so only `getopt_long` is shown.

```c3
// intentionally leaves out 'kilo' which, following the example, is supposed to a SHORT option ONLY
int retval, longopt_idx;
LongOption[] longopts = {
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
	{ "help",       NO_ARGUMENT,        null,   'Z' }
};
while (-1 != (retval = opt::get_long(args, "abc:d:e::fg:h:i:kZ", longopts, &longopt_idx)))
{
	switch (retval) {
		case 'Z': // fallthrough - help request
		case ':': // fallthrough - getopt error
		case '?': help(); /* or return a fault */
		case 'a': t.has_alpha = true;
		case 'b': t.has_bravo = true;
		case 'c': t.charlie = opt::arg.to_integer(isz.typeid)!;
		case 'd': t.delta = opt::arg.to_float()!;
		case 'e': if (opt::arg.ptr != null) t.echo = (ZString)opt::arg.ptr;   // note: optional arg!
		case 'f': ++t.fox;
		case 'g':
			if (golf_index >= t.golf.len) return opt::OUT_OF_BOUNDS?;
			t.golf[golf_index++] = opt::arg[0];
		case 'h':
			if (hotel_index >= t.hotel.len) return opt::OUT_OF_BOUNDS?;
			t.hotel[hotel_index++] = opt::arg;
		// `get_india_value` just grabs the third character from the arg
		case 'i': get_india_value(opt::arg)!;   // custom callback function to set t.india from arg
		case 'x': t.juliet = opt::arg.to_integer(int128.typeid)!;
		/* not listed */ case 'k': t.has_kilo = true;
	}
}
```

Notice how the short and long options can mix in such a way that `getopt_long` supports everything that `getopt` itself does with short options.
```
Input :  { "program-name", "-esomething", "-fff", "-haaa", "--fox",
           "-ad0.4", "--hotel", "beauty at work" },

Output:  { .has_alpha = true, .delta = 0.4, .echo = "something",
           .fox = 4, .hotel = { "aaa", "beauty at work", "" } }

Return:  8   // args.len
```
