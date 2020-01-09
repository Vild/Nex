module nex.parse;

import std.array;
import std.stdio;

import sdlang.ast;
import sdlang.token;
import sdlang.parser;

class VariableNotFound : Exception {
public:
	string var;
	string missing;
	this(string var, string missing, string file = __FILE__, size_t line = __LINE__) {
		super("Variable '" ~ missing ~ "' missing, from " ~ var, null, file, line);
		this.var = var;
		this.missing = missing;
	}
}

struct Variable {
	string name;
	string value;
	bool removeOld;
}

void resolve(ref Variable var, ref Variables vars) {
	return resolve(var.name, var.value, vars);
}

void resolve(string name, ref string value, ref Variables vars) {
	import std.algorithm.iteration : splitter, joiner, map;
	import std.conv : to;

	bool isVar;
	string output;
	bool changed;

	foreach (s; value.splitter("@")) {
		scope (exit)
			isVar = !isVar;
		if (!isVar) {
			output ~= s;
			continue;
		}

		if (!(s in vars))
			throw new VariableNotFound(name, s);
		changed = true;
		output ~= vars[s].value;
	}
	if (changed)
		resolve(name, output, vars);
	value = output;
}

struct Variables {
	Variable[string /* Name */ ] vars;
	void merge(const ref Variables other) {
		foreach (ref var; other) {
			auto v = var.name in vars;
			if (v && !var.removeOld && var.value.length)
				v.value ~= " " ~ var.value;
			else
				vars[var.name] = var;
			vars[var.name].removeOld = false;
		}
	}

	alias vars this;
}

struct OutputProcessor {
	string description;
	string extensions;
	string output;
	string[] commands;

	bool multipleFiles = false;
}

struct Template {
	string name;
	Template* extends;

	Variables vars;

	If[] ifStatements;

	OutputProcessor[] outputProcessors;
}

struct If {
	// Conditions, all need to be true
	string[] exist;
	string[] defined;
	string[string] equals;

	Variables thenPath;
	Variables elsePath;
}

struct Target {
	string name;
	Template* template_;

	Variables vars;

	If[] ifStatements;

	string[] dependencies;
	string[] sources;
	string output;
	Variables exports;
}

class BuildEnvironment {
	string prefix;
	Variables vars;
	Template[string] templates;
	Target[string] targets;
	string[] build;

	this(string prefix) {
		import std.process : environment;

		this.prefix = prefix;
		templates[""] = Template("DEFAULT", null);
		foreach (key, value; environment.toAA)
			vars["ENV:" ~ key] = Variable("ENV:" ~ key, value);
	}

	BuildEnvironment addBuildFile(string file) {
		import std.stdio;

		Tag root = parseFile(file);
		//root.print;

		//writeln("Root: ", root.toDebugString);

		foreach (Tag t; root.all.tags) {
			switch (t.getFullName.toString) {
			default:
				if (t.getFullName().namespace == "")
					assert(0, "Unknown tag when parsing buildfile: " ~ t.toDebugString);
				_parseVariable(t, vars);
				break;
			case "target":
				_parseTarget(t);
				break;
			case "template":
				_parseTemplate(t);
				break;
			case "build":
				build ~= t.expectValue!string();
				break;
			}
		}
		return this;
	}

