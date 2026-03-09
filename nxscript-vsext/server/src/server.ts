import {
	createConnection,
	TextDocuments,
	Diagnostic,
	DiagnosticSeverity,
	ProposedFeatures,
	InitializeParams,
	DidChangeConfigurationNotification,
	CompletionItem,
	CompletionItemKind,
	TextDocumentPositionParams,
	TextDocumentSyncKind,
	InitializeResult,
	InsertTextFormat,
} from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { execSync } from 'child_process';
import { fileURLToPath } from 'url';

const PROJECT_SIGNATURE_POLL_MS = 2000;

interface ProjectIndexCacheEntry {
	configSignature: string;
	classPaths: string[];
	lastSignatureCheckMs: number;
}

const projectIndexCache: Map<string, ProjectIndexCacheEntry> = new Map();

const KEYWORDS = new Set([
	'let', 'var', 'const', 'func', 'fn', 'fun', 'function', 'class', 'extends', 'new', 'this',
	'if', 'else', 'elseif', 'while', 'for', 'in', 'break', 'continue', 'return',
	'try', 'catch', 'throw', 'true', 'false', 'null', 'import', 'i',
]);

type TK =
	| 'num' | 'str' | 'ident' | 'kw'
	| 'newline' | 'eof' | 'error'
	// single-char punctuation stored by value:
	| '(' | ')' | '{' | '}' | '[' | ']' | ',' | '.' | ':' | ';'
	// operators stored as their symbol string for easy matching
	| 'op';

interface Tok { type: TK; val: string; line: number; col: number; }

function tokenize(src: string): Tok[] {
	const tokens: Tok[] = [];
	let i = 0;
	let line = 1;
	let lineStart = 0;

	function col(): number { return i - lineStart + 1; }
	function tok(type: TK, val: string, l: number, c: number): void {
		tokens.push({ type, val, line: l, col: c });
	}

	while (i < src.length) {
		const l = line;
		const c = col();
		const ch = src[i];

		// Newline
		if (ch === '\n') {
			tok('newline', '\n', l, c);
			i++; line++; lineStart = i;
			continue;
		}
		// \r\n or \r
		if (ch === '\r') {
			tok('newline', '\n', l, c);
			i++;
			if (i < src.length && src[i] === '\n') { i++; }
			line++; lineStart = i;
			continue;
		}

		// Whitespace
		if (ch === ' ' || ch === '\t') { i++; continue; }

		// Line comment
		if (ch === '#') {
			while (i < src.length && src[i] !== '\n' && src[i] !== '\r') i++;
			continue;
		}

		// Block comment
		if (ch === '/' && src[i + 1] === '*') {
			i += 2;
			while (i < src.length) {
				if (src[i] === '\n') { line++; lineStart = i + 1; }
				if (src[i] === '*' && src[i + 1] === '/') { i += 2; break; }
				i++;
			}
			continue;
		}

		// Strings
		if (ch === '"' || ch === "'") {
			const q = ch;
			i++;
			let val = '';
			let terminated = false;
			while (i < src.length) {
				const s = src[i];
				if (s === '\\') {
					i++;
					if (i < src.length) { val += src[i]; i++; }
				} else if (s === q) {
					i++; terminated = true; break;
				} else if (s === '\n' || s === '\r') {
					break;
				} else {
					val += s; i++;
				}
			}
			if (!terminated) {
				tok('error', `Unterminated string`, l, c);
			} else {
				tok('str', val, l, c);
			}
			continue;
		}

		// Numbers
		if (ch >= '0' && ch <= '9') {
			let val = '';
			while (i < src.length && ((src[i] >= '0' && src[i] <= '9') || src[i] === '.')) {
				val += src[i]; i++;
			}
			tok('num', val, l, c);
			continue;
		}
		// Number starting with dot
		if (ch === '.' && i + 1 < src.length && src[i + 1] >= '0' && src[i + 1] <= '9') {
			let val = '.';
			i++;
			while (i < src.length && ((src[i] >= '0' && src[i] <= '9') || src[i] === '.')) {
				val += src[i]; i++;
			}
			tok('num', val, l, c);
			continue;
		}

		// Identifiers / keywords
		if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch === '_') {
			let val = '';
			while (i < src.length &&
				((src[i] >= 'a' && src[i] <= 'z') || (src[i] >= 'A' && src[i] <= 'Z') ||
				 (src[i] >= '0' && src[i] <= '9') || src[i] === '_')) {
				val += src[i]; i++;
			}
			tok(KEYWORDS.has(val) ? 'kw' : 'ident', val, l, c);
			continue;
		}

		// Two-char then one-char operators
		const two = src.slice(i, i + 2);
		if (two === '==' || two === '!=' || two === '<=' || two === '>=' ||
			two === '&&' || two === '||' || two === '+=' || two === '-=' ||
			two === '*=' || two === '/=' || two === '%=' || two === '++' ||
			two === '--' || two === '<<' || two === '>>') {
			tok('op', two, l, c); i += 2; continue;
		}

		if ('+-*/%=<>!&|^~'.includes(ch)) {
			tok('op', ch, l, c); i++; continue;
		}

		// Punctuation
		if ('(){}[],.;:'.includes(ch)) {
			tok(ch as TK, ch, l, c); i++; continue;
		}

		// Unknown
		tok('error', ch, l, c); i++;
	}

	tok('eof', '', line, col());
	return tokens;
}


interface ParseError { msg: string; line: number; col: number; endCol: number; }

class Parser {
	private tokens: Tok[];
	private pos = 0;
	readonly errors: ParseError[] = [];

	constructor(tokens: Tok[]) {
		// strip newlines & errors from token stream for parsing, but record errors
		this.tokens = tokens.filter(t => {
			if (t.type === 'error') {
				this.errors.push({ msg: t.val, line: t.line, col: t.col, endCol: t.col + 1 });
				return false;
			}
			return true;
		});
	}

	private peek(): Tok { return this.tokens[this.pos] ?? { type: 'eof', val: '', line: 0, col: 0 }; }
	private prev(): Tok { return this.tokens[this.pos - 1] ?? this.peek(); }
	private isEOF(): boolean { return this.peek().type === 'eof'; }

	private advance(): Tok {
		if (!this.isEOF()) this.pos++;
		return this.prev();
	}

	private skipNewlines(): void {
		while (this.peek().type === 'newline') this.advance();
	}

	private skipSeparators(): void {
		while (this.peek().type === 'newline' || this.peek().type === ';') this.advance();
	}

	/** Check if current token matches; if so advance and return true. */
	private match(type: TK, val?: string): boolean {
		const t = this.peek();
		if (t.type !== type) return false;
		if (val !== undefined && t.val !== val) return false;
		this.advance();
		return true;
	}

	private expect(type: TK, val: string): boolean {
		if (this.match(type, val)) return true;
		const t = this.peek();
		this.error(`Expected '${val}'`, t);
		return false;
	}

	private error(msg: string, tok?: Tok): void {
		const t = tok ?? this.peek();
		this.errors.push({ msg, line: t.line, col: t.col, endCol: t.col + t.val.length });
	}

	/** Synchronize: skip to next separator, '}', or EOF on error. */
	private sync(): void {
		while (!this.isEOF()) {
			const t = this.peek();
			if (t.type === 'newline' || t.type === ';' || (t.type === '}' && t.val === '}')) return;
			this.advance();
		}
	}

	parse(): void {
		while (!this.isEOF()) {
			this.skipSeparators();
			if (this.isEOF()) break;
			try { this.parseStatement(); }
			catch { this.sync(); }
		}
	}


