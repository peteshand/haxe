/*
 * Copyright (C)2005-2015 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
package haxe.xml;

using StringTools;

/* poor'man enum : reduce code size + a bit faster since inlined */
extern private class S {
	public static inline var IGNORE_SPACES 	= 0;
	public static inline var BEGIN			= 1;
	public static inline var BEGIN_NODE		= 2;
	public static inline var TAG_NAME		= 3;
	public static inline var BODY			= 4;
	public static inline var ATTRIB_NAME	= 5;
	public static inline var EQUALS			= 6;
	public static inline var ATTVAL_BEGIN	= 7;
	public static inline var ATTRIB_VAL		= 8;
	public static inline var CHILDS			= 9;
	public static inline var CLOSE			= 10;
	public static inline var WAIT_END		= 11;
	public static inline var WAIT_END_RET	= 12;
	public static inline var PCDATA			= 13;
	public static inline var HEADER			= 14;
	public static inline var COMMENT		= 15;
	public static inline var DOCTYPE		= 16;
	public static inline var CDATA			= 17;
	public static inline var ESCAPE			= 18;
}

class Parser
{
	static var escapes = {
		var h = new haxe.ds.StringMap();
		h.set("lt", "<");
		h.set("gt", ">");
		h.set("amp", "&");
		h.set("quot", '"');
		h.set("apos", "'");
		h;
	}

	/**
		Parses the String into an XML Document. Set strict parsing to true in order to enable a strict check of XML attributes and entities.
	**/
	static public function parse(str:String, strict = false)
	{
		var doc = Xml.createDocument();
		doParse(str, strict, 0, doc);
		return doc;
	}

