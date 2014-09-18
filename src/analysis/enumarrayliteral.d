//          Copyright Brian Schott (Hackerpilot) 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module analysis.enumarrayliteral;

import std.d.ast;
import std.d.lexer;
import analysis.base;

void doNothing(string, size_t, size_t, string, bool) {}

class EnumArrayLiteralCheck : BaseAnalyzer
{
	alias visit = BaseAnalyzer.visit;

	this(string fileName)
	{
		super(fileName);
	}

	bool looking = false;

	mixin visitTemplate!ClassDeclaration;
	mixin visitTemplate!InterfaceDeclaration;
	mixin visitTemplate!UnionDeclaration;
	mixin visitTemplate!StructDeclaration;

	override void visit(const Declaration dec)
	{
		if (inAggregate) foreach (attr; dec.attributes)
		{
			if (attr.storageClass !is null &&
				attr.storageClass.token == tok!"enum")
			{
				looking = true;
			}
		}
		dec.accept(this);
		looking = false;
	}

	override void visit(const AutoDeclaration autoDec)
	{
		if (looking)
		{
			foreach (i, initializer; autoDec.initializers)
			{
				if (initializer is null) continue;
				if (initializer.nonVoidInitializer is null) continue;
				if (initializer.nonVoidInitializer.assignExpression is null) continue;
				line = autoDec.identifiers[i].line;
				column = autoDec.identifiers[i].column;
				text = autoDec.identifiers[i].text;
//				visit(initializer.nonVoidInitializer.assignExpression);
			}
		}
		autoDec.accept(this);
	}

	override void visit(const ArrayLiteral arrayLiteral)
	{
		if (!looking)
			return;
		addErrorMessage(line, column, "dscanner.performance.enum_array_literal",
			"This enum may lead to unnecessary allocation at run-time."
			~ " Use 'static immutable " ~ text ~ " = [ ...' instead.");
	}

	override void visit(const AssocArrayLiteral assocArrayLiteral)
	{
		if (!looking)
			return;
		addErrorMessage(line, column, "dscanner.performance.enum_array_literal",
			"This enum may lead to unnecessary allocation at run-time."
			~ " Use 'static immutable " ~ text ~ " = [ ...' instead.");
	}

private:

	string text;
	size_t line;
	size_t column;
}