	private parseStatement(): void {
		this.skipSeparators();
		const t = this.peek();

		if (t.type === 'kw') {
			switch (t.val) {
				case 'let': case 'var': case 'const': this.parseVarDecl(); return;
				case 'func': case 'fn': case 'fun': case 'function': this.parseFuncDecl(); return;
				case 'class':   this.parseClassDecl(); return;
				case 'return':  this.advance(); if (!this.isNewlineOrEOF()) this.parseExpr(); return;
				case 'throw':   this.advance(); this.parseExpr(); return;
				case 'if':      this.parseIf(); return;
				case 'while':   this.parseWhile(); return;
				case 'for':     this.parseFor(); return;
				case 'try':     this.parseTryCatch(); return;
				case 'break': case 'continue': this.advance(); return;
			}
		}

		if (t.type === '{') { this.parseBlock(); return; }

		this.parseExpr();
	}

	private isNewlineOrEOF(): boolean {
		const t = this.peek();
		return t.type === 'newline' || t.type === 'eof';
	}

	private parseVarDecl(): void {
		this.advance(); // consume let/var/const
		if (this.peek().type !== 'ident') {
			this.error('Expected variable name', this.peek());
			this.sync(); return;
		}
		this.advance(); // name
		// optional type hint
		if (this.peek().type === ':') {
			this.advance();
			this.parseTypeName();
		}
		// optional initializer
		if (this.peek().type === 'op' && this.peek().val === '=') {
			this.advance();
			this.parseExpr();
		}
	}

	private parseFuncDecl(): void {
		this.advance(); // consume 'func'
		if (this.peek().type === 'kw' && this.peek().val === 'new') {
			this.advance();
		} else if (this.peek().type !== 'ident') {
			this.error('Expected function name', this.peek());
		} else {
			this.advance();
		}
		this.parseParamList();
		this.skipSeparators();
		if (this.peek().type !== '{') {
			this.error("Expected '{' before function body", this.peek());
			this.sync(); return;
		}
		this.parseBlock();
	}

	private parseParamList(): void {
		if (!this.expect('(', '(')) return;
		this.skipNewlines();
		while (!this.isEOF() && !(this.peek().type === ')')) {
			if (this.peek().type !== 'ident') {
				this.error('Expected parameter name', this.peek()); break;
			}
			this.advance();
			// optional type hint
			if (this.peek().type === ':') {
				this.advance();
				this.parseTypeName();
			}
			if (!this.match(',')) break;
			this.skipNewlines();
		}
		this.expect(')', ')');
	}

	private parseTypeName(): void {
		if (this.peek().type !== 'ident') {
			this.error('Expected type name', this.peek());
			return;
		}
		this.advance();
		while (this.peek().type === '.') {
			this.advance();
			if (this.peek().type !== 'ident') {
				this.error('Expected type name segment after dot', this.peek());
				return;
			}
			this.advance();
		}
	}

	private parseClassDecl(): void {
		this.advance(); // consume 'class'
		if (this.peek().type !== 'ident') {
			this.error('Expected class name', this.peek());
		} else {
			this.advance();
		}
		if (this.peek().type === 'kw' && this.peek().val === 'extends') {
			this.advance();
			if (this.peek().type !== 'ident') {
				this.error('Expected parent class name', this.peek());
			} else {
				this.advance();
			}
		}
		this.skipSeparators();
		if (this.peek().type !== '{') {
			this.error("Expected '{' before class body", this.peek()); return;
		}
		this.parseClassBody();
	}

	private parseClassBody(): void {
		this.advance(); // consume '{'
		this.skipSeparators();
		while (!this.isEOF() && !(this.peek().type === '}')) {
			const t = this.peek();
			if (t.type === 'kw' && (t.val === 'var' || t.val === 'let' || t.val === 'const')) {
				this.parseVarDecl();
			} else if (t.type === 'kw' && (t.val === 'func' || t.val === 'fn' || t.val === 'fun' || t.val === 'function')) {
				this.parseFuncDecl();
			} else {
				this.error("Expected 'var' or function declaration in class body", t);
				this.advance();
			}
			this.skipSeparators();
		}
		if (!this.match('}')) {
			this.error("Expected '}' to close class body", this.peek());
		}
	}

	private parseIf(): void {
		this.advance(); // consume 'if'
		this.expect('(', '(');
		this.parseExpr();
		this.expect(')', ')');
		this.skipSeparators();
		if (this.peek().type !== '{') {
			this.error("Expected '{' after if condition", this.peek()); return;
		}
		this.parseBlock();
		// elseif / else chains
		while (true) {
			this.skipSeparators();
			const t = this.peek();
			if (t.type === 'kw' && t.val === 'elseif') {
				this.advance();
				this.expect('(', '(');
				this.parseExpr();
				this.expect(')', ')');
				this.skipSeparators();
				if (this.peek().type !== '{') { this.error("Expected '{'", this.peek()); return; }
				this.parseBlock();
			} else if (t.type === 'kw' && t.val === 'else') {
				this.advance();
				this.skipSeparators();
				if (this.peek().type === 'kw' && this.peek().val === 'if') {
					// Support both `elseif` and `else if` chains.
					this.parseIf();
					break;
				}
				if (this.peek().type !== '{') { this.error("Expected '{'", this.peek()); return; }
				this.parseBlock();
				break;
			} else {
				break;
			}
		}
	}

	private parseWhile(): void {
		this.advance();
		this.expect('(', '(');
		this.parseExpr();
		this.expect(')', ')');
		this.skipSeparators();
		if (this.peek().type !== '{') { this.error("Expected '{' after while condition", this.peek()); return; }
		this.parseBlock();
	}

	private parseFor(): void {
		this.advance();
		if (this.peek().type === '(') this.advance();
		if (this.peek().type !== 'ident') { this.error('Expected loop variable', this.peek()); return; }
		this.advance();
		if (!(this.peek().type === 'kw' && this.peek().val === 'in')) {
			this.error("Expected 'in'", this.peek()); return;
		}
		this.advance();
		this.parseExpr();
		if (this.peek().type === ')') this.advance();
		this.skipSeparators();
		if (this.peek().type !== '{') { this.error("Expected '{' after for expression", this.peek()); return; }
		this.parseBlock();
	}

	private parseTryCatch(): void {
		this.advance(); // 'try'
		this.skipSeparators();
		if (this.peek().type !== '{') { this.error("Expected '{' after 'try'", this.peek()); return; }
		this.parseBlock();
		this.skipSeparators();
		if (!(this.peek().type === 'kw' && this.peek().val === 'catch')) {
			this.error("Expected 'catch' after try block", this.peek()); return;
		}
		this.advance();
		this.expect('(', '(');
		if (this.peek().type !== 'ident') { this.error('Expected catch variable', this.peek()); }
		else { this.advance(); }
		this.expect(')', ')');
		this.skipSeparators();
		if (this.peek().type !== '{') { this.error("Expected '{' after catch", this.peek()); return; }
		this.parseBlock();
	}

	private parseBlock(): void {
		this.advance(); // consume '{'
		this.skipSeparators();
		while (!this.isEOF() && !(this.peek().type === '}')) {
			this.parseStatement();
			this.skipSeparators();
		}
		if (!this.match('}')) {
			this.error("Expected '}' to close block", this.peek());
		}
	}


	private parseExpr(): void { this.parseAssign(); }

	private parseAssign(): void {
		this.parseOr();
		const t = this.peek();
		if (t.type === 'op' && ['=', '+=', '-=', '*=', '/=', '%='].includes(t.val)) {
			this.advance();
			this.parseAssign();
		}
	}

	private parseOr(): void {
		this.parseAnd();
		while (this.peek().type === 'op' && this.peek().val === '||') { this.advance(); this.parseAnd(); }
	}

	private parseAnd(): void {
		this.parseEquality();
		while (this.peek().type === 'op' && this.peek().val === '&&') { this.advance(); this.parseEquality(); }
	}

