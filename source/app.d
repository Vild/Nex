module app;

import nex.parse;
import nex.build;

void main(string[] args) {
	import std.path : dirName, absolutePath,buildNormalizedPath;

	string file = args.length > 1 ? args[1] : "nex.sdl";
	string prefix = file.absolutePath.buildNormalizedPath.dirName;
	BuildEnvironment be = new BuildEnvironment(prefix);
	be.addBuildFile(file);
	//be.exportDotFile("nex-output.dot");
	be.resolveVariables();
	//be.exportDotFile("nex-output-vars.dot");
	be.resolveWildcards();
	//be.exportDotFile("nex-output-wildcards.dot");

	Build b = new Build(prefix, be);
	b.constructionBuildDirections();
	b.save();
	b.build();
}
