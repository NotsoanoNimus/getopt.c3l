// getopt.c3l: primary module
//
// Copyright (c) 2025 Zack Puhl <github@xmit.xyz>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
//
// This is both a port of the classic C 'getopt' and 'getopt_long', with
//   an additional C3-specific way to use command-line options.
//
//
// Original `getopt` and `getopt_long` code translated from a FreeBSD implementation:
// /*
//  * Copyright (c) 2000 The NetBSD Foundation, Inc.
//  * All rights reserved.
//  *
//  * [Original C] code is derived from software contributed to The NetBSD Foundation
//  * by Dieter Baron and Thomas Klausner.
//  */
//
module opt;

import libc;

import std::io;
import std::math;


const BAD_CHAR = '?';
const BAD_ARG = ':';

const DEFAULT_PREFIX = '-';

enum GetoptPrefixType : const inline int @local
{
	NO_PREFIX = -1,
	D_PREFIX = 0,
	DD_PREFIX = 1,
	W_PREFIX = 2,
}

const char[1] PLACEHOLDER @local = {0};   // used to mark an empty 'place' value


enum OptionArgType : const inline int
{
	NO_ARGUMENT,
	REQUIRED_ARGUMENT,
	OPTIONAL_ARGUMENT,
	INCREMENTAL,
	CALLBACK,
}

alias OptionCallback = fn void? (String);

// Used for long options - equivalent to 'struct option' in most C projects.
struct LongOption
{
	ZString name;
	OptionArgType has_arg;
	int* flag;
	int val;
}


// Used to control getopt_long behaviors internally.
bitstruct GetoptFlags : char @local
{
	bool permute;
	bool all_args;
	bool long_only;
}


// While these are old and crusty, it helps C developers to be able to use familiar constructs almost 1-to-1.
int err = 1;   // whether to print an error message
int ind = 1;   // index into 'args' slice
int opt;   // character checked for validity
int reset;   // reset getopt scanning pointer
String arg;   // argument string associated with option

char prefix = DEFAULT_PREFIX;


// Module-local static variables.
char* place @local = &PLACEHOLDER[0];

int nonopt_start @local = -1;
int nonopt_end @local = -1;
GetoptPrefixType dash_prefix @local = NO_PREFIX;


fn void permute_args(int panonopt_start, int panonopt_end, int opt_end, String[] args) @local
{
	int nnonopts = panonopt_end - panonopt_start;
	int nopts = opt_end - panonopt_end;
	int ncycle = math::gcd(nnonopts, nopts);
	int cyclelen = (opt_end - panonopt_start) / ncycle;

	for (int i = 0; i < ncycle; ++i)
	{
		int cstart = panonopt_end + i;
		int pos = cstart;

		for (int j = 0; j < cyclelen; ++j)
		{
			pos = (pos >= panonopt_end) ? (pos - nnonopts) : (pos + nopts);

			@swap(args[pos], args[cstart]);
		}
	}
}