	void resolveVariables() {
		bool[Template* ] visitedTemplate;
		bool[Target* ] visitedTarget;

		void visitIf(ref If if_, ref Variables vars) {
			foreach (ref string e; if_.exist)
				resolve("If-exist", e, vars);

			bool doIt = true;

			if (doIt)
				foreach (e; if_.exist) {
					import std.file : exists;

					doIt = exists(e);
					if (!doIt)
						break;
				}
			if (doIt)
				foreach (def; if_.defined) {
					doIt = !!(def in vars);
					if (!doIt)
						break;
				}
			if (doIt)
				foreach (key, value; if_.equals) {
					assert(key in vars, "Variable '" ~ key ~ " is undefined'");
					doIt = vars[key].value == value;
					if (!doIt)
						break;
				}

			vars.merge(doIt ? if_.thenPath : if_.elsePath);
		}

		void visitTemplate(ref Template t) {
			if (&t in visitedTemplate)
				return;
			visitedTemplate[&t] = true;
			if (t.extends)
				visitTemplate(*t.extends);
			else
				t.vars.merge(vars);

			if (t.extends)
				t.vars.merge(t.extends.vars);

			foreach (ref If if_; t.ifStatements)
				visitIf(if_, t.vars);

			foreach (ref Variable var; t.vars)
				var.resolve(t.vars);
		}

		void visitTarget(ref Target t) {
			if (&t in visitedTarget)
				return;
			visitedTarget[&t] = true;
			visitTemplate(*t.template_);
			foreach (string dep; t.dependencies)
				visitTarget(targets[dep]);

			t.vars.merge(t.template_.vars);

			foreach (ref Variable var; t.vars)
				var.resolve(t.vars);

			foreach (ref If if_; t.ifStatements)
				visitIf(if_, t.vars);

			foreach (ref string src; t.sources)
				resolve("source", src, t.vars);

			resolve("output", t.output, t.vars);

			foreach (ref Variable v; t.exports)
				resolve("exports-" ~ v.name, v.value, t.vars);
		}

		foreach (ref Variable var; vars)
			var.resolve(vars);

		foreach (ref Target t; targets)
			visitTarget(t);
	}

	void resolveWildcards() {
		import std.path : absolutePath, relativePath;

		foreach (ref Target t; targets) {
			import std.path : buildPath, expandTilde;
			import std.array : appender;

			auto newPaths = appender!(string[]);

			foreach (idx, string path; t.sources) {
				import std.file : dirEntries, SpanMode;
				import std.algorithm : map, each, filter;

				path = expandTilde(path);
				if (path[0] != '/')
					path = buildPath(prefix, path);

				dirEntries(path.absolutePath, SpanMode.depth).filter!(a => a.isFile)
					.map!"a.name"
					.each!(x => newPaths ~= x.relativePath(prefix));
			}

			t.sources = newPaths.data;

			t.output = expandTilde(t.output);
			if (t.output[0] != '/')
				t.output = buildPath(prefix, t.output);
			t.output = t.output.relativePath(prefix);
		}
	}