	private parseEquality(): void {
		this.parseComparison();
		while (this.peek().type === 'op' && ['==', '!='].includes(this.peek().val)) { this.advance(); this.parseComparison(); }
	}

	private parseComparison(): void {
		this.parseBitwise();
		while (this.peek().type === 'op' && ['<', '>', '<=', '>='].includes(this.peek().val)) { this.advance(); this.parseBitwise(); }
	}

	private parseBitwise(): void {
		this.parseAddSub();
		while (this.peek().type === 'op' && ['&', '|', '^', '<<', '>>'].includes(this.peek().val)) { this.advance(); this.parseAddSub(); }
	}

	private parseAddSub(): void {
		this.parseMulDiv();
		while (this.peek().type === 'op' && ['+', '-'].includes(this.peek().val)) { this.advance(); this.parseMulDiv(); }
	}

	private parseMulDiv(): void {
		this.parseUnary();
		while (this.peek().type === 'op' && ['*', '/', '%'].includes(this.peek().val)) { this.advance(); this.parseUnary(); }
	}

	private parseUnary(): void {
		const t = this.peek();
		if (t.type === 'op' && ['-', '!', '~', '++', '--'].includes(t.val)) {
			this.advance(); this.parseUnary();
		} else {
			this.parsePostfix();
		}
	}

	private parsePostfix(): void {
		this.parsePrimary();
		while (true) {
			const t = this.peek();
			if (t.type === '.') {
				this.advance();
				if (this.peek().type !== 'ident') { this.error('Expected property name', this.peek()); }
				else { this.advance(); }
			} else if (t.type === '[') {
				this.advance();
				this.parseExpr();
				this.expect(']', ']');
			} else if (t.type === '(') {
				this.parseArgList();
			} else if (t.type === 'op' && (t.val === '++' || t.val === '--')) {
				this.advance();
			} else {
				break;
			}
		}
	}

	private parsePrimary(): void {
		const t = this.peek();

		if (t.type === 'num' || t.type === 'str') { this.advance(); return; }

		if (t.type === 'kw') {
			if (t.val === 'true' || t.val === 'false' || t.val === 'null') { this.advance(); return; }
			if (t.val === 'this') { this.advance(); return; }
			if (t.val === 'new') {
				this.advance();
				if (this.peek().type !== 'ident') { this.error('Expected class name after new', this.peek()); return; }
				this.advance();
				this.parseArgList();
				return;
			}
		}

		if (t.type === 'ident') { this.advance(); return; }

		if (t.type === '(') {
			this.advance();
			this.parseExpr();
			this.expect(')', ')');
			return;
		}

		// Array literal
		if (t.type === '[') {
			this.advance();
			this.skipNewlines();
			while (!this.isEOF() && !(this.peek().type === ']')) {
				this.parseExpr();
				this.skipNewlines();
				if (!this.match(',')) break;
				this.skipNewlines();
			}
			this.expect(']', ']');
			return;
		}

		// Dict/object literal
		if (t.type === '{') {
			this.advance();
			this.skipNewlines();
			while (!this.isEOF() && !(this.peek().type === '}')) {
				if (this.peek().type !== 'ident' && this.peek().type !== 'str') {
					this.error('Expected key in object literal', this.peek()); break;
				}
				this.advance();
				this.expect(':', ':');
				this.parseExpr();
				this.skipNewlines();
				if (!this.match(',')) break;
				this.skipNewlines();
			}
			this.expect('}', '}');
			return;
		}

		this.error(`Unexpected token '${t.val}'`, t);
		this.advance();
	}

	private parseArgList(): void {
		this.expect('(', '(');
		this.skipNewlines();
		while (!this.isEOF() && !(this.peek().type === ')')) {
			this.parseExpr();
			this.skipNewlines();
			if (!this.match(',')) break;
			this.skipNewlines();
		}
		this.expect(')', ')');
	}
}


const KEYWORD_COMPLETIONS: CompletionItem[] = [
	{ label: 'let',      kind: CompletionItemKind.Keyword },
	{ label: 'var',      kind: CompletionItemKind.Keyword },
	{ label: 'const',    kind: CompletionItemKind.Keyword },
	{ label: 'func',     kind: CompletionItemKind.Keyword, insertText: 'func ${1:name}(${2:args}) {\n\t$0\n}', insertTextFormat: InsertTextFormat.Snippet },
	{ label: 'function', kind: CompletionItemKind.Keyword, insertText: 'function ${1:name}(${2:args}) {\n\t$0\n}', insertTextFormat: InsertTextFormat.Snippet },
	{ label: 'fn',       kind: CompletionItemKind.Keyword, insertText: 'fn ${1:name}(${2:args}) {\n\t$0\n}', insertTextFormat: InsertTextFormat.Snippet },
	{ label: 'fun',      kind: CompletionItemKind.Keyword, insertText: 'fun ${1:name}(${2:args}) {\n\t$0\n}', insertTextFormat: InsertTextFormat.Snippet },
	{ label: 'class',    kind: CompletionItemKind.Keyword, insertText: 'class ${1:Name} {\n\t$0\n}', insertTextFormat: InsertTextFormat.Snippet },
	{ label: 'extends',  kind: CompletionItemKind.Keyword },
	{ label: 'new',      kind: CompletionItemKind.Keyword },
	{ label: 'return',   kind: CompletionItemKind.Keyword },
	{ label: 'if',       kind: CompletionItemKind.Keyword, insertText: 'if (${1:cond}) {\n\t$0\n}', insertTextFormat: InsertTextFormat.Snippet },
	{ label: 'else',     kind: CompletionItemKind.Keyword, insertText: 'else {\n\t$0\n}', insertTextFormat: InsertTextFormat.Snippet },
	{ label: 'elseif',   kind: CompletionItemKind.Keyword, insertText: 'elseif (${1:cond}) {\n\t$0\n}', insertTextFormat: InsertTextFormat.Snippet },
	{ label: 'while',    kind: CompletionItemKind.Keyword, insertText: 'while (${1:cond}) {\n\t$0\n}', insertTextFormat: InsertTextFormat.Snippet },
	{ label: 'for',      kind: CompletionItemKind.Keyword, insertText: 'for ${1:item} in ${2:collection} {\n\t$0\n}', insertTextFormat: InsertTextFormat.Snippet },
	{ label: 'break',    kind: CompletionItemKind.Keyword },
	{ label: 'continue', kind: CompletionItemKind.Keyword },
	{ label: 'in',       kind: CompletionItemKind.Keyword },
	{ label: 'try',      kind: CompletionItemKind.Keyword, insertText: 'try {\n\t$1\n} catch (${2:e}) {\n\t$0\n}', insertTextFormat: InsertTextFormat.Snippet },
	{ label: 'catch',    kind: CompletionItemKind.Keyword },
	{ label: 'throw',    kind: CompletionItemKind.Keyword },
	{ label: 'true',     kind: CompletionItemKind.Value },
	{ label: 'false',    kind: CompletionItemKind.Value },
	{ label: 'null',     kind: CompletionItemKind.Value },
	{ label: 'this',     kind: CompletionItemKind.Keyword },
];

const GLOBAL_FUNCTION_COMPLETIONS: CompletionItem[] = [
	{ label: 'trace', kind: CompletionItemKind.Function, detail: 'trace(value)', documentation: 'Print a value to console.' },
	{ label: 'len',   kind: CompletionItemKind.Function, detail: 'len(value): Number', documentation: 'Returns the length of a string, array, or dict.' },
	{ label: 'type',  kind: CompletionItemKind.Function, detail: 'type(value): String', documentation: 'Returns the type name of a value.' },
];

function makeMethod(label: string, detail: string, doc?: string): CompletionItem {
	return { label, kind: CompletionItemKind.Method, detail, documentation: doc };
}

