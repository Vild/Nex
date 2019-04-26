module app;

import std.stdio;

void dfunc();
extern (C) void cfunc();
extern (C++) void cfunc();

void main() {
	writeln("Edit source/app.d to start your project.");
}
