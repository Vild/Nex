module nex.parse;

import sdlang.ast;
import sdlang.token;
import sdlang.parser;

struct Variable {
	string name;
	Value[] value;
}

struct Processor {
	string name;
	string[] commands;
}

struct Target {
	string name;

	struct Paths {
		string prefix;
		string[] paths;
	}

	Paths[] inputPaths;

	struct InputPath {
		size_t pathsIdx;
		size_t pathsIdx2;
		string path;
	}

	InputPath[] processesInputPaths;
	string[] inputTargets;

	string[] outputs;
	string processor;

	Variable[string] exportVariables;
}

struct Project {
	string name;

	Variable[string] variables;
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
	string prefix;
	Project[string] projects;
	string[] build;

	this(string prefix) { this.prefix = prefix; }

	BuildEnvironment addBuildFile(string file) {
		Tag t = parseFile(file);
		//t.print;
		foreach (Tag.NamespaceAccess na; t.namespaces) {
			switch (na.name) {
			default:
				foreach (Tag tt; na.tags) {
					switch (tt.name) {
					default:
						assert(0, "Unknown tag when parsing buildfile: " ~ tt.toDebugString);
					case "build":
						import std.stdio;

						writeln("Will build: ", tt.expectValue!string());
						build ~= tt.expectValue!string();
						break;
					}
				}
				break;
			case "project":
				foreach (Tag proj; na.tags) {
					auto p = _parseProject(proj);
					projects[p.name] = p;
				}
				break;
			}
		}

		return this;
	}

	void resolveWildcards() {
		foreach (ref Project p; projects) {
			foreach (ref Target t; p.targets) {
				import std.array : appender;

				auto newPaths = appender!(Target.InputPath[]);

				foreach (idx, ref Target.Paths path; t.inputPaths)
					foreach (idx2, ref pp; path.paths) {
						import std.file : dirEntries, SpanMode;
						import std.algorithm : map, each;
						import std.path : buildPath;

						dirEntries(buildPath(prefix, path.prefix), pp, SpanMode.depth).map!"a.name"
							.each!(x => newPaths ~= Target.InputPath(idx, idx2, x));
					}

				t.processesInputPaths = newPaths.data;
			}
		}
	}