const NUMBER_METHODS: CompletionItem[] = [
	makeMethod('floor',  'floor(): Number',               'Rounds down to the nearest integer.\nExample: 3.8.floor() -> 3'),
	makeMethod('ceil',   'ceil(): Number',                'Rounds up to the nearest integer.\nExample: 3.2.ceil() -> 4'),
	makeMethod('round',  'round(): Number',               'Rounds to the nearest integer.\nExample: 3.6.round() -> 4'),
	makeMethod('abs',    'abs(): Number',                 'Returns the absolute value.\nExample: (-9).abs() -> 9'),
	makeMethod('sqrt',   'sqrt(): Number',                'Returns the square root.\nExample: 9.sqrt() -> 3'),
	makeMethod('pow',    'pow(exp: Number): Number',      'Raises the value to a power.\nExample: 2.pow(3) -> 8'),
	makeMethod('sin',    'sin(): Number',                 'Sine of the value (radians).'),
	makeMethod('cos',    'cos(): Number',                 'Cosine of the value (radians).'),
	makeMethod('tan',    'tan(): Number',                 'Tangent of the value (radians).'),
	makeMethod('asin',   'asin(): Number',                'Arc-sine result in radians.'),
	makeMethod('acos',   'acos(): Number',                'Arc-cosine result in radians.'),
	makeMethod('atan',   'atan(): Number',                'Arc-tangent result in radians.'),
	makeMethod('int',    'int(): Number',                 'Converts to integer (truncate).\nExample: 3.9.int() -> 3'),
	makeMethod('float',  'float(): Number',               'Converts to float.'),
	makeMethod('str',    'str(): String',                 'Converts to string.\nExample: 12.str() -> "12"'),
	makeMethod('bool',   'bool(): Bool',                  'Converts to boolean.\nExample: 0.bool() -> false'),
	makeMethod('add',    'add(n: Number): Number',        'Adds a number and returns the result.\nExample: 10.add(5) -> 15'),
	makeMethod('sub',    'sub(n: Number): Number',        'Subtracts a number and returns the result.\nExample: 10.sub(3) -> 7'),
	makeMethod('mul',    'mul(n: Number): Number',        'Multiplies by a number.\nExample: 6.mul(4) -> 24'),
	makeMethod('div',    'div(n: Number): Number',        'Divides by a number.\nExample: 12.div(3) -> 4'),
	makeMethod('mod',    'mod(n: Number): Number',        'Remainder after division.\nExample: 10.mod(4) -> 2'),
	makeMethod('min',    'min(n: Number): Number',        'Returns the smaller value.\nExample: 5.min(8) -> 5'),
	makeMethod('max',    'max(n: Number): Number',        'Returns the larger value.\nExample: 5.max(8) -> 8'),
];

const STRING_METHODS: CompletionItem[] = [
	makeMethod('length',   'length: Number',              'Length of the string.'),
	makeMethod('upper',    'upper(): String',             'Convert to uppercase.'),
	makeMethod('lower',    'lower(): String',             'Convert to lowercase.'),
	makeMethod('trim',     'trim(): String',              'Remove leading/trailing whitespace.'),
	makeMethod('int',      'int(): Number',               'Parse as integer.'),
	makeMethod('float',    'float(): Number',             'Parse as float.'),
	makeMethod('bool',     'bool(): Bool',                'Parse as bool.'),
	makeMethod('contains', 'contains(sub: String): Bool', 'Check if string contains substring.'),
	makeMethod('indexOf',  'indexOf(sub: String): Number','First index of substring, or -1.'),
	makeMethod('charAt',   'charAt(i: Number): String',   'Character at index.'),
	makeMethod('substr',   'substr(start: Number, len: Number): String', 'Substring.'),
	makeMethod('split',    'split(sep: String): Array',   'Split into array.'),
];

const ARRAY_METHODS: CompletionItem[] = [
	makeMethod('length',   'length: Number',             'Number of elements.'),
	makeMethod('push',     'push(value): Void',          'Append to end.'),
	makeMethod('pop',      'pop(): value',               'Remove and return last element.'),
	makeMethod('shift',    'shift(): value',             'Remove and return first element.'),
	makeMethod('unshift',  'unshift(value): Void',       'Prepend element.'),
	makeMethod('first',    'first(): value',             'First element.'),
	makeMethod('last',     'last(): value',              'Last element.'),
	makeMethod('contains', 'contains(value): Bool',      'Check if array contains value.'),
	makeMethod('indexOf',  'indexOf(value): Number',     'Index of value, or -1.'),
	makeMethod('reverse',  'reverse(): Void',            'Reverse in place.'),
	makeMethod('join',     'join(sep: String): String',  'Join elements into string.'),
];

const KNOWN_NUMBER_METHODS = new Set(NUMBER_METHODS.map(m => String(m.label)));
const KNOWN_STRING_METHODS = new Set(STRING_METHODS.map(m => String(m.label)));
const KNOWN_ARRAY_METHODS = new Set(ARRAY_METHODS.map(m => String(m.label)));

interface ImportStmt {
	module: string;
	line: number;
	col: number;
}

const IMPORT_LINE_RE = /^\s*(?:i|import)\s+(?:"([A-Za-z_][A-Za-z0-9_\.]*)"|'([A-Za-z_][A-Za-z0-9_\.]*)'|([A-Za-z_][A-Za-z0-9_\.]*))\s*;?\s*$/;

let workspaceRoot: string | null = null;
let knownModules: Set<string> = new Set();
let moduleIndexReady = false;
let discoveredClassPaths: string[] = [];
let knownModuleFiles: Map<string, string> = new Map();
let nativeMembersCache: Map<string, CompletionItem[]> = new Map();

/** Returns method completions based on identifier before the dot. */
function getMethodCompletions(document: TextDocument, position: { line: number; character: number }): CompletionItem[] {
	const text = document.getText();
	const lines = text.split('\n');
	const currentLine = lines[position.line] ?? '';
	const beforeDot = currentLine.slice(0, Math.max(0, position.character - 1)); // -1 for '.'
	const importsMap = buildImportShortNameMap(text);

	if (/\b\d+(?:\.\d+)?\s*$/.test(beforeDot)) {
		return sortCompletionItemsForDisplay(NUMBER_METHODS);
	}
	if (/("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')\s*$/.test(beforeDot)) {
		return sortCompletionItemsForDisplay(STRING_METHODS);
	}
	if (/\[[^\]\n]*\]\s*$/.test(beforeDot)) {
		return sortCompletionItemsForDisplay(ARRAY_METHODS);
	}

	const idMatch = beforeDot.match(/([a-zA-Z_][a-zA-Z0-9_]*)\s*$/);
	if (!idMatch) {
		return sortCompletionItemsForDisplay([...NUMBER_METHODS, ...STRING_METHODS, ...ARRAY_METHODS]);
	}

	const target = idMatch[1];
	if (target === 'this') {
		const localMembers = extractLocalClassMembers(text);
		const inferredThisType = inferThisType(text, importsMap);
		const inheritedMembers = inferredThisType ? getTypeCompletionItems(inferredThisType, importsMap) : [];
		if (localMembers.length === 0) return sortCompletionItemsForDisplay(inheritedMembers);
		return mergeCompletionItems(localMembers, inheritedMembers);
	}

	const inferredType = inferIdentifierType(text, target, position.line, importsMap);
	if (inferredType == null) {
		return [...NUMBER_METHODS, ...STRING_METHODS, ...ARRAY_METHODS];
	}

	const primitive = normalizePrimitiveType(inferredType);
	if (primitive === 'Number') return sortCompletionItemsForDisplay(NUMBER_METHODS);
	if (primitive === 'String') return sortCompletionItemsForDisplay(STRING_METHODS);
	if (primitive === 'Array') return sortCompletionItemsForDisplay(ARRAY_METHODS);

	const nativeMembers = getNativeTypeMembers(inferredType, importsMap);
	if (nativeMembers.length > 0) return nativeMembers;

	return sortCompletionItemsForDisplay([...NUMBER_METHODS, ...STRING_METHODS, ...ARRAY_METHODS]);
}