	void exportDotFile(string filePath) {
		import std.stdio : File;

		File f = File(filePath, "w");
		scope (exit)
			f.close();

		f.writeln("digraph Nex {");
		f.writeln("\tgraph[rankdir=LR, overlap=false, splines=true];");
		f.writeln("\tcompound=true;");

		f.writef("\tglobal_var[shape=record,color=red,label=\"Global Vars:");
		foreach (const ref Variable v; vars)
			f.writef("|%s: '%s'", v.name, v.value);
		f.writeln("\"];");

		bool[Template* ] visitedTemplate;
		bool[Target* ] visitedTarget;

		void visitTemplate(const ref Template t) {
			if (&t in visitedTemplate)
				return;
			visitedTemplate[&t] = true;
			if (t.extends)
				visitTemplate(*t.extends);
			f.writefln("\tsubgraph clustertemplate_%s {", t.name);
			f.writefln("\t\tlabel=\"%s\";", t.name);
			f.writeln("\t\tstyle=filled;");
			f.writeln("\t\tcolor=lightseagreen;");

			f.writefln("\t\ttemplate_%s[label=\"Template: %s\"];", t.name, t.name);
			if (t.extends)
				f.writefln("\t\ttemplate_%s -> template_%s;", t.extends.name, t.name);

			f.writef("\ttemplate_%s_var[shape=record,color=red,label=\"Vars:", t.name);
			foreach (const ref Variable v; t.vars)
				f.writef("|%s: '%s'", v.name, v.value);
			f.writeln("\"];");

			f.writefln("\t}");
		}

		void visitTarget(const ref Target t) {
			if (&t in visitedTarget)
				return;
			visitedTarget[&t] = true;
			visitTemplate(*t.template_);
			foreach (string dep; t.dependencies)
				visitTarget(targets[dep]);

			f.writefln("\tsubgraph clustertarget_%s {", t.name);
			f.writefln("\t\tlabel=\"%s\";", t.name.length ? t.name : "<DEFAULT>");
			f.writeln("\t\tstyle=filled;");
			f.writeln("\t\tcolor=lightgreen;");

			f.writefln("\t\ttarget_%s[label=\"%s\"];", t.name, t.output);

			f.writefln("\t\ttemplate_%s -> target_%s;", t.template_.name, t.name);

			foreach (string dep; t.dependencies)
				f.writefln("\t\ttarget_%s -> target_%s;", dep, t.name);

			f.writef("\ttarget_%s_source[shape=record,color=red,label=\"Sources:", t.name);
			foreach (string src; t.sources)
				f.writef("|%s", src);
			f.writeln("\"];");
			f.writefln("\t\ttarget_%s_source -> target_%s;", t.name, t.name);

			f.writef("\ttarget_%s_var[shape=record,color=red,label=\"Vars:", t.name);
			foreach (const ref Variable v; t.vars)
				f.writef("|%s: '%s'", v.name, v.value);
			f.writeln("\"];");

			f.writef("\ttarget_%s_exports[shape=record,color=yellow,label=\"Exports:", t.name);
			foreach (const ref Variable v; t.exports)
				f.writef("|%s: '%s'", v.name, v.value);
			f.writeln("\"];");

			f.writefln("\t}");
		}

		foreach (string b; build) {
			f.writefln("\tbuild_%s[label=\"%s\",fontsize=32,style=filled,color=gold];", b, b);
			visitTarget(targets[b]);
			f.writefln("\tbuild_%s -> target_%s;", b, b);
		}

		f.writeln("}");
	}

private:

	// TODO: merge everythings with same name

	void _parseVariable(Tag t, ref Variables vars) {
		assert(t.values.length < 2, "Variables only accepts zero arguments (Clears value), or one string argument (Append value)!");
		auto name = t.getFullName.toString;
		Variable* var = name in vars;
		if (!var) {
			vars[name] = Variable(name);
			var = &vars[name];
		}
		if (t.values.length) {
			var.value ~= (var.value.length ? " " : "") ~ t.getValue!string;
		} else {
			var.value = null;
			var.removeOld = true;
		}
	}

	void _parseTemplate(Tag tag) {
		//writeln("Template: ", tag.toDebugString);
		string name = tag.getValue!string("");
		Template* template_ = name in templates;
		if (!template_) {
			templates[name] = Template(name);
			template_ = &templates[name];
			string parent = tag.getAttribute!string("extends", "");
			template_.extends = parent in templates;
			assert(template_.extends, "Template " ~ tag.getFullName.toString ~ " does extends a non-defined template " ~ parent);
		} //TODO: insert more warnings here, if uses extends later.

		Tag lastTag;
		foreach (Tag t; tag.all.tags) {
			//writeln("\tt: ", t.toDebugString);
			scope (exit)
				lastTag = t;
			switch (t.getFullName.toString) {
			case "output_processor":
				t.expectAttribute!string("description");
				t.expectAttribute!string("extensions");
				t.expectAttribute!string("output");
				OutputProcessor op;
				op.description = t.getAttribute!string("description");
				op.extensions = t.getAttribute!string("extensions");
				op.output = t.getAttribute!string("output");
				if (auto cmd = t.getAttribute!string("command", null))
					op.commands ~= cmd;
				else
					foreach (Tag l; t.all.tags)
						op.commands ~= l.getValue!string();
				op.multipleFiles = t.getAttribute!bool("multiple_files", false);
				template_.outputProcessors ~= op;
				break;
			case "if":
				template_.ifStatements ~= _parseIf(t);
				break;
			case "else":
				assert(lastTag && lastTag.getFullName.toString == "if", "There needs to be a 'if' before 'else'");
				_parseElse(t, template_.ifStatements[$ - 1]);
				break;
			default:
				if (t.getFullName().namespace == "")
					assert(0, "Unknown tag when parsing 'template': " ~ t.toDebugString);
				_parseVariable(t, template_.vars);
				break;
			}
		}
	}

