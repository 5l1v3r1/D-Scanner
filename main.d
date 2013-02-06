//          Copyright Brian Schott (Sir Alaran) 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module main;


import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.getopt;
import std.parallelism;
import std.path;
import std.regex;
import std.stdio;
import std.range;
import std.d.lexer;

import highlighter;

pure nothrow bool isLineOfCode(TokenType t)
{
	switch(t)
	{
	case TokenType.semicolon:
	case TokenType.while_:
	case TokenType.if_:
	case TokenType.for_:
	case TokenType.foreach_:
	case TokenType.foreach_reverse_:
	case TokenType.case_:
		return true;
	default:
		return false;
	}
}

/**
 * Loads any import directories specified in /etc/dmd.conf.
 * Bugs: Only works on Linux
 * Returns: the paths specified as -I options in /etc/dmd.conf
 */
string[] loadDefaultImports()
{
version(linux)
{
	string path = "/etc/dmd.conf";
	if (!exists(path))
		return [];
	string[] rVal;
	auto file = File(path, "r");
	foreach(char[] line; file.byLine())
	{
		if (!line.startsWith("DFLAGS"))
			continue;
		while ((line = line.find("-I")).length > 0)
		{
			auto end = std.string.indexOf(line, " ");
			auto importDir = line[2 .. end].idup;
			rVal ~= importDir;
			line = line[end .. $];
		}
	}
	return rVal;
}
else
{
	return [];
}
}


string[] loadConfig()
{
	string path = expandTilde("~" ~ dirSeparator ~ ".dscanner");
	string[] dirs;
	if (exists(path))
	{
		auto f = File(path, "r");
		scope(exit) f.close();

		auto trimRegex = ctRegex!(`\s*$`);
		foreach(string line; lines(f))
		{
			dirs ~= replace(line, trimRegex, "");
		}
	}
	foreach(string importDir; loadDefaultImports()) {
		dirs ~= importDir;
	}
	return dirs;
}