function inferIdentifierType(text: string, ident: string, _line: number, importsMap: Map<string, string>): string | null {
	if (ident === 'this') {
		const thisType = inferThisType(text, importsMap);
		if (thisType) return thisType;
	}

	const escaped = ident.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
	const lines = text.split(/\r?\n/);
	let inferred: string | null = null;

	const typedDecl = new RegExp(`\\b(?:let|var|const)\\s+${escaped}\\s*:\\s*([A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z_][A-Za-z0-9_]*)*)`);
	const newDecl = new RegExp(`\\b(?:let|var|const)\\s+${escaped}\\s*=\\s*new\\s+([A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z_][A-Za-z0-9_]*)*)`);
	const assignNew = new RegExp(`\\b${escaped}\\s*=\\s*new\\s+([A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z_][A-Za-z0-9_]*)*)`);
	const assignStr = new RegExp(`\\b${escaped}\\s*=\\s*("(?:[^"\\\\]|\\\\.)*"|'(?:[^'\\\\]|\\\\.)*')`);
	const assignNum = new RegExp(`\\b${escaped}\\s*=\\s*[-+]?\\d+(?:\\.\\d+)?\\b`);
	const assignArr = new RegExp(`\\b${escaped}\\s*=\\s*\\[`);

	for (const line of lines) {
		let m = line.match(typedDecl);
		if (m && m[1]) inferred = m[1];
		m = line.match(newDecl);
		if (m && m[1]) inferred = m[1];
		m = line.match(assignNew);
		if (m && m[1]) inferred = m[1];
		if (assignStr.test(line)) inferred = 'String';
		if (assignNum.test(line)) inferred = 'Number';
		if (assignArr.test(line)) inferred = 'Array';
	}

	if (inferred && importsMap.has(inferred)) {
		return importsMap.get(inferred) ?? inferred;
	}

	return inferred;
}

function inferThisType(text: string, importsMap: Map<string, string>): string | null {
	const classHeaderRe = /\bclass\s+[A-Za-z_][A-Za-z0-9_]*\s+extends\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)/;
	const m = text.match(classHeaderRe);
	if (!m || !m[1]) return null;
	const t = m[1];
	if (importsMap.has(t)) return importsMap.get(t) ?? t;
	return t;
}

function normalizePrimitiveType(typeName: string): 'Number' | 'String' | 'Array' | null {
	const t = typeName.trim();
	if (t === 'Number' || t === 'Int' || t === 'Float') return 'Number';
	if (t === 'String') return 'String';
	if (t === 'Array' || t.startsWith('Array<') || t.startsWith('[')) return 'Array';
	return null;
}

function getNativeTypeMembers(typeName: string, importsMap: Map<string, string>): CompletionItem[] {
	const resolved = resolveModuleName(typeName, importsMap);
	if (!resolved) return [];

	if (nativeMembersCache.has(resolved)) {
		return nativeMembersCache.get(resolved) ?? [];
	}

	const file = knownModuleFiles.get(resolved);
	if (!file || !fs.existsSync(file)) {
		nativeMembersCache.set(resolved, []);
		return [];
	}

	let content = '';
	try {
		content = fs.readFileSync(file, 'utf8');
	} catch {
		nativeMembersCache.set(resolved, []);
		return [];
	}

	const parsed = parseNativeMembersFromHaxe(content, resolved);
	const visible = parsed
		.filter(m => !m.isPrivate && !m.isHidden)
		.map(m => m.item);
	const ordered = sortCompletionItemsForDisplay(visible);

	nativeMembersCache.set(resolved, ordered);
	return ordered;
}

interface ParsedNativeMember {
	item: CompletionItem;
	isPrivate: boolean;
	isHidden: boolean;
}

function parseNativeMembersFromHaxe(content: string, moduleName: string): ParsedNativeMember[] {
	const out: ParsedNativeMember[] = [];
	const seen = new Set<string>();
	const lines = content.split(/\r?\n/);

	let inDoc = false;
	let docBuffer: string[] = [];
	let pendingDoc = '';
	let pendingMeta: string[] = [];

	for (const rawLine of lines) {
		const line = rawLine.trim();
		if (!line) continue;

		if (line.startsWith('/**')) {
			inDoc = true;
			docBuffer = [line];
			if (line.includes('*/')) {
				inDoc = false;
				pendingDoc = normalizeDocComment(docBuffer.join('\n'));
				docBuffer = [];
			}
			continue;
		}
		if (inDoc) {
			docBuffer.push(line);
			if (line.includes('*/')) {
				inDoc = false;
				pendingDoc = normalizeDocComment(docBuffer.join('\n'));
				docBuffer = [];
			}
			continue;
		}

		if (line.startsWith('@:')) {
			pendingMeta.push(line);
			continue;
		}

		const isPrivate = /\bprivate\b/.test(line);
		const hasHideMeta = /@:dox\s*\(\s*hide\s*\)/i.test(line) || pendingMeta.some(m => /@:dox\s*\(\s*hide\s*\)/i.test(m));

		const fn = line.match(/\bfunction\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*(?::\s*([A-Za-z0-9_\.<>,\[\]]+))?/);
		if (fn && fn[1]) {
			const name = fn[1];
			if (!seen.has(name)) {
				seen.add(name);
				const params = (fn[2] ?? '').trim();
				const ret = (fn[3] ?? 'Dynamic').trim();
				const summary = pendingDoc || `Native method from ${moduleName}.`;
				out.push({
					isPrivate,
					isHidden: hasHideMeta,
					item: {
						label: name,
						kind: CompletionItemKind.Method,
						detail: `${name}(${params}): ${ret}`,
						documentation: `${summary}\nowner: ${moduleName}`,
					},
				});
			}
			pendingDoc = '';
			pendingMeta = [];
			continue;
		}

		const vf = line.match(/\bvar\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*([A-Za-z0-9_\.<>,\[\]]+))?/);
		if (vf && vf[1]) {
			const name = vf[1];
			if (!seen.has(name)) {
				seen.add(name);
				const typ = (vf[2] ?? 'Dynamic').trim();
				const summary = pendingDoc || `Native field from ${moduleName}.`;
				out.push({
					isPrivate,
					isHidden: hasHideMeta,
					item: {
						label: name,
						kind: CompletionItemKind.Field,
						detail: `${name}: ${typ}`,
						documentation: `${summary}\nowner: ${moduleName}`,
					},
				});
			}
			pendingDoc = '';
			pendingMeta = [];
			continue;
		}

		pendingDoc = '';
		pendingMeta = [];
	}

	return out;
}

function normalizeDocComment(raw: string): string {
	return raw
		.replace(/^\s*\/\*\*?/, '')
		.replace(/\*\/\s*$/, '')
		.split(/\r?\n/)
		.map(l => l.replace(/^\s*\*\s?/, '').trim())
		.filter(Boolean)
		.join('\n')
		.trim();
}

function sortCompletionItemsForDisplay(items: CompletionItem[]): CompletionItem[] {
	const copy = [...items];
	copy.sort((a, b) => {
		const la = String(a.label ?? '');
		const lb = String(b.label ?? '');
		const aUnderscore = la.startsWith('_');
		const bUnderscore = lb.startsWith('_');
		if (aUnderscore !== bUnderscore) return aUnderscore ? 1 : -1;
		return la.localeCompare(lb);
	});
	return copy;
}

