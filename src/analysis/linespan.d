//          Copyright Brian Schott (Hackerpilot) 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module analysis.linespan;

/**
 * Used for determining which lines to include as context in the generated HTML
 * report.
 */
struct LineSpans
{
public:
	/**
	 * Returns: true if any of the spans contain the given line number
	 */
	bool containsLine(size_t line) pure const nothrow @safe
	{
		foreach (span; spans)
		{
			if (line >= span.low && line <= span.high)
				return true;
		}
		return false;
	}

	/**
	 * Params: line = the line to add
	 */
	void addLine(size_t line) pure nothrow @safe
	{
		immutable size_t low = line >= context ? line - context : 0;
		immutable size_t high = line + context;
		foreach (ref span; spans)
		{
			if (low <= span.low && high >= span.low && high <= span.high)
			{
				span.low = low;
				return;
			}
			else if (high >= span.high && low <= span.high && low >= span.low)
			{
				span.high = high;
				return;
			}
		}
		spans ~= Span(low, high);
	}

private:

	static struct Span
	{
		size_t low;
		size_t high;
	}

	Span[] spans;

	enum context = 3;
}

unittest
{
	import std.stdio:stderr;

	LineSpans l;
	l.addLine(5);
	foreach (i; 2 .. 9)
		assert (l.containsLine(i));
	assert (!l.containsLine(1));
	assert (!l.containsLine(9));
	l.addLine(5);
	assert (l.containsLine(7));
	l.addLine(40);
	l.addLine(35);
	foreach (i; 33 .. 43)
		assert (l.containsLine(i));
	stderr.writeln("Unittest for LineSpans passed.");
}