int main(string[] args)
{
	string[] importDirs;
	bool sloc;
	/+bool dotComplete;+/
	/+bool json;+/
	/+bool parenComplete;+/
	bool highlight;
	bool ctags;
	bool recursiveCtags;
	bool format;
	bool help;
	bool tokenCount;
    bool frequencyCount;

	try
	{
		getopt(args, "I", &importDirs,/+ "dotComplete", &dotComplete,+/ "sloc", &sloc,
			/+"json", &json,+/ /+"parenComplete", &parenComplete,+/ "highlight", &highlight,
			"ctags", &ctags, "recursive|r|R", &recursiveCtags, "help|h", &help,
			"tokenCount", &tokenCount, "frequencyCount", &frequencyCount);
	}
	catch (Exception e)
	{
		stderr.writeln(e.msg);
	}

	if (help || (!sloc && /+!dotComplete &&+/ /+!json &&+/ /+!parenComplete &&+/ !highlight
		&& !ctags && !format && !tokenCount && !frequencyCount))
	{
		printHelp();
		return 0;
	}

	importDirs ~= loadConfig();

	if (tokenCount)
	{
		import core.memory;
		/+if (args.length == 1)
		{
			writeln((cast (ubyte[]) stdin.byLine(KeepTerminator.yes).join()).byToken().walkLength());
		}
		else
		{+/
			LexerConfig config;
            config.tokenStyle = TokenStyle.doNotReplaceSpecial;
			foreach (arg; args[1..$])
			{
				config.fileName = arg;
				uint count;
                auto f = File(arg);
                ubyte[] buffer = uninitializedArray!(ubyte[])(f.size);
				foreach(t; byToken(f.rawRead(buffer), config))
				{
					++count;
				}
				writefln("%s: %d", arg, count);
			}
		/+}+/
	}
    /+else if (frequencyCount)
    {
        uint[TokenType] frequency;
        foreach (t; byToken(cast(ubyte[]) File(args[1]).byLine(KeepTerminator.yes).join()))
        {
            frequency[t.type]++;
        }
        foreach (k, v; frequency)
        {
            writeln(v, ":", cast(TokenType) k);
        }
    }+/

	/+if (sloc)
	{
		if (args.length == 1)
		{
			writeln(stdin.byLine(KeepTerminator.yes).join().byToken().count!(a => isLineOfCode(a.type))());
		}
		else
		{
			writeln(args[1..$].map!(a => File(a).byLine(KeepTerminator.yes).join().byToken(a))()
                .joiner().count!(a => isLineOfCode(a.type))());
		}
		return 0;
	}+/

	if (highlight)
	{
		LexerConfig config;
		config.iterStyle = IterationStyle.everything;
		config.tokenStyle = TokenStyle.source;
        File f = args.length == 1 ? stdin : File(args[1]);
        highlighter.highlight((cast(ubyte[]) f.byLine(KeepTerminator.yes).join()).byToken(config),
			args.length == 1 ? "stdin" : args[1]);
		return 0;
	}

	/+if (dotComplete || parenComplete)
	{
		if (isAbsolute(args[1]))
			importDirs ~= dirName(args[1]);
		else
			importDirs ~= getcwd();
		Token[] tokens;
		try
		{
			to!size_t(args[1]);
			auto f = appender!string();
			char[] buf;
			while (stdin.readln(buf))
				f.put(buf);
			tokens = f.data.byToken().array();
		}
		catch(ConvException e)
		{
			tokens = args[1].readText().byToken().array();
			args.popFront();
		}
		auto mod = parseModule(tokens);
		CompletionContext context = new CompletionContext(mod);
		context.importDirectories = importDirs;
		foreach (im; parallel(mod.imports))
		{
			auto p = findAbsPath(importDirs, im);
			if (p is null || !p.exists())
				continue;
			context.addModule(p.readText().byToken().array().parseModule());
		}
		auto complete = AutoComplete(tokens, context);
		if (parenComplete)
			writeln(complete.parenComplete(to!size_t(args[1])));
		else if (dotComplete)
			writeln(complete.dotComplete(to!size_t(args[1])));
		return 0;
	}+/

	/+if (json)
	{
		CircularBuffer!(Token) tokens;
        File f = args.length == 1 ? stdin : File(args[1]);
        tokens = new CircularBuffer!(Token)(CIRC_BUFF_SIZE,
            f.byLine(KeepTerminator.yes).join().byToken!(char[])());
		auto mod = parseModule(tokens);
		mod.writeJSONTo(stdout);
		return 0;
	}+/

//	if (ctags)
//	{
//		if (!recursiveCtags)
//		{
//			auto tokens = byToken(readText(args[1]));
//			auto mod = parseModule(tokens.array());
//			mod.writeCtagsTo(stdout, args[1]);
//		}
//		else
//		{
//			Module m;
//			foreach (dirEntry; dirEntries(args[1], SpanMode.breadth))
//			{
//				if (!dirEntry.name.endsWith(".d", ".di"))
//					continue;
//				stderr.writeln("Generating tags for ", dirEntry.name);
//				auto tokens = byToken(readText(dirEntry.name));
//				if (m is null)
//					m = parseModule(tokens.array());
//				else
//				{
//					auto mod = parseModule(tokens.array());
//					m.merge(mod);
//				}
//			}
//			m.writeCtagsTo(stdout, "");
//		}
//	}
	return 0;
}

void printHelp()
{
	writeln(
q{
    Usage: dscanner options

options:
    --help | -h
        Prints this help message

    --sloc [sourceFiles]
        count the number of logical lines of code in the given
        source files. If no files are specified, a file is read from stdin.

    --json [sourceFile]
        Generate a JSON summary of the given source file. If no file is
        specifed, the file is read from stdin.

    --dotComplete [sourceFile] cursorPosition
        Provide autocompletion for the insertion of the dot operator. The cursor
        position is the character position in the *file*, not the position in
        the line. If no file is specified, the file is read from stdin.

    --parenComplete [sourceFile] cursorPosition
        Provides a listing of function parameters or pre-defined version
        identifiers at the cursor position. The cursor position is the character
        position in the *file*, not the line. If no file is specified, the
        contents are read from stdin.

    --highlight [sourceFile] - Syntax-highlight the given source file. The
        resulting HTML will be written to standard output.

    -I includePath
        Include _includePath_ in the list of paths used to search for imports.
        By default dscanner will search in the current working directory as
        well as any paths specified in /etc/dmd.conf. This is only used for the
        --parenComplete and --dotComplete options.

    --ctags sourceFile
        Generates ctags information from the given source code file. Note that
        ctags information requires a filename, so stdin cannot be used in place
        of a filename.

    --recursive | -R | -r directory
        When used with --ctags, dscanner will produce ctags output for all .d
        and .di files contained within directory and its sub-directories.});
}
