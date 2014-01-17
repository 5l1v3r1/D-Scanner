// Written in the D programming language

/**
 * This module contains a range-based _lexer generator.
 *
 * Copyright: Brian Schott 2013
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt Boost, License 1.0)
 * Authors: Brian Schott, with ideas shamelessly stolen from Andrei Alexandrescu
 * Source: $(PHOBOSSRC std/_lexer.d)
 */

module stdx.lexer;

import std.typecons;
import std.algorithm;
import std.range;
import std.traits;
import std.conv;
import std.math;
import dpick.buffer.buffer;
import dpick.buffer.traits;

/**
 * Template for determining the type used for a token type. Selects the smallest
 * unsigned integral type that is able to hold the value
 * staticTokens.length + dynamicTokens.length. For example if there are 20
 * static tokens, 30 dynamic tokens, and 10 possible default tokens, this
 * template will alias itself to ubyte, as 20 + 30 + 10 < ubyte.max.
 */
template TokenIdType(alias staticTokens, alias dynamicTokens,
	alias possibleDefaultTokens)
{
  static if ((staticTokens.length + dynamicTokens.length + possibleDefaultTokens.length) <= ubyte.max)
		alias TokenIdType = ubyte;
	else static if ((staticTokens.length + dynamicTokens.length + possibleDefaultTokens.length) <= ushort.max)
		alias TokenIdType = ushort;
	else static if ((staticTokens.length + dynamicTokens.length + possibleDefaultTokens.length) <= uint.max)
		alias TokenIdType = uint;
	else
		static assert (false);
}

/**
 * Looks up the string representation of the given token type.
 */
string tokenStringRepresentation(IdType, alias staticTokens, alias dynamicTokens, alias possibleDefaultTokens)(IdType type) @property
{
	if (type == 0)
		return "!ERROR!";
	else if (type < staticTokens.length + 1)
		return staticTokens[type - 1];
	else if (type < staticTokens.length + possibleDefaultTokens.length + 1)
		return possibleDefaultTokens[type - staticTokens.length - 1];
	else if (type < staticTokens.length + possibleDefaultTokens.length + dynamicTokens.length + 1)
		return dynamicTokens[type - staticTokens.length - possibleDefaultTokens.length - 1];
	else
		return null;
}

/**
 * Generates the token type identifier for the given symbol. There are two
 * special cases:
 * $(UL
 *     $(LI If symbol is "", then the token identifier will be 0)
 *     $(LI If symbol is "\0", then the token identifier will be the maximum
 *         valid token type identifier)
 * )
 * In all cases this template will alias itself to a constant of type IdType.
 * Examples:
 * ---
 * enum string[] staticTokens = ["+", "-", "*", "/"];
 * enum string[] dynamicTokens = ["number"];
 * enum string[] possibleDefaultTokens = [];
 * alias IdType = TokenIdType!(staticTokens, dynamicTokens, possibleDefaultTokens);
 * template tok(string symbol)
 * {
 *     alias tok = TokenId!(IdType, staticTokens, dynamicTokens,
 *         possibleDefaultTokens, symbol);
 * }
 * IdType plus = tok!"+";
 * ---
 */
template TokenId(IdType, alias staticTokens, alias dynamicTokens,
	alias possibleDefaultTokens, string symbol)
{
	static if (symbol == "")
	{
		enum id = 0;
		alias TokenId = id;
	}
	else static if (symbol == "\0")
	{
		enum id = 1 + staticTokens.length + dynamicTokens.length + possibleDefaultTokens.length;
		alias TokenId = id;
	}
	else
	{
		enum i = staticTokens.countUntil(symbol);
		static if (i >= 0)
		{
			enum id = i + 1;
			alias TokenId = id;
		}
		else
		{
			enum ii = possibleDefaultTokens.countUntil(symbol);
			static if (ii >= 0)
			{
				enum id = ii + staticTokens.length + 1;
				static assert (id >= 0 && id < IdType.max, "Invalid token: " ~ symbol);
				alias TokenId = id;
			}
			else
			{
				enum dynamicId = dynamicTokens.countUntil(symbol);
				enum id = dynamicId >= 0
					? i + staticTokens.length + possibleDefaultTokens.length + dynamicId + 1
					: -1;
				static assert (id >= 0 && id < IdType.max, "Invalid token: " ~ symbol);
				alias TokenId = id;
			}
		}
	}
}