	void exportDotFile(string filePath) {
		import std.stdio : File;

		File f = File(filePath, "w");
		scope (exit)
			f.close();

		f.writeln("digraph Nex {");
		size_t index;
		foreach (_, ref Project p; projects) {
			f.writeln("\tsubgraph cluster_project_", p.name, "{");
			f.writeln("\t\tlabel=\"Project: ", p.name, "\";");
			f.writeln("\t\tstyle=filled;");
			f.writeln("\t\tcolor=lightseagreen;");
			foreach (__, Target t; p.targets) {
				f.writeln("\t\tsubgraph cluster_target_", t.name, "{");
				f.writeln("\t\t\tstyle=filled;");
				f.writeln("\t\t\tcolor=lightblue;");
				f.writeln("\t\t\tlabel=\"Target: ", t.name, "\";");
				f.writeln("\t\t\ttarget_", p.name, "_", t.name, "[label=\"Target: ", t.name, "\",style=filled,color=lightgrey];");

				foreach (idx, Target.Paths paths; t.inputPaths)
					foreach (idx2, string path; paths.paths) {
						f.writeln("\t\t\tsubgraph cluster_path_", p.name, "_", t.name, "_", idx, "_", idx2, "{");
						f.writeln("\t\t\t\tstyle=filled;");
						f.writeln("\t\t\t\tcolor=white;");
						f.writeln("\t\t\t\tlabel=\"Path: ", paths.prefix, path,"\";");
						//f.writeln("\t\t\t\"path_", p.name, "_", t.name, "_", paths.prefix, "_", path, "\" -> target_", p.name, "_", t.name, ";");
						foreach (idx3, Target.InputPath path2; t.processesInputPaths) {
							if (idx != path2.pathsIdx || idx2 != path2.pathsIdx2)
								continue;
							f.writeln("\t\t\t\t\"path_", p.name, "_", t.name, "_", idx3, "\"[label=\"Path: ",
									path2.path, "\",style=filled,color=grey];");
							f.writeln("\t\t\t\t\"path_", p.name, "_", t.name, "_", idx3, "\" -> target_", p.name, "_", t.name, ";");
						}
						if (!t.processesInputPaths.length)
						f.writeln("cluster_path_", p.name, "_", t.name, "_", idx, "_", idx2,"_empty[label=\"NOTHING FOUND\",style=filled,color=red];");
						f.writeln("\t\t\t}");
					}
				foreach (string depTar; t.inputTargets)
					f.writeln("\t\t\ttarget_", p.name, "_", depTar, " -> target_", p.name, "_", t.name, ";");
				f.writeln("\t\t}");
			}

			f.writeln("\t}");
			foreach (string dep; p.dependencies)
				f.writeln("\ttarget_", dep, "_", dep, " -> target_", p.name, "_", p.name, ";");
		}

		f.writeln("\tsubgraph cluster__will_build {");
		foreach (string b; build) {
			f.writeln("\t\tbuild_", b, "[label=\"Build: ", b, "\",style=filled,color=magenta];");
			f.writeln("\t\tbuild_", b, " -> target_", b, "_", b, ";");
		}

		f.writeln("\t}");

		f.writeln("}");
	}

private:
	Project _parseProject(Tag t) {
		import std.stdio;

		Project p;
		p.name = t.name;
		foreach (Tag.NamespaceAccess na; t.namespaces) {
			switch (na.name) {
			default:
				foreach (Tag tt; na.tags) {
					switch (tt.name) {
					default:
						assert(0, "Unknown tag when parsing project: " ~ tt.toDebugString);
					case "dependency":
						p.dependencies ~= tt.expectValue!string();
						break;
					}
				}
				break;
			case "var":
				foreach (Tag tt; na.tags)
					p.variables[tt.name] = Variable(tt.name, tt.values);
				break;
			case "processor":
				foreach (Tag tt; na.tags) {
					Processor processor = _parseProcessor(tt);
					p.processors[processor.name] = processor;
				}
				break;
			case "target":
				foreach (Tag tt; na.tags) {
					Target target = _parseTarget(tt);
					p.targets[target.name] = target;
				}
				break;
			}
		}
		return p;
	}

	Processor _parseProcessor(Tag t) {
		Processor processor;
		processor.name = t.name;
		foreach (Value v; t.values)
			processor.commands ~= v.get!string;

		foreach (Tag tt; t.tags)
			foreach (Value v; tt.values)
				processor.commands ~= v.get!string;
		return processor;
	}

	Target _parseTarget(Tag t) {
		Target target;

		target.name = t.name;
		t.expectTag("input");
		t.expectTag("output");
		t.expectTag("processor");

		foreach (Tag child; t.tags) {
			switch (child.name) {
			default:
				assert(0, "Unknown tag when parsing target: " ~ child.toDebugString());
			case "input":
				Target.Paths paths = Target.Paths(child.getAttribute!string("prefix", ""));
				foreach (Value v; child.values)
					paths.paths ~= v.get!string;

				foreach (Attribute attr; child.attributes) {
					if (attr.name == "prefix")
						continue;
					assert(attr.name == "target", attr.name ~ " is not \"target\"");
					target.inputTargets ~= attr.value.get!string;
				}

				target.inputPaths ~= paths;
				break;
			case "output":
				foreach (Value v; child.values)
					target.outputs ~= v.get!string;
				break;
			case "processor":
				target.processor = child.getValue!string();
				break;

			case "export":
				foreach (Tag.NamespaceAccess na; child.namespaces) {
					switch (na.name) {
					default:
						foreach (Tag tt; na.tags) {
							switch (tt.name) {
							default:
								assert(0, "Unknown tag when parsing export block inside target: " ~ tt.toDebugString);
							}
						}
						break;
					case "var":
						foreach (Tag tt; na.tags)
							target.exportVariables[tt.name] = Variable(tt.name, tt.values);
						break;
					}
					break;
				}
			}
		}
		return target;
	}
}


