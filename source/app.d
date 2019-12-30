module app;

import nex.parse;

void main(string[] args) {
	import std.path : dirName;

	string file = args.length > 1 ? args[1] : "tests/base/nex.sdl";
	BuildEnvironment be = new BuildEnvironment(file.dirName);
	be.addBuildFile(file);
	be.resolveWildcards();
	be.exportDotFile("tests_base_nex.dot");
	//ProjectScope ps = t.parse;
	//ps.dot();
}