fn int parse_long_options(String[] args, ZString option_str, LongOption[] options, int* idx, int short_too, GetoptFlags flags) @local
{
	char* current_dash;
	usz current_argv_len;

	ZString has_equal;
	ZString current_argv = (ZString)place;

	switch (dash_prefix)
	{
		case D_PREFIX: current_dash = "-";
		case DD_PREFIX: current_dash = "--";
		case W_PREFIX: current_dash = "-W ";
		default: current_dash = "";
	}

	int match = -1;
	int exact_match = 0;
	int second_partial_match = 0;

	++ind;

	if (null != (has_equal = (ZString)libc::strchr(current_argv, '=')))
	{
		// argument found (--option=arg)
		current_argv_len = (uptr)has_equal - (uptr)current_argv;
		++has_equal;
	}
	else
	{
		current_argv_len = current_argv.len();
	}

	// Since `options` is a bounded array, no need to check for a sentinel (NULL 'name' value/entry).
	foreach (int i, option : options)
	{
		if (!option.name.len()) continue;   // skip empty names

		/* find matching long option */
		if (current_argv.str_view()[:current_argv_len] != option.name.str_view()) continue;

		if (option.name.len() == current_argv_len)
		{
			/* exact match */
			match = i;
			exact_match = 1;
			break;
		}

		// If this is a known short option, don't allow a partial match of a single character.
		if (short_too && current_argv_len == 1) continue;

		if (match == -1)
		{
			match = i;
		}
		else if (
			flags.long_only
			|| option.has_arg != options[match].has_arg
			|| option.flag != options[match].flag
			|| option.val != options[match].val
		) {
			second_partial_match = 1;
		}
	}

	if (!exact_match && second_partial_match)
	{
		/* ambiguous abbreviation */
		if (err) io::eprintf("getopt: ambiguous option -- (%s) %s\n", current_dash, current_argv);

		opt = 0;
		return BAD_CHAR;
	}

	if (match != -1)
	{
		if (options[match].has_arg == OptionArgType.NO_ARGUMENT && has_equal)
		{
			if (err) io::eprintf("getopt: option doesn't take an argument -- (%s) %s\n", current_dash, current_argv);

			// GNU sets 'opt' to 'val' regardless of flag.
			if (options[match].flag == null)
			{
				opt = options[match].val;
			}
			else
			{
				opt = 0;
			}

			return BAD_CHAR;
		}

		if (
			options[match].has_arg == OptionArgType.REQUIRED_ARGUMENT
			|| options[match].has_arg == OptionArgType.OPTIONAL_ARGUMENT
		) {
			if (has_equal)
			{
				arg = has_equal.str_view();
			}
			else if (options[match].has_arg == OptionArgType.REQUIRED_ARGUMENT)
			{
				// optional argument doesn't use next nargv
				arg = args[ind++];
			}
		}

		if (options[match].has_arg == OptionArgType.REQUIRED_ARGUMENT && (arg.ptr == null || !arg.len))
		{
			// Missing argument; leading ':' indicates no error should be generated.
			if (err) io::eprintf("getopt: option requires an argument -- (%s) %s\n", current_dash, current_argv);

			// GNU sets opt to val regardless of flag
			if (options[match].flag == null)
			{
				opt = options[match].val;
			}
			else
			{
				opt = 0;
			}

			--ind;
			return BAD_ARG;
		}
	}
	else
	{
		if (short_too)
		{
			--ind;
			return -1;
		}

		if (err) io::eprintf("getopt: unknown option -- (%s) %s\n", current_dash, current_argv);

		opt = 0;
		return BAD_CHAR;
	}

	if (idx) *idx = match;

	if (options[match].flag)
	{
		*(options[match].flag) = options[match].val;

		return 0;
	}
	else
	{
		return options[match].val;
	}
}