function resolveModuleName(typeName: string, importsMap: Map<string, string>): string | null {
	if (importsMap.has(typeName)) return importsMap.get(typeName) ?? typeName;
	const shortDirect = typeName.split('.').pop();
	if (shortDirect && importsMap.has(shortDirect)) return importsMap.get(shortDirect) ?? shortDirect;

	if (knownModuleFiles.has(typeName)) return typeName;

	const short = typeName.split('.').pop();
	if (!short) return null;

	for (const m of knownModuleFiles.keys()) {
		if (m === short || m.endsWith(`.${short}`)) return m;
	}
	return null;
}

function buildImportShortNameMap(text: string): Map<string, string> {
	const out = new Map<string, string>();
	for (const imp of extractImports(text)) {
		const parts = imp.module.split('.');
		const short = parts[parts.length - 1];
		out.set(short, imp.module);
		out.set(imp.module, imp.module);
	}
	return out;
}


const connection = createConnection(ProposedFeatures.all);
const documents: TextDocuments<TextDocument> = new TextDocuments(TextDocument);

let hasConfigurationCapability = false;

connection.onInitialize((params: InitializeParams) => {
	workspaceRoot = normalizeWorkspaceRoot(params);
	buildModuleIndex();

	const capabilities = params.capabilities;
	hasConfigurationCapability = !!(capabilities.workspace && !!capabilities.workspace.configuration);

	const result: InitializeResult = {
		capabilities: {
			textDocumentSync: TextDocumentSyncKind.Incremental,
			completionProvider: {
				resolveProvider: false,
				triggerCharacters: ['.'],
			},
			hoverProvider: true,
		},
	};
	return result;
});

connection.onInitialized(() => {
	if (hasConfigurationCapability) {
		connection.client.register(DidChangeConfigurationNotification.type, undefined);
	}
});

// Validate on open/change
documents.onDidChangeContent(change => { validateDocument(change.document); });
documents.onDidOpen(event => { validateDocument(event.document); });

function validateDocument(document: TextDocument): void {
	refreshClassPathsForDocument(document);

	const text = document.getText();
	const importStmts = extractImports(text);
	const stripped = stripImportLines(text);

	const tokens = tokenize(stripped);
	const parser = new Parser(tokens);
	parser.parse();

	const diagnostics: Diagnostic[] = parser.errors.map(e => {
		const startPos = { line: e.line - 1, character: e.col - 1 };
		const endPos   = { line: e.line - 1, character: e.endCol - 1 };
		return {
			severity: DiagnosticSeverity.Error,
			range: { start: startPos, end: endPos },
			message: e.msg,
			source: 'nxscript',
		};
	});

	const nativeImportDiagnostics = runNativeHaxeImportDiagnostics(document, importStmts);
	if (nativeImportDiagnostics != null) {
		diagnostics.push(...nativeImportDiagnostics);
	} else {
		for (const imp of importStmts) {
			if (!isImportResolvable(imp.module)) {
				diagnostics.push({
					severity: DiagnosticSeverity.Warning,
					range: {
						start: { line: imp.line - 1, character: imp.col - 1 },
						end: { line: imp.line - 1, character: imp.col - 1 + imp.module.length },
					},
					message: `Cant find module that package name: ${imp.module}`,
					source: 'nxscript',
				});
			}
		}
	}

	diagnostics.push(...findNativeMethodDiagnostics(document));

	connection.sendDiagnostics({ uri: document.uri, diagnostics });
}

function refreshClassPathsForDocument(document: TextDocument): void {
	let filePath = '';
	try {
		filePath = fileURLToPath(document.uri);
	} catch {
		return;
	}

	const projectRoot = findNearestProjectRoot(path.dirname(filePath));
	if (!projectRoot) return;

	updateProjectIndexIfNeeded(projectRoot, false);
}

function updateProjectIndexIfNeeded(projectRoot: string, forceRebuild: boolean): void {
	const now = Date.now();
	const cached = projectIndexCache.get(projectRoot);

	if (!forceRebuild && cached && (now - cached.lastSignatureCheckMs) < PROJECT_SIGNATURE_POLL_MS) {
		return;
	}

	const signature = getProjectConfigSignature(projectRoot);
	if (!forceRebuild && cached && cached.configSignature === signature) {
		cached.lastSignatureCheckMs = now;
		projectIndexCache.set(projectRoot, cached);
		return;
	}

	const classPaths = dedupePaths([
		path.join(projectRoot, 'src'),
		path.join(projectRoot, 'source'),
		...discoverLimeClassPaths(projectRoot),
	]).filter(cp => fs.existsSync(cp));

	projectIndexCache.set(projectRoot, {
		configSignature: signature,
		classPaths,
		lastSignatureCheckMs: now,
	});

	rebuildGlobalModuleIndexFromProjects();
}

function rebuildGlobalModuleIndexFromProjects(): void {
	knownModules = new Set();
	knownModuleFiles = new Map();
	nativeMembersCache = new Map();

	const allClassPaths: string[] = [];
	for (const entry of projectIndexCache.values()) {
		for (const cp of entry.classPaths) {
			allClassPaths.push(cp);
		}
	}

	discoveredClassPaths = dedupePaths(allClassPaths);
	for (const cp of discoveredClassPaths) {
		scanHxModules(cp, cp, knownModules, knownModuleFiles);
	}
}

function getProjectConfigSignature(projectRoot: string): string {
	const files = collectProjectConfigFiles(projectRoot);
	if (files.length === 0) return 'no-project-config';

	const parts: string[] = [];
	for (const file of files) {
		try {
			const st = fs.statSync(file);
			const rel = path.relative(projectRoot, file).replace(/\\/g, '/');
			parts.push(`${rel}:${st.size}:${Math.trunc(st.mtimeMs)}`);
		} catch {
			const rel = path.relative(projectRoot, file).replace(/\\/g, '/');
			parts.push(`${rel}:missing`);
		}
	}

	parts.sort();
	return parts.join('|');
}

function collectProjectConfigFiles(projectRoot: string): string[] {
	const out: string[] = [];
	const projectXml = path.join(projectRoot, 'Project.xml');
	if (fs.existsSync(projectXml)) out.push(projectXml);

	collectHxmlFiles(projectRoot, projectRoot, out, 0, 4);
	return dedupePaths(out);
}

function collectHxmlFiles(projectRoot: string, dir: string, out: string[], depth: number, maxDepth: number): void {
	if (depth > maxDepth) return;

	let entries: fs.Dirent[];
	try {
		entries = fs.readdirSync(dir, { withFileTypes: true });
	} catch {
		return;
	}

	for (const entry of entries) {
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) {
			if (entry.name === '.git' || entry.name === 'node_modules' || entry.name === 'export' || entry.name === 'bin' || entry.name === 'obj') {
				continue;
			}
			collectHxmlFiles(projectRoot, full, out, depth + 1, maxDepth);
			continue;
		}

		if (entry.isFile() && entry.name.toLowerCase().endsWith('.hxml')) {
			out.push(full);
		}
	}
}
function findNearestProjectRoot(startDir: string): string | null {
	let dir = startDir;
	while (true) {
		if (fs.existsSync(path.join(dir, 'Project.xml')) || fs.existsSync(path.join(dir, 'haxelib.json')) || fs.existsSync(path.join(dir, '.git'))) {
			return dir;
		}
		const parent = path.dirname(dir);
		if (parent === dir) break;
		dir = parent;
	}
	return null;
}

// Completion
connection.onCompletion((params: TextDocumentPositionParams): CompletionItem[] => {
	const document = documents.get(params.textDocument.uri);
	if (!document) return [];
	refreshClassPathsForDocument(document);

	// Check if triggered by a dot
	const lines = document.getText().split('\n');
	const line = lines[params.position.line] ?? '';
	const charBefore = line[params.position.character - 1];

	if (charBefore === '.') {
		return getMethodCompletions(document, params.position);
	}

	return [...KEYWORD_COMPLETIONS, ...GLOBAL_FUNCTION_COMPLETIONS, {
		label: 'import',
		kind: CompletionItemKind.Keyword,
		insertText: 'import "${1:package.name}"',
		insertTextFormat: InsertTextFormat.Snippet,
	}, {
		label: 'i',
		kind: CompletionItemKind.Keyword,
		insertText: 'i "${1:package.name}"',
		insertTextFormat: InsertTextFormat.Snippet,
	}];
});

