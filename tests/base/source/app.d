module app;

import std.stdio;

void dfunc();
extern (C) void cfunc();
extern (C++) void cppfunc();

void main() {
	dfunc();
	cfunc();
	cppfunc();
}