/**
 * The token that is returned by the lexer.
 * Params:
 *     IDType = The D type of the "type" token type field.
 *     extraFields = A string containing D code for any extra fields that should
 *         be included in the token structure body. This string is passed
 *         directly to a mixin statement.
 */
struct TokenStructure(IDType, string extraFields = "")
{
public:

	/**
	 * == overload for the the token type.
	 */
	bool opEquals(IDType type) const pure nothrow @safe
	{
		return this.type == type;
	}

	/**
	 *
	 */
	this(IDType type)
	{
		this.type = type;
	}

	/**
	 *
	 */
	this(IDType type, string text, size_t line, size_t column, size_t index)
	{
		this.text = text;
		this.line = line;
		this.column = column;
		this.type = type;
		this.index = index;
	}

	/**
	 *
	 */
	string text;

	/**
	 *
	 */
	size_t line;

	/**
	 *
	 */
	size_t column;

	/**
	 *
	 */
	size_t index;

	/**
	 *
	 */
	IDType type;

	mixin (extraFields);
}

mixin template Lexer(R, IDType, Token, alias defaultTokenFunction,
	alias staticTokens, alias dynamicTokens, alias pseudoTokens,
	alias pseudoTokenHandlers, alias possibleDefaultTokens)
{
	static string generateCaseStatements(string[] tokens, size_t offset = 0)
	{
		string code;
		for (size_t i = 0; i < tokens.length; i++)
		{
			auto indent = "";
			foreach (k; 0 .. offset)
				indent ~= "    ";
			size_t j = i + 1;

			if (offset < tokens[i].length)
			{
				while (j < tokens.length && offset < tokens[j].length
					&& tokens[i][offset] == tokens[j][offset]) j++;
				code ~= indent ~ "case " ~ text(cast(ubyte) tokens[i][offset]) ~ ":\n";
				if (i + 1 >= j)
				{
					if (offset + 1 == tokens[i].length)
						code ~= generateLeaf(tokens[i], indent ~ "    ");
					else
					{
						code ~= indent ~ "    if (range.lookahead(" ~ text(tokens[i].length) ~ ").length == 0)\n";
						code ~= indent ~ "        goto outer_default;\n";
						code ~= indent ~ "    if (range.lookahead(" ~ text(tokens[i].length) ~ ") == \"" ~ escape(tokens[i]) ~ "\")\n";
						code ~= indent ~ "    {\n";
						code ~= generateLeaf(tokens[i], indent ~ "        ");
						code ~= indent ~ "    }\n";
						code ~= indent ~ "    else\n";
						code ~= indent ~ "        goto outer_default;\n";
					}
				}
				else
				{
					code ~= indent ~ "    if (range.lookahead(" ~ text(offset + 2) ~ ").length == 0)\n";
					code ~= indent ~ "    {\n";
					code ~= generateLeaf(tokens[i][0 .. offset + 1], indent ~ "        ");
					code ~= indent ~ "    }\n";
					code ~= indent ~ "    switch (range.lookahead(" ~ text(offset + 2) ~ ")[" ~ text(offset + 1) ~ "])\n";
					code ~= indent ~ "    {\n";
					code ~= generateCaseStatements(tokens[i .. j], offset + 1);
					code ~= indent ~ "    default:\n";
					code ~= generateLeaf(tokens[i][0 .. offset + 1], indent ~ "        ");
					code ~= indent ~ "    }\n";
				}
			}
			i = j - 1;
		}
		return code;
	}

	static string generateLeaf(string token, string indent)
	{
		static assert (pseudoTokenHandlers.length % 2 == 0,
			"Each pseudo-token must have a matching function name.");
		string code;
		if (staticTokens.countUntil(token) >= 0)
		{
			if (token.length == 1)
				code ~= indent ~ "range.popFront();\n";
			else
				code ~= indent ~ "range.popFrontN(" ~ text(token.length) ~ ");\n";
			code ~= indent ~ "return Token(tok!\"" ~ escape(token) ~ "\", null, line, column, index);\n";
		}
		else if (pseudoTokens.countUntil(token) >= 0)
			code ~= indent ~ "return " ~ pseudoTokenHandlers[pseudoTokenHandlers.countUntil(token) + 1] ~ "();\n";
		else if (possibleDefaultTokens.countUntil(token) >= 0)
		{
			code ~= indent ~ "if (range.lookahead(" ~ text(token.length + 1) ~ ").length == 0 || isSeparating(range.lookahead(" ~ text(token.length + 1) ~ ")[" ~ text(token.length) ~ "]))\n";
			code ~= indent ~ "{\n";
			if (token.length == 1)
				code ~= indent ~ "    range.popFront();\n";
			else
				code ~= indent ~ "    range.popFrontN(" ~ text(token.length) ~ ");\n";
			code ~= indent ~ "    return Token(tok!\"" ~ escape(token) ~"\", null, line, column, index);\n";
			code ~= indent ~ "}\n";
			code ~= indent ~ "else\n";
			code ~= indent ~ "    goto outer_default;\n";
		}
		else
			code ~= indent ~ "goto outer_default;\n";
		return code;
	}

	const(Token) front() pure nothrow const @property
	{
		return _front;
	}

	void _popFront() pure
	{
		_front = advance();
	}

	bool empty() pure const nothrow @property
	{
		return _front.type == tok!"\0";
	}

	static string escape(string input)
	{
		string retVal;
		foreach (ubyte c; cast(ubyte[]) input)
		{
			switch (c)
			{
			case '\\': retVal ~= `\\`; break;
			case '"': retVal ~= `\"`; break;
			case '\'': retVal ~= `\'`; break;
			case '\t': retVal ~= `\t`; break;
			case '\n': retVal ~= `\n`; break;
			case '\r': retVal ~= `\r`; break;
			default: retVal ~= c; break;
			}
		}
		return retVal;
	}

	Token advance() pure
	{
		if (range.empty)
			return Token(tok!"\0");
		immutable size_t index = range.index;
		immutable size_t column = range.column;
		immutable size_t line = range.line;
		lexerLoop: switch (range.front)
		{
		mixin(generateCaseStatements(stupidToArray(sort(staticTokens ~ pseudoTokens ~ possibleDefaultTokens))));
//		pragma(msg, generateCaseStatements(stupidToArray(sort(staticTokens ~ pseudoTokens ~ possibleDefaultTokens))));
		outer_default:
		default:
			return defaultTokenFunction();
		}
	}

	/**
	 * This only exists because the real array() can't be called at compile-time
	 */
	static T[] stupidToArray(R, T = ElementType!R)(R range)
	{
		T[] retVal;
		foreach (v; range)
			retVal ~= v;
		return retVal;
	}

	LexerRange!(typeof(buffer(R.init))) range;
	Token _front;
}