	static function doParse(str:String, strict:Bool, p:Int = 0, ?parent:Xml):Int
	{
		var xml:Xml = null;
		var state = S.BEGIN;
		var next = S.BEGIN;
		var aname = null;
		var start = 0;
		var nsubs = 0;
		var nbrackets = 0;
		var c = str.fastCodeAt(p);
		var buf = new StringBuf();
		// need extra state because next is in use
		var escapeNext = S.BEGIN;
		var attrValQuote = -1;
		inline function addChild(xml:Xml) {
			parent.addChild(xml);
			nsubs++;
		}
		while (!StringTools.isEof(c))
		{
			switch(state)
			{
				case S.IGNORE_SPACES:
					switch(c)
					{
						case
							'\n'.code,
							'\r'.code,
							'\t'.code,
							' '.code:
						default:
							state = next;
							continue;
					}
				case S.BEGIN:
					switch(c)
					{
						case '<'.code:
							state = S.IGNORE_SPACES;
							next = S.BEGIN_NODE;
						default:
							start = p;
							state = S.PCDATA;
							continue;
					}
				case S.PCDATA:
					if (c == '<'.code)
					{
						buf.addSub(str, start, p - start);
						var child = Xml.createPCData(buf.toString());
						buf = new StringBuf();
						addChild(child);
						state = S.IGNORE_SPACES;
						next = S.BEGIN_NODE;
					} else if (c == '&'.code) {
						buf.addSub(str, start, p - start);
						state = S.ESCAPE;
						escapeNext = S.PCDATA;
						start = p + 1;
					}
				case S.CDATA:
					if (c == ']'.code && str.fastCodeAt(p + 1) == ']'.code && str.fastCodeAt(p + 2) == '>'.code)
					{
						var child = Xml.createCData(str.substr(start, p - start));
						addChild(child);
						p += 2;
						state = S.BEGIN;
					}
				case S.BEGIN_NODE:
					switch(c)
					{
						case '!'.code:
							if (str.fastCodeAt(p + 1) == '['.code)
							{
								p += 2;
								if (str.substr(p, 6).toUpperCase() != "CDATA[")
									throw("Expected <![CDATA[");
								p += 5;
								state = S.CDATA;
								start = p + 1;
							}
							else if (str.fastCodeAt(p + 1) == 'D'.code || str.fastCodeAt(p + 1) == 'd'.code)
							{
								if(str.substr(p + 2, 6).toUpperCase() != "OCTYPE")
									throw("Expected <!DOCTYPE");
								p += 8;
								state = S.DOCTYPE;
								start = p + 1;
							}
							else if( str.fastCodeAt(p + 1) != '-'.code || str.fastCodeAt(p + 2) != '-'.code )
								throw("Expected <!--");
							else
							{
								p += 2;
								state = S.COMMENT;
								start = p + 1;
							}
						case '?'.code:
							state = S.HEADER;
							start = p;
						case '/'.code:
							if( parent == null )
								throw("Expected node name");
							start = p + 1;
							state = S.IGNORE_SPACES;
							next = S.CLOSE;
						default:
							state = S.TAG_NAME;
							start = p;
							continue;
					}
				case S.TAG_NAME:
					if (!isValidChar(c))
					{
						if( p == start )
							throw("Expected node name");
						xml = Xml.createElement(str.substr(start, p - start));
						addChild(xml);
						state = S.IGNORE_SPACES;
						next = S.BODY;
						continue;
					}
				case S.BODY:
					switch(c)
					{
						case '/'.code:
							state = S.WAIT_END;
						case '>'.code:
							state = S.CHILDS;
						default:
							state = S.ATTRIB_NAME;
							start = p;
							continue;
					}
				case S.ATTRIB_NAME:
					if (!isValidChar(c))
					{
						var tmp;
						if( start == p )
							throw("Expected attribute name");
						tmp = str.substr(start,p-start);
						aname = tmp;
						if( xml.exists(aname) )
							throw("Duplicate attribute");
						state = S.IGNORE_SPACES;
						next = S.EQUALS;
						continue;
					}
				case S.EQUALS:
					switch(c)
					{
						case '='.code:
							state = S.IGNORE_SPACES;
							next = S.ATTVAL_BEGIN;
						default:
							throw("Expected =");
					}
				case S.ATTVAL_BEGIN:
					switch(c)
					{
						case '"'.code | '\''.code:
							buf = new StringBuf();
							state = S.ATTRIB_VAL;
							start = p + 1;
							attrValQuote = c;
						default:
							throw("Expected \"");
					}
				case S.ATTRIB_VAL:
					switch (c) {
						case '&'.code:
							buf.addSub(str, start, p - start);
							state = S.ESCAPE;
							escapeNext = S.ATTRIB_VAL;
							start = p + 1;
						case '>'.code | '<'.code if( strict ):
							// HTML allows these in attributes values
							throw "Invalid unescaped " + String.fromCharCode(c) + " in attribute value";
						case _ if (c == attrValQuote):
							buf.addSub(str, start, p - start);
							var val = buf.toString();
							buf = new StringBuf();
							xml.set(aname, val);
							state = S.IGNORE_SPACES;
							next = S.BODY;
					}
				case S.CHILDS:
					p = doParse(str, strict, p, xml);
					start = p;
					state = S.BEGIN;
				case S.WAIT_END:
					switch(c)
					{
						case '>'.code:
							state = S.BEGIN;
						default :
							throw("Expected >");
					}
				case S.WAIT_END_RET:
					switch(c)
					{
						case '>'.code:
							if( nsubs == 0 )
								parent.addChild(Xml.createPCData(""));
							return p;
						default :
							throw("Expected >");
					}
				case S.CLOSE:
					if (!isValidChar(c))
					{
						if( start == p )
							throw("Expected node name");

						var v = str.substr(start,p - start);
						if (v != parent.nodeName)
							throw "Expected </" +parent.nodeName + ">";

						state = S.IGNORE_SPACES;
						next = S.WAIT_END_RET;
						continue;
					}
				case S.COMMENT:
					if (c == '-'.code && str.fastCodeAt(p +1) == '-'.code && str.fastCodeAt(p + 2) == '>'.code)
					{
						addChild(Xml.createComment(str.substr(start, p - start)));
						p += 2;
						state = S.BEGIN;
					}
				case S.DOCTYPE:
					if(c == '['.code)
						nbrackets++;
					else if(c == ']'.code)
						nbrackets--;
					else if (c == '>'.code && nbrackets == 0)
					{
						addChild(Xml.createDocType(str.substr(start, p - start)));
						state = S.BEGIN;
					}
				case S.HEADER:
					if (c == '?'.code && str.fastCodeAt(p + 1) == '>'.code)
					{
						p++;
						var str = str.substr(start + 1, p - start - 2);
						addChild(Xml.createProcessingInstruction(str));
						state = S.BEGIN;
					}
				case S.ESCAPE:
					if (c == ';'.code)
					{
						var s = str.substr(start, p - start);
						if (s.fastCodeAt(0) == '#'.code) {
							var c = s.fastCodeAt(1) == 'x'.code
								? Std.parseInt("0" +s.substr(1, s.length - 1))
								: Std.parseInt(s.substr(1, s.length - 1));
							#if (neko || cpp || php)
							if( c >= 128 ) {
								// UTF8-encode it
								if( c <= 0x7FF ) {
									buf.addChar(0xC0 | (c >> 6));
									buf.addChar(0x80 | (c & 63));
								} else if( c <= 0xFFFF ) {
									buf.addChar(0xE0 | (c >> 12));
									buf.addChar(0x80 | ((c >> 6) & 63));
									buf.addChar(0x80 | (c & 63));
								} else if( c <= 0x10FFFF ) {
									buf.addChar(0xF0 | (c >> 18));
									buf.addChar(0x80 | ((c >> 12) & 63));
									buf.addChar(0x80 | ((c >> 6) & 63));
									buf.addChar(0x80 | (c & 63));
								} else
									throw "Cannot encode UTF8-char " + c;
							} else
							#end
							buf.addChar(c);
						} else if (!escapes.exists(s)) {
							if( strict )
								throw 'Undefined entity: $s';
							buf.add('&$s;');
						} else {
							buf.add(escapes.get(s));
						}
						start = p + 1;
						state = escapeNext;
					} else if (!isValidChar(c) && c != "#".code) {
						if( strict )
							throw 'Invalid character in entity: ' + String.fromCharCode(c);
						buf.addChar("&".code);
						buf.addSub(str, start, p - start);
						p--;
						start = p + 1;
						state = escapeNext;
					}
			}
			c = str.fastCodeAt(++p);
		}

		if (state == S.BEGIN)
		{
			start = p;
			state = S.PCDATA;
		}

		if (state == S.PCDATA)
		{
			if (p != start || nsubs == 0) {
				buf.addSub(str, start, p-start);
				addChild(Xml.createPCData(buf.toString()));
			}
			return p;
		}

		if( !strict && state == S.ESCAPE && escapeNext == S.PCDATA ) {
			buf.addChar("&".code);
			buf.addSub(str, start, p - start);
			addChild(Xml.createPCData(buf.toString()));
			return p;
		}

		throw "Unexpected end";
	}

	static inline function isValidChar(c) {
		return (c >= 'a'.code && c <= 'z'.code) || (c >= 'A'.code && c <= 'Z'.code) || (c >= '0'.code && c <= '9'.code) || c == ':'.code || c == '.'.code || c == '_'.code || c == '-'.code;
	}
}