fn int getopt_internal(String[] args, ZString option_str, LongOption[] options, int* options_index, GetoptFlags flags) @local
{
	// NOTE: This translation explicitly prefers the GNU extensions to getopt and cuts out any #else blocks.
	char* option_letter_list_index;
	int optchar, short_too;

	if (!option_str || !option_str[0]) return -1;

	if (option_str[0] == '-')   // note: '-' here is NOT the default-prefix value
	{
		flags.all_args = true;
	}
	else if (option_str[0] == '+')
	{
		flags.permute = false;
	}

	if (option_str[0] == '+' || option_str[0] == '-') ++option_str;

	if (!ind) ind = reset = 1;
	arg = {};

	if (reset) nonopt_start = nonopt_end = -1;

	while START: (true)   // set 'start:' label
	{
		if (!reset && *place) break START;

		reset = 0;

		if (ind >= args.len)
		{
			place = &PLACEHOLDER[0];

			if (nonopt_end != -1)
			{
				permute_args(nonopt_start, nonopt_end, ind, args);

				ind -= (nonopt_end - nonopt_start);
			}
			else if (nonopt_start != -1)
			{
				ind = nonopt_start;
			}

			nonopt_start = nonopt_end = -1;
			return -1;
		}

		place = args[ind].ptr;

		if (place[0] != prefix || (((ZString)place).len() >= 2 && !place[1]))
		{
			// found a non-option...
			place = &PLACEHOLDER[0];

			if (flags.all_args)
			{
				arg = args[ind++];
				return 1;   // INORDER: GNU extension returning non-options as opt::arg on opt::opt/retval '1'.
			}

			if (!flags.permute) return -1;   // when no permutation wanted, stop parsing at first non-option

			// do permutation
			if (nonopt_start == -1)
			{
				nonopt_start = ind;
			}
			else if (nonopt_end != -1)
			{
				permute_args(nonopt_start, nonopt_end, ind, args);

				nonopt_start = ind - (nonopt_end - nonopt_start);
				nonopt_end = -1;
			}

			++ind;
			continue START;   // goto START - process next argument
		}

		if (nonopt_start != -1 && nonopt_end == -1) nonopt_end = ind;

		// if there's a '-' here, do nothing. '--' means this processing is finished
		if (((ZString)place).len() > 1 && place[1] && *++place == prefix && !place[1])
		{
			++ind;
			place = &PLACEHOLDER[0];

			// found an option, so if skipped non-options, then permute
			if (nonopt_end != -1)
			{
				permute_args(nonopt_start, nonopt_end, ind, args);
				ind -= nonopt_end - nonopt_start;
			}

			nonopt_start = nonopt_end = -1;
			return -1;
		}

		break START;
	}

	if (options.len > 0 && place != args[ind].ptr && (*place == prefix || flags.long_only))
	{
		short_too = 0;
		dash_prefix = D_PREFIX;

		if (*place == prefix)
		{
			++place;
			dash_prefix = DD_PREFIX;
		}
		else if (*place != ':' && null != libc::strchr(option_str, *place))
		{
			short_too = 1;
		}

		optchar = parse_long_options(args, option_str, options, options_index, short_too, flags);
		if (optchar != -1)
		{
			place = &PLACEHOLDER[0];
			return optchar;
		}
	}

	// If the user specified '-' and '-' isn't in options, return -1 per POSIX.
	//   Else, it is an unknown option.
	if ((optchar = (int)*place++) == (int)':'
		|| (optchar == (int)'-' && *place)
		|| null == (option_letter_list_index = libc::strchr(option_str, optchar))
	) {
		if (optchar == (int)'-' && !*place) return -1;

		if (!*place) ++ind;

		if (err) io::eprintf("getopt: invalid option -- (%d) %c\n", dash_prefix, optchar);

		opt = optchar;
		return BAD_CHAR;
	}

	// -W long option (barf)
	if (options.len > 0 && optchar == 'W' && option_letter_list_index[1] == ';')
	{
		if (*place)   // no space
		{
			asm { nop; }   // do nothing
		}
		else if (++ind >= args.len)
		{
			place = &PLACEHOLDER[0];

			if (err) io::eprintf("getopt: option requires an argument -- (%d) %c\n", dash_prefix, optchar);

			opt = optchar;
			return BAD_ARG;
		}
		else
		{
			place = args[ind];
		}

		dash_prefix = W_PREFIX;

		optchar = parse_long_options(args, option_str, options, options_index, 0, flags);
		place = &PLACEHOLDER[0];

		return optchar;
	}

	if (*++option_letter_list_index != ':')   // doesn't take arg
	{
		if (!*place) ++ind;
	}
	else   // takes an optional arg
	{
		arg = {};

		if (*place)   // no space! (optional arguments DO NOT USE A SPACE)
		{
			arg = ((ZString)place).str_view();
		}
		else if (option_letter_list_index[1] != ':')   // arg not optional
		{
			if (++ind >= args.len)
			{
				place = &PLACEHOLDER[0];

				if (err) io::eprintf("getopt: option requires an argument -- (%d) %c\n", dash_prefix, optchar);

				opt = optchar;
				return BAD_ARG;
			}
			else
			{
				arg = args[ind];
			}
		}

		place = &PLACEHOLDER[0];
		++ind;
	}

	return optchar;
}

fn int get(String[] args, ZString option_str) @public
	=> getopt_internal(args, option_str, {}, null, {});

fn int get_long(String[] args, ZString option_str, LongOption[] options, int* options_index) @public
	=> getopt_internal(args, option_str, options, options_index, { .permute = true });

fn int get_long_only(String[] args, ZString option_str, LongOption[] options, int* options_index) @public
	=> getopt_internal(args, option_str, options, options_index, { .permute = true, .long_only = true });



// ========================================================================================
// ========================================================================================
// ========================================================================================
// C3-specific declarations and components.
//

faultdef
	HELP_REQUESTED, MISSING_ARGUMENT, ILLEGAL_OPTION,
	INVALID_LONGOPT, OUT_OF_BOUNDS, INVALID_FORMAT
	;