	void _parseTarget(Tag tag) {
		//writeln("Target: ", tag.toDebugString);
		string name = tag.getValue!string("");
		Target* target = name in targets;
		if (!target) {
			targets[name] = Target(name);
			target = &targets[name];
			string parent = tag.getAttribute!string("template", "");
			target.template_ = parent in templates;
			assert(target.template_, "Target " ~ tag.getFullName.toString ~ " uses a non-defined template " ~ parent);
		} //TODO: insert more warnings here, if uses templates later.

		tag.expectTag("source");
		tag.expectTag("output");
		Tag lastTag;
		foreach (Tag t; tag.all.tags) {
			//writeln("\tt: ", t.toDebugString);
			scope (exit)
				lastTag = t;
			switch (t.getFullName.toString) {
			case "source":
				foreach (Value val; t.values)
					if (auto str = val.peek!string)
						target.sources ~= *str;
					else
						assert(0, "Values to 'source' must be strings!");
				break;
			case "output":
				t.expectValue!string();
				assert(t.values.length == 1);
				target.output = t.getValue!string();
				Variable output = Variable("output", target.output);
				target.vars[output.name] = output;
				break;
			case "export":
				foreach (Attribute attr; t.all.attributes) {
					Variable var = Variable(attr.getFullName.toString, attr.value.get!string);
					target.exports[var.name] = var;
				}
				break;
			case "if":
				target.ifStatements ~= _parseIf(t);
				break;
			case "else":
				assert(lastTag && lastTag.getFullName.toString == "if", "There needs to be a 'if' before 'else'");
				_parseElse(t, target.ifStatements[$ - 1]);
				break;
			case "dependency":
				foreach (Value val; t.values)
					if (auto str = val.peek!string)
						target.dependencies ~= *str;
					else
						assert(0, "Values to 'dependency' must be strings!");
				break;
			default:
				if (t.getFullName().namespace == "")
					assert(0, "Unknown tag when parsing 'target': " ~ t.toDebugString);
				_parseVariable(t, target.vars);
				break;
			}
		}
	}

	If _parseIf(Tag tag) {
		If if_;
		//writeln("If: ", tag.toDebugString);
		foreach (ref Attribute attr; tag.all.attributes) {
			if (attr.getFullName.toString == "exist")
				if_.exist ~= attr.value.get!string;
			else if (attr.getFullName.toString == "defined")
				if_.defined ~= attr.value.get!string;
			else if (attr.getFullName.namespace.length)
				if_.equals[attr.getFullName.toString] = attr.value.get!string;
			else
				assert(0, "Unknown 'if' instruction: " ~ attr.toSDLString);
		}

		foreach (Tag t; tag.all.tags) {
			//writeln("\tt: ", t.toDebugString);
			switch (t.getFullName.toString) {
			default:
				if (t.getFullName().namespace == "")
					assert(0, "Unknown tag when parsing 'template': " ~ t.toDebugString);
				_parseVariable(t, if_.thenPath);
				break;
			}
		}
		return if_;
	}

	void _parseElse(Tag tag, ref If if_) {
		foreach (Tag t; tag.all.tags) {
			//writeln("\tt: ", t.toDebugString);
			switch (t.getFullName.toString) {
			default:
				if (t.getFullName().namespace == "")
					assert(0, "Unknown tag when parsing 'template': " ~ t.toDebugString);
				_parseVariable(t, if_.elsePath);
				break;
			}
		}
	}
}