struct LexerRange(BufferType) if (isBuffer!BufferType)
{
	this(BufferType r)
	{
		this.range = r;
		index = 0;
		column = 1;
		line = 1;
	}

	void popFront() pure
	{
		index++;
		column++;
		range.popFront();
	}

	void incrementLine() pure nothrow
	{
		column = 1;
		line++;
	}

	BufferType range;
	alias range this;
	size_t index;
	size_t column;
	size_t line;
}

/**
 * The string cache should be used within lexer implementations for several
 * reasons:
 * $(UL
 *     $(LI Reducing memory consumption.)
 *     $(LI Increasing performance in token comparisons)
 *     $(LI Correctly creating immutable token text if the lexing source is not
 *     immutable)
 * )
 */
struct StringCache
{
public:

	/**
	 * Equivalent to calling cache() and get().
	 * ---
	 * StringCache cache;
	 * ubyte[] str = ['a', 'b', 'c'];
	 * string s = cache.get(cache.cache(str));
	 * assert(s == "abc");
	 * ---
	 */
	string cacheGet(const(ubyte[]) bytes) pure nothrow @safe
	{
		return get(cache(bytes));
	}

	/**
	 * Caches a string.
	 * Params: bytes = the string to cache
	 * Returns: A key that can be used to retrieve the cached string
	 * Examples:
	 * ---
	 * StringCache cache;
	 * ubyte[] bytes = ['a', 'b', 'c'];
	 * size_t first = cache.cache(bytes);
	 * size_t second = cache.cache(bytes);
	 * assert (first == second);
	 * ---
	 */
	size_t cache(const(ubyte)[] bytes) pure nothrow @safe
	in
	{
		assert (bytes.length > 0);
	}
	out (retVal)
	{
		assert (retVal < items.length);
	}
	body
	{
		immutable uint hash = hashBytes(bytes);
		const(Item)* found = find(bytes, hash);
		if (found is null)
			return intern(bytes, hash);
		return found.index;
	}

	/**
	 * Gets a cached string based on its key.
	 * Params: index = the key
	 * Returns: the cached string
	 */
	string get(size_t index) const pure nothrow @safe
	in
	{
		assert (items.length > index);
		assert (items[index] !is null);
	}
	out (retVal)
	{
		assert (retVal !is null);
	}
	body
	{
		return items[index].str;
	}

private:

	size_t intern(const(ubyte)[] bytes, uint hash) pure nothrow @safe
	{
		Item* item = new Item;
		item.hash = hash;
		item.str = allocate(bytes);
		item.index = items.length;
		items ~= item;
		buckets[hash % buckets.length] ~= item;
		return item.index;
	}

	const(Item)* find(const(ubyte)[] bytes, uint hash) pure nothrow const @safe
	{
		immutable size_t index = hash % buckets.length;
		foreach (item; buckets[index])
		{
			if (item.hash == hash && bytes.equal(item.str))
				return item;
		}
		return null;
	}

	string allocate(const(ubyte)[] bytes) pure nothrow @trusted
	out (retVal)
	{
		assert (retVal == bytes);
	}
	body
	{
		import core.memory;
		if (bytes.length > (pageSize / 4))
		{
			ubyte* memory = cast(ubyte*) GC.malloc(bytes.length, GC.BlkAttr.NO_SCAN);
			memory[0 .. bytes.length] = bytes[];
			return cast(string) memory[0..bytes.length];
		}
		foreach (ref block; blocks)
		{
			immutable size_t endIndex = block.used + bytes.length;
			if (endIndex > block.bytes.length)
				continue;
			block.bytes[block.used .. endIndex] = bytes[];
			string slice = cast(string) block.bytes[block.used .. endIndex];
			block.used = endIndex;
			return slice;
		}
		blocks.length = blocks.length + 1;
		blocks[$ - 1].bytes = (cast(ubyte*) GC.malloc(pageSize, GC.BlkAttr.NO_SCAN))[0 .. pageSize];
		blocks[$ - 1].bytes[0 .. bytes.length] = bytes[];
		blocks[$ - 1].used = bytes.length;
		return cast(string) blocks[$ - 1].bytes[0 .. bytes.length];
	}

	static uint hashBytes(const(ubyte)[] data) pure nothrow @safe
    {
        uint hash = 0;
        foreach (b; data)
        {
            hash ^= sbox[b];
            hash *= 3;
        }
        return hash;
    }

	static struct Item
	{
		size_t index;
		string str;
		uint hash;
	}

	static struct Block
	{
		ubyte[] bytes;
		size_t used;
	}

	static enum pageSize = 4096 * 1024;
	static enum bucketCount = 2048;

