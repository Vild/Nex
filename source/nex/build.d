module nex.build;

import nex.parse;

import sdlang;
import std.datetime;

struct BuildTask {
	string description;
	string output;
	string command;
	string[] dependencies;
	string[string] env;
}

struct BuildCommand {
	string directory;
	string file;
	string command;
	string output;
}

class Build {
	string prefix;
	BuildEnvironment be;
	BuildTask[] tasks;
	BuildCommand[] buildCommands;

	this(string prefix, BuildEnvironment be) {
		this.prefix = prefix;
		this.be = be;
	}

	void save() {
		import std.file : write;
		import std.json;

		JSONValue[] cmds;
		foreach (ref BuildCommand cmd; buildCommands)
			cmds ~= JSONValue(["directory": cmd.directory, "file": cmd.file, "command": cmd.command]);
		JSONValue j = cmds;

		write("compile_commands.json", j.toPrettyString());
	}

	void constructionBuildDirections_OLD() {
		import std.process : environment;
		import std.algorithm : map;
		import std.format : format;

		bool[Target* ] visitedTarget;

		void visitTarget(ref Target t) {
			if (&t in visitedTarget)
				return;
			visitedTarget[&t] = true;

			foreach (string dep; t.dependencies)
				visitTarget(be.targets[dep]);

			Processor*[] matches;

			void visitTemplate(ref Template template_) {
				import std.path : globMatch, baseName;

				bool found;

				foreach (ref Processor op; template_.processors)
					if (globMatch(t.output.baseName, op.output)) {
						found = true;
						matches ~= &op;
					}

				if (!found && template_.extends)
					visitTemplate(*template_.extends);
			}

			visitTemplate(*t.template_);

			assert(matches.length > 0, "Could not find any processor that matches '" ~ t.output ~ "'");
			assert(matches.length == 1, "'" ~ t.output ~ "' matches multiple processors: " ~ format("%s", matches.map!"*a"));

			Variables vars;
			vars.merge(t.vars);

			{
				bool[Target* ] visitedDependency;
				void visitDependency(ref Target dep) {
					if (&dep in visitedDependency)
						return;
					visitedDependency[&dep] = true;
					vars.merge(dep.exports);
					foreach (string d; dep.dependencies)
						vars.merge(be.targets[d].exports);
				}

				foreach (string dep; t.dependencies)
					visitDependency(be.targets[dep]);
			}

			import std.array : join;
			import std.conv : to;
			import std.algorithm : filter, startsWith;
			import std.path : baseName, globMatch;

			/*size_t[] sources;
			foreach (idx src; t.sources) {
				if (globMatch(a.baseName, matches[0].input))
					sources ~= idx;
			}*/

			Variable in_ = Variable("IN", t.sources.join(" ").to!string);
			Variable out_ = Variable("OUT", t.output);
			vars[in_.name] = in_;
			vars[out_.name] = out_;

			string cmd = matches[0].command;
			resolve("Command", cmd, vars);
			foreach (src; t.sources)
				buildCommands ~= BuildCommand(prefix, src, cmd, t.output);
			string description = matches[0].description;
			resolve("Description", description, vars);

			string[string] env;
			foreach (Variable var; vars.byValue.filter!`a.name.startsWith("ENV:")`)
				env[var.name["ENV:".length .. $]] = var.value;
			tasks ~= BuildTask(description, t.output, cmd, [], env);
		}

		foreach (string build; be.build)
			visitTarget(be.targets[build]);
	}

	void constructionBuildDirections() {
		_insertFiles();
		_singleDAG();
		_multiDAG();
	}

	void build() {
		foreach (idx, ref BuildTask bt; tasks) {
			import std.process : pipeProcess, Redirect, wait, Config;
			import std.stdio;
			import std.range : repeat;

			string commands = "set -euo pipefail";

			commands ~= " && (" ~ bt.command ~ ")";

			enum size_t width = 64;
			size_t procent = (idx + 1) * 100 / tasks.length;
			immutable(dchar[]) step = [' ', '▏', '▎', '▍', '▋', '▊', '▉', '█'];
			size_t filled = cast(size_t)(width * (procent / 100.0) * step.length);

			long fullFilled = cast(long)(filled) / step.length;
			if (fullFilled < 0)
				fullFilled = 0;
			long empty = width - fullFilled - 1;
			if (empty < 0)
				empty = 0;

			writefln!"\x1b[39;1m[%3d%%] \x1b[40;36;1m%s%s%s\x1b[0m %s"(procent, step[$ - 1].repeat(fullFilled),
					step[filled % step.length].repeat((procent != 100) * 1), step[0].repeat(empty), bt.description);

			//writefln("[%3d%%] %s", procent, bt.description);
			auto p = pipeProcess(["bash", "-c", commands], Redirect.stdin, bt.env, Config.none, prefix);
			wait(p.pid);
		}
	}
	private:

	void _insertFiles() {

	}
	void _singleDAG() {

	}
	void _multiDAG() {

	}
}

struct DAG {
	alias Constructor = void delegate(ref BuildTask[] tasks);
	struct Entry {
		string file;
		Entry*[] dependencies;
		Constructor constructor; // Null if real file
	}
	Entry*[] entries;

	void insertFile(string file) {
		entries ~= new Entry(file);
	}

	void insertPseudoFile(string output, Entry*[] dependencies, Constructor constructor) {
		entries ~= new Entry(output, dependencies, constructor);
	}
}