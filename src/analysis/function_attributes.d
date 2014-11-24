//          Copyright Brian Schott (Hackerpilot) 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module analysis.function_attributes;

import std.d.ast;
import std.d.lexer;
import analysis.base;

import std.stdio;

/**
 * Prefer
 * ---
 * int getStuff() const {}
 * ---
 * to
 * ---
 * const int getStuff() {}
 * ---
 */
class FunctionAttributeCheck : BaseAnalyzer
{
	alias visit = BaseAnalyzer.visit;

	this(string fileName)
	{
		super(fileName);
	}

	override void visit(const InterfaceDeclaration dec)
	{
		inInterface++;
		dec.accept(this);
		inInterface--;
	}

	override void visit(const Declaration dec)
	{
		if (dec.functionDeclaration is null)
			goto end;
		if (dec.attributes.length == 0)
			goto end;
		foreach (attr; dec.attributes)
		{
			if (attr.storageClass is null)
				continue;
			if (attr.storageClass.token == tok!"abstract" && inInterface > 0)
			{
				addErrorMessage(dec.functionDeclaration.name.line,
					dec.functionDeclaration.name.column, KEY,
					"'abstract' attribute on interface function has"
						~ " no effect.");
				continue;
			}
			if (attr.storageClass.token == tok!"const"
				|| attr.storageClass.token == tok!"inout"
				|| attr.storageClass.token == tok!"immutable")
			{
				import std.string : format;
				immutable string attrString = str(attr.storageClass.token.type);
				addErrorMessage(dec.functionDeclaration.name.line,
					dec.functionDeclaration.name.column, KEY,
					format("'%s' is not an attribute of the return type."
					~ " Place it after the parameter list to clarify.", attrString));
			}
		}
	end:
		dec.accept(this);
	}

	int inInterface;

	private enum KEY = "dscanner.confusing.function_attributes";
}