<*
Reset all 'static' option state values to their initial states. Does not reset the option prefix.
*>
macro @reset()
{
	err = ind = 1;
	opt = reset = 0;
	arg = {};
	place = &PLACEHOLDER[0];

	nonopt_start = nonopt_end = dash_prefix = -1;
}


<*
Globally disable any error outputs to STDERR from this module.
*>
macro @disable_errors() => err = 0;

<*
Globally enable error outputs to STDERR from this module.
*>
macro @enable_errors() => err = 1;


<*
 @require @in($typeof(#args), String[])
*>
macro int? @parse(#args, ...)
{
	$assert $vacount % 3 == 0 : `Options must be specified in triplets as "[shortname]", "[longname]", {store-ptr}.`;
	var $argcount = $vacount / 3;

	// Used for sequentially filling array args for repeating options.
	//   256 of these because that's the width of one shortname, which is how the indices themselves are indexed.
	static ushort[256] array_storage_indexes;
	defer array_storage_indexes = {};   // always reset these when finished

	char $dyn_shortname = 0x80;   // dynamic shortname values start at 0x80 for longopts w/o shortopt chars

	// Set up a dynamically-filled runtime longopts.
	LongOption[$argcount] longopts;

	String $dyn_opt_str = "";   // dynamic option_str
	OptionArgType[$argcount] $ct_argstype = {};   // indexing for OptionArgType
	String[$argcount] $ct_longnames = {};   // indexing for longnames
	char[$argcount] $ct_shortnames = {};   // indexing for shortnames

	// Iterate each provided triplet and build up all compile-time indices with accurate information.
	$for var $argidx = 0, var $idx = 0; $argidx < $vacount; ++$idx, $argidx += 3:
	{ // scoped to avoid redeclarations of 'assignee' at runtime
		String $shortname = $typeof($vaconst[$argidx]) == void* &&& $vaconst[$argidx] == null ??? "" : $vaconst[$argidx];
		String $longname = $typeof($vaconst[$argidx + 1]) == void* &&& $vaconst[$argidx + 1] == null ??? "" : $vaconst[$argidx + 1];
		var assignee = $vaarg[$argidx + 2];

		$assert $longname.len > 0 ||| $shortname.len > 0 : "You must specify at least a short or a long name for each option.";

		$if $shortname.len > 0:
			$assert ($shortname[0] >= 'a' &&& $shortname[0] <= 'z')
				||| ($shortname[0] >= 'A' &&& $shortname[0] <= 'Z')
				||| ($shortname[0] >= '0' &&& $shortname[0] <= '9')
					: `Short-name options should match the following regular expression: [a-zA-Z0-9][\+\?]?`;
			$dyn_opt_str = $dyn_opt_str +++ $shortname[0];   // concat shortname onto dynamic option_str
		$endif

		// If both names are set, only ONE of them may have an argument type specifier.
		$if $defined($longname[^1], $shortname[^1]) &&& @in($longname[^1], '+', '?') &&& @in($shortname[^1], '+', '?'):
			$error "You can't have argument type specifiers (? or +) on both the short and long option names.";
		$endif

		// The third param MUST be a pointer/reference or function type.
		var $kind_of_arg = $kindof(assignee);
		$assert @in($kind_of_arg, POINTER, FUNC) : "The parameter reference " +++ $typeof(assignee).nameof +++ " is not a pointer or function type.";

		OptionArgType $has_arg = NO_ARGUMENT;   // default
		$if $kind_of_arg == FUNC ||| ! types::is_bool($typeof(assignee).inner): // Only 'bool*' types represent flags, which do not have arguments.
			$switch:
			$case ($longname.len >= 2 &&& $longname[^1] == '?') ||| ($shortname.len >= 2 &&& $shortname[1] == '?'): $has_arg = OPTIONAL_ARGUMENT;
			$case ($longname.len >= 2 &&& $longname[^1] == '+') ||| ($shortname.len >= 2 &&& $shortname[1] == '+'): $has_arg = INCREMENTAL;   // incremental types do not accept arguments
			$case $kind_of_arg == FUNC: $has_arg = CALLBACK;
			$default: $has_arg = REQUIRED_ARGUMENT;
			$endswitch

			$if $has_arg == INCREMENTAL:
				$assert $defined(*assignee) &&& types::is_int($typeof(*assignee))
					: @sprintf("Incremental option '%s' must be a pointer to an integer type, but got '%s' instead",
						$shortname[^1] == '+' ? $shortname : $longname, $typeof(assignee).nameof);
			$endif

			$if $shortname.len > 0:
				$switch $has_arg:
				$case OPTIONAL_ARGUMENT: $dyn_opt_str = $dyn_opt_str +++ "::";
				$case REQUIRED_ARGUMENT:
				$case CALLBACK: $dyn_opt_str = $dyn_opt_str +++ ":";
				$endswitch
			$endif
		$endif

		// But also track the runtime longopts details. This means removing INCREMENTAL and CALLBACK from the equation,
		//   since they're not runtime argtype values according to getopts.
		OptionArgType $has_arg_runtime = $has_arg;
		$switch $has_arg:
		$case INCREMENTAL: $has_arg_runtime = NO_ARGUMENT;
		$case CALLBACK: $has_arg_runtime = REQUIRED_ARGUMENT;
		$endswitch

		// Update 'longname' to remove possible suffix.
		$longname = ($defined($longname[^1]) &&& @in($longname[^1], '?', '+')) ??? $longname[..^2] : $longname;

		longopts[$idx] = { $longname, $has_arg_runtime, null, (int)($shortname.len > 0 ??? $shortname[0] : $dyn_shortname++) };

		// Track the arg type in CT variables.
		$ct_argstype[$idx] = $has_arg;
		$ct_longnames[$idx] = $longname;
		$ct_shortnames[$idx] = $shortname.len > 0 ??? $shortname[0] : $dyn_shortname - 1;

		// Quickly check for duplicate short/long option names.
		$for var $a = 0; $a < $idx; ++$a :
			$assert !$ct_longnames[$a].len ||| $ct_longnames[$a] != $longname : "Duplicate long option name '" +++ $ct_longnames[$a] +++ "' is not allowed.";
			$assert $ct_shortnames[$a] != $ct_shortnames[$idx] : "Duplicate short option character '" +++ $ct_shortnames[$a] +++ "' is not allowed.";
		$endfor
	}
	$endfor

	// Reset any previous options parsing that might have been done.
	opt::@reset();

	// This macro wraps a `getopt_long` call.
	int longopt_index;
	int optval;
	while (-1 != (optval = opt::get_long(#args, $dyn_opt_str, longopts[..], &longopt_index)))
	{
		if CT_SWITCH: (true)   // cheesy CT workaround for lack of dynamic CT cases in $switch
		{
			if ('?' == optval) return HELP_REQUESTED?;
			if (':' == optval) return ILLEGAL_OPTION?;

			$for var $argidx = 0, var $idx = 0; $argidx < $vacount; ++$idx, $argidx += 3 :
			{
				var $shortname = $ct_shortnames[$idx];
				var $longname = $ct_longnames[$idx];
				var assignee = $vaarg[$argidx + 2];

				if ((int)($shortname) == optval)
				{
					// An option handler should never be considered valid if the longopt_index exceeds the size of the longopts slice.
					if (longopt_index >= longopts.len) return INVALID_LONGOPT?;

					// Now set the option handler's behavior based on the type of argument (if any) that's expected.
					$switch $ct_argstype[$idx] :
					$case OptionArgType.NO_ARGUMENT: *assignee = true;
					$case OptionArgType.INCREMENTAL: *assignee += 1;

					$case OptionArgType.CALLBACK:
						if (null == opt::arg.ptr || !opt::arg.len) return MISSING_ARGUMENT?;   // callbacks MUST have an argument to pass
						$assert $defined(OptionCallback z = assignee)
							: "Callback argument types must provide a function reference of type OptionCallback. Got '" +++ $typeof(assignee).nameof +++ "'.";
						assignee(opt::arg)!;   // invoke the callback method.

					$default:
						if (null == opt::arg.ptr || !opt::arg.len)
						{
							if ($ct_argstype[$idx] == OPTIONAL_ARGUMENT) break CT_SWITCH;   // optional arg? continue checking options
							return MISSING_ARGUMENT?;   // required arg? throw
						}

						$assert $kindof(assignee) == POINTER &&& $defined($typeof(assignee).inner)
							: "The assignee must be a pointer type and must have an '.inner' property";

						// Set the passed pointer's value.
						String arg = opt::arg;
						var $ArgType = $typeof(assignee);
						var $SingleDerefArgType = $ArgType.inner;
						var $DerefArgType = $ArgType.inner;   // keep digging until the type is no longer a pointer kind
						$for ; $DerefArgType.kindof == TypeKind.POINTER; $DerefArgType = $DerefArgType.inner: $endfor

						$switch $typeof(assignee).inner.kindof:
						$case ARRAY:
							$assert $defined($typeof((*assignee)[0])) : "The ARRAY kindof arg must be indexable";

							$ArgType = $typeof(assignee);
							$SingleDerefArgType = $typeof((*assignee)[0]);
							$DerefArgType = $SingleDerefArgType;   // keep digging until the type is no longer a pointer kind
							$for ; $DerefArgType.kindof == TypeKind.POINTER; $DerefArgType = $DerefArgType.inner: $endfor

							ushort current_index = array_storage_indexes[(char)$shortname]++;
							if (current_index >= (*assignee).len) return OUT_OF_BOUNDS?;;

							(*assignee)[current_index] = ($DerefArgType)@derive_arg_value(
								arg, $DerefArgType.typeid, $DerefArgType.typeid, $ArgType.typeid);

						$case ENUM:
							int ordinal;
							if (catch @try(ordinal, arg.to_integer(int)))
							{
								$DerefArgType enum_val;
								if (catch @try(enum_val, enum_by_name($DerefArgType, arg)))
								{
									io::eprintf("Exception caught while converting argument to enum type %s.", $DerefArgType.nameof);
									abort("Unable to convert argument to the enum type.");
								}
								*assignee = enum_val;
							}
							else
							{
								*assignee = $DerefArgType.from_ordinal(ordinal);
							}

						$default:   // in the default case, we let the language allow/disallow the assignment
							*assignee = ($SingleDerefArgType)@derive_arg_value(
								arg, $SingleDerefArgType.typeid, $DerefArgType.typeid, $ArgType.typeid);
						$endswitch
					$endswitch

					break CT_SWITCH;
				}
			}
			$endfor

			// Default to not knowing the option that was presented.
			return ILLEGAL_OPTION?;
		}
	}

	// Return current option index.
	return ind;
}


macro @derive_arg_value(String arg, $SingleDerefArgType, $DerefArgType, $ArgType) @local
{
	$switch ($SingleDerefArgType) :
	$case int128.typeid :
	$case long.typeid :
	$case int.typeid :
	$case short.typeid :
	$case ichar.typeid :
	$case uint128.typeid :
	$case ulong.typeid :
	$case uint.typeid :
	$case ushort.typeid :
		$DerefArgType? retval = arg.to_integer($DerefArgType);
		if (catch oops = retval)
		{
			io::eprintf("Exception caught while parsing arg '%s' as NUMERIC type '%s': %s", arg, $DerefArgType.nameof, oops);

			abort("Invalid option argument format for integer type '" +++ $SingleDerefArgType.nameof +++ "'.");
		}
		return retval;

	$case char.typeid :
		if (ascii::@is_digit(arg[0]))
		{
			$DerefArgType? retval = arg.to_integer($DerefArgType);
			if (catch oops = retval)
			{
				io::eprintf("Exception caught while parsing arg '%s' as CHAR type '%s': %s", arg, $DerefArgType.nameof, oops);

				abort("Invalid option argument format for char type '" +++ $SingleDerefArgType.nameof +++ "'.");
			}
			return retval;
		}
		else
		{
			if (arg.len != 1) abort("Alphabetic 'char' arguments must be only a single character.");

			return arg[0];
		}

	$case float.typeid : return arg.to_float()!!;
	$case double.typeid : return arg.to_double()!!;

	$case String.typeid :
	$case ZString.typeid :
	$case (char*).typeid :
	$case (char[*]*).typeid :
	$case char[*].typeid :
		return ($SingleDerefArgType)arg;

	$case WString.typeid :
		WString? retval = arg.to_wstring();
		if (catch oops = retval)
		{
				io::eprintf("Exception caught while converting argument to WString: %s", oops);

				abort("Unable to convert argument to a wide string.");
		}
		return retval;

	$default:
		$error "Type '" +++ $ArgType.nameof +++ "' could not be derived from a String argument.";
	$endswitch
}