	static enum uint[] sbox = [
		0xF53E1837, 0x5F14C86B, 0x9EE3964C, 0xFA796D53,
		0x32223FC3, 0x4D82BC98, 0xA0C7FA62, 0x63E2C982,
		0x24994A5B, 0x1ECE7BEE, 0x292B38EF, 0xD5CD4E56,
		0x514F4303, 0x7BE12B83, 0x7192F195, 0x82DC7300,
		0x084380B4, 0x480B55D3, 0x5F430471, 0x13F75991,
		0x3F9CF22C, 0x2FE0907A, 0xFD8E1E69, 0x7B1D5DE8,
		0xD575A85C, 0xAD01C50A, 0x7EE00737, 0x3CE981E8,
		0x0E447EFA, 0x23089DD6, 0xB59F149F, 0x13600EC7,
		0xE802C8E6, 0x670921E4, 0x7207EFF0, 0xE74761B0,
		0x69035234, 0xBFA40F19, 0xF63651A0, 0x29E64C26,
		0x1F98CCA7, 0xD957007E, 0xE71DDC75, 0x3E729595,
		0x7580B7CC, 0xD7FAF60B, 0x92484323, 0xA44113EB,
		0xE4CBDE08, 0x346827C9, 0x3CF32AFA, 0x0B29BCF1,
		0x6E29F7DF, 0xB01E71CB, 0x3BFBC0D1, 0x62EDC5B8,
		0xB7DE789A, 0xA4748EC9, 0xE17A4C4F, 0x67E5BD03,
		0xF3B33D1A, 0x97D8D3E9, 0x09121BC0, 0x347B2D2C,
		0x79A1913C, 0x504172DE, 0x7F1F8483, 0x13AC3CF6,
		0x7A2094DB, 0xC778FA12, 0xADF7469F, 0x21786B7B,
		0x71A445D0, 0xA8896C1B, 0x656F62FB, 0x83A059B3,
		0x972DFE6E, 0x4122000C, 0x97D9DA19, 0x17D5947B,
		0xB1AFFD0C, 0x6EF83B97, 0xAF7F780B, 0x4613138A,
		0x7C3E73A6, 0xCF15E03D, 0x41576322, 0x672DF292,
		0xB658588D, 0x33EBEFA9, 0x938CBF06, 0x06B67381,
		0x07F192C6, 0x2BDA5855, 0x348EE0E8, 0x19DBB6E3,
		0x3222184B, 0xB69D5DBA, 0x7E760B88, 0xAF4D8154,
		0x007A51AD, 0x35112500, 0xC9CD2D7D, 0x4F4FB761,
		0x694772E3, 0x694C8351, 0x4A7E3AF5, 0x67D65CE1,
		0x9287DE92, 0x2518DB3C, 0x8CB4EC06, 0xD154D38F,
		0xE19A26BB, 0x295EE439, 0xC50A1104, 0x2153C6A7,
		0x82366656, 0x0713BC2F, 0x6462215A, 0x21D9BFCE,
		0xBA8EACE6, 0xAE2DF4C1, 0x2A8D5E80, 0x3F7E52D1,
		0x29359399, 0xFEA1D19C, 0x18879313, 0x455AFA81,
		0xFADFE838, 0x62609838, 0xD1028839, 0x0736E92F,
		0x3BCA22A3, 0x1485B08A, 0x2DA7900B, 0x852C156D,
		0xE8F24803, 0x00078472, 0x13F0D332, 0x2ACFD0CF,
		0x5F747F5C, 0x87BB1E2F, 0xA7EFCB63, 0x23F432F0,
		0xE6CE7C5C, 0x1F954EF6, 0xB609C91B, 0x3B4571BF,
		0xEED17DC0, 0xE556CDA0, 0xA7846A8D, 0xFF105F94,
		0x52B7CCDE, 0x0E33E801, 0x664455EA, 0xF2C70414,
		0x73E7B486, 0x8F830661, 0x8B59E826, 0xBB8AEDCA,
		0xF3D70AB9, 0xD739F2B9, 0x4A04C34A, 0x88D0F089,
		0xE02191A2, 0xD89D9C78, 0x192C2749, 0xFC43A78F,
		0x0AAC88CB, 0x9438D42D, 0x9E280F7A, 0x36063802,
		0x38E8D018, 0x1C42A9CB, 0x92AAFF6C, 0xA24820C5,
		0x007F077F, 0xCE5BC543, 0x69668D58, 0x10D6FF74,
		0xBE00F621, 0x21300BBE, 0x2E9E8F46, 0x5ACEA629,
		0xFA1F86C7, 0x52F206B8, 0x3EDF1A75, 0x6DA8D843,
		0xCF719928, 0x73E3891F, 0xB4B95DD6, 0xB2A42D27,
		0xEDA20BBF, 0x1A58DBDF, 0xA449AD03, 0x6DDEF22B,
		0x900531E6, 0x3D3BFF35, 0x5B24ABA2, 0x472B3E4C,
		0x387F2D75, 0x4D8DBA36, 0x71CB5641, 0xE3473F3F,
		0xF6CD4B7F, 0xBF7D1428, 0x344B64D0, 0xC5CDFCB6,
		0xFE2E0182, 0x2C37A673, 0xDE4EB7A3, 0x63FDC933,
		0x01DC4063, 0x611F3571, 0xD167BFAF, 0x4496596F,
		0x3DEE0689, 0xD8704910, 0x7052A114, 0x068C9EC5,
		0x75D0E766, 0x4D54CC20, 0xB44ECDE2, 0x4ABC653E,
		0x2C550A21, 0x1A52C0DB, 0xCFED03D0, 0x119BAFE2,
		0x876A6133, 0xBC232088, 0x435BA1B2, 0xAE99BBFA,
		0xBB4F08E4, 0xA62B5F49, 0x1DA4B695, 0x336B84DE,
		0xDC813D31, 0x00C134FB, 0x397A98E6, 0x151F0E64,
		0xD9EB3E69, 0xD3C7DF60, 0xD2F2C336, 0x2DDD067B,
		0xBD122835, 0xB0B3BD3A, 0xB0D54E46, 0x8641F1E4,
		0xA0B38F96, 0x51D39199, 0x37A6AD75, 0xDF84EE41,
		0x3C034CBA, 0xACDA62FC, 0x11923B8B, 0x45EF170A,
	];

	Item*[] items;
	Item*[][bucketCount] buckets;
	Block[] blocks;
}
