module nex.build;

import nex.parse;

import sdlang;
import std.datetime;

struct BuildTask {
	string command;
	string[] dependencies;
	bool build;
}

struct InfoDatabase {
	struct FileInfo {
		SysTime lastModified;
	}
	FileInfo[string] fileInfo;

	void save() {

	}
}

class Build {
	BuildEnvironment be;
	InfoDatabase db;
	this(BuildEnvironment be) { this.be = be; }


	void build() {

	}
private:

	void _pruneTree() {}
}