connection.onHover((params) => {
	const document = documents.get(params.textDocument.uri);
	if (!document) return null;

	refreshClassPathsForDocument(document);
	return buildHover(document, params.position.line, params.position.character);
});

function buildHover(document: TextDocument, line: number, character: number): { contents: string } | null {
	const text = document.getText();
	const lines = text.split(/\r?\n/);
	const lineText = lines[line] ?? '';
	const symbol = getWordAt(lineText, character);
	if (!symbol) return null;

	const importsMap = buildImportShortNameMap(text);

	const memberCtx = getMemberHoverContext(lineText, character, symbol);
	if (memberCtx != null) {
		const ownerType = inferIdentifierType(text, memberCtx.owner, line, importsMap);
		const items = ownerType ? getTypeCompletionItems(ownerType, importsMap) : [];
		const memberPool = memberCtx.owner === 'this'
			? mergeCompletionItems(extractLocalClassMembers(text), items)
			: items;
		const item = memberPool.find(i => String(i.label) === symbol);
		if (item) {
			const ownerLabel = ownerType ?? 'this';
			return { contents: formatHover(item, ownerLabel) };
		}
	}

	if (symbol === 'this') {
		const thisType = inferThisType(text, importsMap);
		if (thisType) {
			return { contents: `this: ${thisType}` };
		}
	}

	const inferred = inferIdentifierType(text, symbol, line, importsMap);
	if (inferred) {
		return { contents: `${symbol}: ${inferred}` };
	}

	const fn = findFunctionSignature(text, symbol);
	if (fn) {
		return { contents: fn };
	}

	const global = GLOBAL_FUNCTION_COMPLETIONS.find(i => String(i.label) === symbol);
	if (global) {
		const detail = global.detail ? String(global.detail) : `${symbol}()`;
		const doc = global.documentation ? String(global.documentation) : '';
		return { contents: doc ? `${detail}\n${doc}` : detail };
	}

	return null;
}

function getTypeCompletionItems(typeName: string, importsMap: Map<string, string>): CompletionItem[] {
	const primitive = normalizePrimitiveType(typeName);
	if (primitive === 'Number') return NUMBER_METHODS;
	if (primitive === 'String') return STRING_METHODS;
	if (primitive === 'Array') return ARRAY_METHODS;
	return getNativeTypeMembers(typeName, importsMap);
}

function extractLocalClassMembers(text: string): CompletionItem[] {
	const items: CompletionItem[] = [];
	const seen = new Set<string>();

	const varRe = /\bvar\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*([A-Za-z_][A-Za-z0-9_\.<>\[\]]*))?/g;
	let m: RegExpExecArray | null;
	while ((m = varRe.exec(text)) !== null) {
		const name = m[1];
		if (!name || seen.has(name)) continue;
		seen.add(name);
		const typ = (m[2] ?? 'Dynamic').trim();
		items.push({
			label: name,
			kind: CompletionItemKind.Field,
			detail: `${name}: ${typ}`,
			documentation: 'Field declared in current script class',
		});
	}

	const fnRe = /\b(?:func|function|fn|fun)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*(?:(?:->|:)\s*([A-Za-z_][A-Za-z0-9_\.<>\[\]]*))?/g;
	while ((m = fnRe.exec(text)) !== null) {
		const name = m[1];
		if (!name || seen.has(name)) continue;
		seen.add(name);
		const args = (m[2] ?? '').trim();
		const ret = (m[3] ?? 'Dynamic').trim();
		items.push({
			label: name,
			kind: CompletionItemKind.Method,
			detail: `${name}(${args}): ${ret}`,
			documentation: 'Method declared in current script class',
		});
	}

	return sortCompletionItemsForDisplay(items);
}

function mergeCompletionItems(primary: CompletionItem[], secondary: CompletionItem[]): CompletionItem[] {
	const out: CompletionItem[] = [];
	const seen = new Set<string>();

	for (const item of [...primary, ...secondary]) {
		const key = String(item.label);
		if (seen.has(key)) continue;
		seen.add(key);
		out.push(item);
	}

	return sortCompletionItemsForDisplay(out);
}

function formatHover(item: CompletionItem, ownerType: string): string {
	const detail = item.detail ? String(item.detail) : String(item.label);
	const doc = item.documentation ? String(item.documentation) : '';
	if (doc) return `${detail}\n${doc}\nowner: ${ownerType}`;
	return `${detail}\nowner: ${ownerType}`;
}

function getMemberHoverContext(lineText: string, character: number, symbol: string): { owner: string } | null {
	const symbolStart = findWordStart(lineText, symbol, character);
	if (symbolStart <= 0) return null;

	let i = symbolStart - 1;
	while (i >= 0 && /\s/.test(lineText[i])) i--;
	if (i < 0 || lineText[i] !== '.') return null;

	let j = i - 1;
	while (j >= 0 && /\s/.test(lineText[j])) j--;
	if (j < 0) return null;

	let end = j + 1;
	while (j >= 0 && /[A-Za-z0-9_]/.test(lineText[j])) j--;
	const owner = lineText.slice(j + 1, end);
	if (!owner) return null;
	return { owner };
}

function findWordStart(lineText: string, symbol: string, character: number): number {
	const max = Math.min(character, lineText.length);
	for (let i = max; i >= 0; i--) {
		if (lineText.slice(i, i + symbol.length) === symbol) return i;
	}
	return -1;
}

function getWordAt(lineText: string, character: number): string | null {
	if (lineText.length === 0) return null;
	const pos = Math.max(0, Math.min(character, lineText.length - 1));
	const isWord = (ch: string) => /[A-Za-z0-9_]/.test(ch);

	if (!isWord(lineText[pos]) && pos > 0 && isWord(lineText[pos - 1])) {
		return getWordAt(lineText, pos - 1);
	}
	if (!isWord(lineText[pos])) return null;

	let s = pos;
	let e = pos;
	while (s > 0 && isWord(lineText[s - 1])) s--;
	while (e + 1 < lineText.length && isWord(lineText[e + 1])) e++;
	return lineText.slice(s, e + 1);
}

function findFunctionSignature(text: string, name: string): string | null {
	const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
	const re = new RegExp(`\\b(?:func|function|fn|fun)\\s+${escaped}\\s*\\(([^)]*)\\)\\s*(?:(?:->|:)\\s*([A-Za-z_][A-Za-z0-9_\\.<>,\[\]]*))?`, 'm');
	const m = text.match(re);
	if (!m) return null;
	const params = (m[1] ?? '').trim();
	const ret = (m[2] ?? 'Dynamic').trim();
	return `${name}(${params}): ${ret}`;
}

function normalizeWorkspaceRoot(params: InitializeParams): string | null {
	if (params.workspaceFolders && params.workspaceFolders.length > 0) {
		const uri = params.workspaceFolders[0].uri;
		if (uri.startsWith('file://')) {
			return fileURLToPath(uri);
		}
	}
	if (params.rootUri && params.rootUri.startsWith('file://')) {
		return fileURLToPath(params.rootUri);
	}
	if (params.rootPath) {
		return params.rootPath;
	}
	return null;
}

function buildModuleIndex(): void {
	if (moduleIndexReady) return;
	moduleIndexReady = true;
	knownModules = new Set();
	knownModuleFiles = new Map();
	nativeMembersCache = new Map();
	discoveredClassPaths = [];
	projectIndexCache.clear();

	if (!workspaceRoot) return;

	updateProjectIndexIfNeeded(workspaceRoot, true);
}

