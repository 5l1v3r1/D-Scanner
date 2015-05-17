//          Copyright Brian Schott (Hackerpilot) 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module analysis.redundant_parens;

import std.d.ast;
import std.d.lexer;
import analysis.base;

class RedundantParenCheck : BaseAnalyzer
{
	alias visit = BaseAnalyzer.visit;

	this(string fileName)
	{
		super(fileName);
	}

	override void visit(const IfStatement statement)
	{
		import std.stdio : stderr;

		stderr.writeln(__PRETTY_FUNCTION__);
		UnaryExpression unary;
		if (statement.expression is null || statement.expression.items.length != 1)
			goto end;
		unary = cast(UnaryExpression) statement.expression.items[0];
		if (unary is null)
			goto end;
		visit(unary.primaryExpression);
	end:
		statement.accept(this);
	}

	override void visit(const PrimaryExpression primaryExpression)
	{
		if (primaryExpression is null)
			goto end;
		if (primaryExpression.expression is null)
			goto end;
		addErrorMessage(primaryExpression.expression.line,
			primaryExpression.expression.column, KEY, "Redundant parenthesis");
	end:
		primaryExpression.accept(this);
	}

private:
	enum KEY = "dscanner.suspicious.redundant_parens";
}
