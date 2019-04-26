module nex.parse;

import sdlang.ast;
import sdlang.token;
import sdlang.parser;

struct Processor {
	string name;
	string[] commands;
}

struct Target {
	string[] input;
	string[] output;
}

struct Project {
	string name;

	string[string] variables;
	string[] dependencies;
	Processor[string] processors;
	Target[string] targets;
}

void print(Tag t) {
	import std.stdio;
	import std.file;
	import std.range;

	size_t indent = -1;
	void _() {
		write(' '.repeat(indent * 2));
	}

	void print(Tag t) {
		indent++;
		scope (exit)
			indent--;
		_;
		write(t.getFullName);

		if (t.values) {
			write(" [");
			foreach (size_t idx, Value val; t.values) {
				if (idx)
					write(", ");
				write('"', val, '"');
			}
			write("]");
		}

		foreach (Attribute attr; t.all.attributes)
			write(" ", attr.getFullName, "=\"", attr.value, '"');

		if (t.all.tags.length) {
			writeln(" {");
			foreach (Tag child; t.all.tags)
				print(child);
			_;
			write("}");
		}
		writeln;
	}

	print(t);
}

class BuildEnvironment {
	Project[string] projects;

	BuildEnvironment addBuildFile(string file) {
		Tag t = parseFile("tests/base/nex.sdl");
		//t.print;
		foreach (Tag.NamespaceAccess na; t.namespaces){
			import std.stdio;
			writeln(na);
		}

		return this;
	}

}