function dedupePaths(paths: string[]): string[] {
	const seen = new Set<string>();
	const out: string[] = [];
	for (const p of paths) {
		const norm = path.normalize(p);
		if (seen.has(norm)) continue;
		seen.add(norm);
		out.push(norm);
	}
	return out;
}

function discoverLimeClassPaths(root: string): string[] {
	const out: string[] = [];
	if (!commandAvailable('lime')) return out;

	try {
		const raw = execSync('lime display hl', {
			cwd: root,
			encoding: 'utf8',
			stdio: ['ignore', 'pipe', 'ignore'],
		});
		const parts = raw.split(/\s+/).filter(Boolean);
		for (let i = 0; i < parts.length - 1; i++) {
			if (parts[i] === '-cp') {
				const resolved = path.resolve(root, parts[i + 1]);
				out.push(resolved);
			}
		}
	} catch {
		// Optional integration: ignore failures and keep local scanning.
	}

	return out;
}

function commandAvailable(name: string): boolean {
	try {
		if (process.platform === 'win32') {
			execSync(`where ${name}`, { stdio: 'ignore' });
		} else {
			execSync(`which ${name}`, { stdio: 'ignore' });
		}
		return true;
	} catch {
		return false;
	}
}

function scanHxModules(basePath: string, currentPath: string, sink: Set<string>, files: Map<string, string>): void {
	if (!fs.existsSync(currentPath)) return;
	let entries: fs.Dirent[];
	try {
		entries = fs.readdirSync(currentPath, { withFileTypes: true });
	} catch {
		return;
	}

	for (const entry of entries) {
		const full = path.join(currentPath, entry.name);
		if (entry.isDirectory()) {
			scanHxModules(basePath, full, sink, files);
			continue;
		}
		if (!entry.isFile() || !entry.name.endsWith('.hx')) continue;

		const rel = path.relative(basePath, full).replace(/\\/g, '/');
		const module = rel.substring(0, rel.length - 3).replace(/\//g, '.');
		if (module) {
			sink.add(module);
			if (!files.has(module)) files.set(module, full);
		}
	}
}

function extractImports(text: string): ImportStmt[] {
	const out: ImportStmt[] = [];
	const lines = text.split(/\r?\n/);
	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		const m = line.match(IMPORT_LINE_RE);
		if (!m) continue;
		const mod = m[1] || m[2] || m[3];
		if (!mod) continue;
		out.push({ module: mod, line: i + 1, col: line.indexOf(mod) + 1 });
	}
	return out;
}

function stripImportLines(text: string): string {
	const lines = text.split(/\r?\n/);
	for (let i = 0; i < lines.length; i++) {
		if (IMPORT_LINE_RE.test(lines[i])) {
			lines[i] = '';
		}
	}
	return lines.join('\n');
}

function isImportResolvable(moduleName: string): boolean {
	if (moduleName.startsWith('haxe.') || moduleName === 'String' || moduleName === 'Math' || moduleName === 'Std') {
		return true;
	}
	if (knownModules.has(moduleName)) return true;
	const short = moduleName.split('.').pop();
	if (!short) return false;

	for (const m of knownModules) {
		if (m.endsWith(`.${short}`) || m === short) return true;
	}
	return false;
}

function findNativeMethodDiagnostics(document: TextDocument): Diagnostic[] {
	const text = document.getText();
	const diagnostics: Diagnostic[] = [];

	const scans: Array<{ regex: RegExp; known: Set<string>; kind: string }> = [
		{ regex: /\b\d+(?:\.\d+)?\.(\w+)\s*\(/g, known: KNOWN_NUMBER_METHODS, kind: 'Number' },
		{ regex: /"(?:[^"\\]|\\.)*"\.(\w+)\s*\(/g, known: KNOWN_STRING_METHODS, kind: 'String' },
		{ regex: /'(?:[^'\\]|\\.)*'\.(\w+)\s*\(/g, known: KNOWN_STRING_METHODS, kind: 'String' },
		{ regex: /\[[^\]\n]*\]\.(\w+)\s*\(/g, known: KNOWN_ARRAY_METHODS, kind: 'Array' },
	];

	for (const s of scans) {
		s.regex.lastIndex = 0;
		let m: RegExpExecArray | null;
		while ((m = s.regex.exec(text)) !== null) {
			const method = m[1];
			if (s.known.has(method)) continue;

			const full = m[0];
			const methodOffset = m.index + full.lastIndexOf('.' + method + '(') + 1;
			const start = document.positionAt(methodOffset);
			const end = document.positionAt(methodOffset + method.length);
			diagnostics.push({
				severity: DiagnosticSeverity.Warning,
				range: { start, end },
				message: `Unknown ${s.kind} native method '${method}'`,
				source: 'nxscript',
			});
		}
	}

	return diagnostics;
}

function runNativeHaxeImportDiagnostics(document: TextDocument, imports: ImportStmt[]): Diagnostic[] | null {
	if (imports.length === 0) return [];
	if (!commandAvailable('haxe')) return null;

	const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'nxscript-lsp-'));
	const probePath = path.join(tmpRoot, 'NxImportProbe.hx');

	try {
		const importLines = imports.map(i => `import ${i.module};`).join('\n');
		const probe = `${importLines}\nclass NxImportProbe { static function main() {} }\n`;
		fs.writeFileSync(probePath, probe, 'utf8');

		const args: string[] = ['--no-output', '-main', 'NxImportProbe', '-cp', tmpRoot];
		for (const cp of discoveredClassPaths) {
			if (fs.existsSync(cp)) {
				args.push('-cp', cp);
			}
		}

		try {
			execSync(`haxe ${args.map(quoteArg).join(' ')}`, {
				cwd: workspaceRoot ?? undefined,
				encoding: 'utf8',
				stdio: ['ignore', 'pipe', 'pipe'],
			});
			return [];
		} catch (err: unknown) {
			const stderr = (err as { stderr?: string }).stderr ?? '';
			const stdout = (err as { stdout?: string }).stdout ?? '';
			const output = String(stderr || stdout || '');
			return parseNativeHaxeOutput(document, imports, output);
		}
	} finally {
		try {
			fs.rmSync(tmpRoot, { recursive: true, force: true });
		} catch {
			// ignore cleanup errors
		}
	}
}

function parseNativeHaxeOutput(document: TextDocument, imports: ImportStmt[], output: string): Diagnostic[] {
	const diagnostics: Diagnostic[] = [];
	const lines = output.split(/\r?\n/);
	const re = /NxImportProbe\.hx:(\d+): characters (\d+)-(\d+) : (.*)$/;

	for (const line of lines) {
		const m = line.match(re);
		if (!m) continue;

		const probeLine = parseInt(m[1], 10);
		const msg = m[4] || 'Haxe error';
		const importIdx = probeLine - 1;
		if (importIdx < 0 || importIdx >= imports.length) continue;
		const imp = imports[importIdx];

		const range = {
			start: { line: imp.line - 1, character: imp.col - 1 },
			end: { line: imp.line - 1, character: imp.col - 1 + imp.module.length },
		};

		let message = msg;
		if (/Type not found|Module not found|Unknown identifier/i.test(msg)) {
			message = `Cant find module that package name: ${imp.module}`;
		}

		diagnostics.push({
			severity: DiagnosticSeverity.Warning,
			range,
			message,
			source: 'nxscript(haxe)',
		});
	}

	return diagnostics;
}

function quoteArg(v: string): string {
	if (/^[a-zA-Z0-9_./\\:-]+$/.test(v)) return v;
	return `"${v.replace(/"/g, '\\"')}"`;
}

documents.listen(connection);
connection.listen();
