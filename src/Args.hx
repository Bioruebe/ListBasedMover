//The MIT License (MIT)
//
//Copyright (c) Simn, https://github.com/Simn/hxargs
//
//Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

package;

import haxe.Constraints.Function;
import haxe.macro.Context;
import haxe.macro.Expr;

using haxe.macro.Tools;
using StringTools;

class Args {
	macro static public function generate(definition:Expr, ?interactive:Bool = false, ?usage) {
		var p = Context.currentPos();
		
		var el = switch(definition.expr) {
			case EArrayDecl(el): el;
			case _: Context.error("Command mapping expected", p);
		}

		var unknownArgCallback = macro throw "Unknown command: " + arg;

		var docs = [];
		var cases = [];
		var maxCmdLength = 0;
		
		usage = switch(usage.expr) {
			case EConst(CIdent("null")):
				macro "";
			case _:
				usage;
		}

		function addDoc(e, s, args:Array<FunctionArg>) {
			var e = switch(e.expr) {
				case EParenthesis(e): e;
				case _: e;
			}
			var argString = args.length == 0 ? "" : " " + args.map(function(arg) {
				return arg.opt? '[${arg.name}]': '${arg.name}'; } ).join(" ");
			var cmdString = e.toString().replace('",', " |").replace('"', "") + argString;
			if (cmdString.length > maxCmdLength)
				maxCmdLength = cmdString.length;
			docs.push({
				cmd: cmdString,
				desc: s
			});
		}

		function addCase(cmds:Expr, action) {
			var args = [];
			
			action.expr = switch(action.expr) {
				case EConst(CIdent(f)):
					//var className = Context.getLocalClass().toString();
					var prop = Reflect.getProperty(Main, $v { f } );
					if (prop == null) throw "The property " + $v { f } + " for switch " + f + " does not exist";
						
					var type = Type.typeof(prop);
					var e;
					
					if (type == TBool) {
						e = macro function f() {
							Reflect.setProperty(Main, $v { f }, true);
							Sys.println("Option '" + $v { f } + "' set to true");
						}
					}
					else {
						e = macro function f(value:String) {
							//if (value == null) throw "Not enough arguments: " + __args[__index -1] + " is missing option value";
							
							var val:Dynamic;
							switch($v{type}) {
								case TInt:
									val = Std.parseInt(value);
								case TFloat:
									val = Std.parseFloat(value);
								case _:
									val = value;
							}
							
							Reflect.setProperty(Main, $v { f }, val);
							trace("Option '" + $v { f } + "' set to " + val);
						};
					}
					
					e.expr;
				case _:
					action.expr;
			}

			var fArgs = switch(action.expr) {
				case EFunction(name, func):
					for (i in 0...func.args.length) {
						var e = macro __args[__index + $v{i}];
						var e = switch [func.args[i].type, func.args[i].value] {
							case [null, null]: e;
							case [TPath({ name: "String"}), _] | [null, macro $v{(_:String)}]: e;
							case [TPath({ name: "Int"}), _] | [null, macro $v{(_:Int)}]: macro Std.parseInt($e);
							case [TPath({ name: "Float"}), _] | [null, macro $v{(_:Float)}]: macro Std.parseFloat($e);
							case [TPath({ name: "Bool"}), _] | [null, (macro true) | (macro false)]: macro $e == "true" ? true : false;
							case [t, _]: Context.error('Unsupported argument type: $t', action.pos);
						}
						args.push(e);
					}
					func.args;
				case _: Context.error("Function expected", action.pos);
			}
			cmds = switch(cmds.expr) {
				case EMeta({name: "doc", params: [{expr: EConst(CString(s))}]}, e):
					addDoc(e, s, fArgs);
					e;
				case _: cmds;
			}
			var cmds = switch(cmds.expr) {
				case EArrayDecl(el):
					for (e in el) {
						switch(e.expr) {
							case EConst(CString(_)):
							case _: Context.error("String expected", e.pos);
						}
					}
					el;
				case EConst(CIdent("_")):
					unknownArgCallback = macro $action(arg);
					return;
				case EConst(CString(_)): [cmds];
				case _: Context.error("[commands] or command expected", cmds.pos);
			}

			var e = if(!interactive) macro {
				if (__index + $v{fArgs.length} > __args.length) {
					if (!$a{fArgs.map(function(arg) return macro $v{arg.opt || arg.value != null})}[__args.length - 1])
						throw "Not enough arguments: " +__args[__index -1]+ " expects " + $v{fArgs.length};
				}
				${action}($a{args});
				__index += $v{fArgs.length};
			} else macro {
				var __argInfo = $a{fArgs.map(function(arg) {
					var arg = {
						name: arg.name.replace("_", " "),
						type: arg.type,
						opt: arg.opt || arg.value != null,
						value: $v{arg.value == null ? null : arg.value.getValue()}
					}
					return macro $v{arg};
				})};
				while (__index + $v{fArgs.length} > __args.length) {
					var currentArg = __argInfo[__args.length - 1];
					Sys.print(currentArg.name + (currentArg.value != null ? " (default = " + currentArg.value + ")" : currentArg.opt ? " (optional)" : "") + ": ");
					var s = Sys.stdin().readLine();
					if (s == "") {
						if (currentArg.opt) {
							__args.push(currentArg.value);
						} else {
							Sys.println("Cannot skip non-optional argument " +currentArg.name);
						}
					} else {
						__args.push(s);
					}
				}
				${action}($a{args});
				__index += $v{fArgs.length};
			}
			cases.push({
				values: cmds,
				guard: null,
				expr: e
			});
		}
		
		for (e in el) {
			switch(e.expr) {
				case EBinop(OpArrow, cmds, action):
					addCase(cmds, action);
				case _:
					Context.error("Command mapping expected", e.pos);
			}
		}

		// Create getDoc function and add help command
		var getDoc = macro function getDoc() {
#if sys
			var path:String = Sys.programPath();
			var programName = path.substr(path.lastIndexOf("\\") + 1);
#else
			var programName = "<executableName>";
#end	
			return "\nUsage: " + programName + " [options] " + $usage + "\n\n" + $v{docs.map(function(doc) return doc.cmd.rpad(" ", maxCmdLength + 1) + ": " +doc.desc).join("\n") + "\n"};
		}
		addCase(macro ["-h", "--help"], macro function() { Sys.println(($getDoc())); } );
		
		cases.push({
			values: [macro arg],
			guard: null,
			expr: unknownArgCallback
		});

		var eswitch = {
			expr: ESwitch(macro __args[__index++], cases, null),
			pos: p
		};
		
		return macro {
			getDoc: $getDoc,
			parse: function(__args:Array<Dynamic>) {
				var __index = 0;
				while (__index < __args.length) {
					$eswitch;
				}
			}
		}
	}
}