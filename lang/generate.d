// rdmd generate.d <mcpe-apk-location>
module generate;

import std.algorithm : sort;
import std.file;
import std.json;
import std.regex;
import std.string;
import std.zip;

enum commands_file = "alias Commands = TypeTuple!(";

enum start = "assets/resource_packs/vanilla/texts/";
enum end = ".lang";

void main(string[] args) {

	string[] commands = ["generic", "players"];
	
	void add(string command) {
		string[] spl = command.split(" ");
		commands ~= spl[0];
		if(spl.length > 1) {
			string ret = spl[0];
			foreach(s ; spl[1..$]) {
				ret ~= capitalize(s);
			}
			commands ~= ret;
		}
	}
	
	auto settings = parseJSON(cast(string)read("../../../resources/commands/plugins.json"));
	
	foreach(string command, obj; settings.object) {
		auto aliases = "aliases" in obj;
		if(aliases) {
			foreach(alias_ ; (*aliases).array) add(alias_.str);
		}
		add(command);
	}
	
	auto apk = new ZipArchive(read(args[1]));
	foreach(location, member; apk.directory) {
		if(location.startsWith(start) && location.endsWith(end)) {
			apk.expand(member);
			string[] file = ["## Automatically generated using Minecraft: Pocket Edition's language files."];
			foreach(line ; split(cast(string)member.expandedData, "\n")) {
				if(line.startsWith("commands.")) {
					auto spl = line.split(".");
					foreach(command ; commands) {
						if(spl[1] == command) {
							line = spl.join(".").strip;
							if(line.endsWith("#")) line = line[0..$-1].strip;
							string mx;
							for(size_t i=0; i<line.length; i++) {
								if(line[i] == '%' && i < line.length - 1) {
									if(line[i+1] == 'd' || line[i+1] == 's') {
										mx ~= "{0}";
										i++;
										continue;
									} else if(i < line.length - 3 && (line[i+3] == 'd' || line[i+3] == 's') && line[i+2] == '$') {
										mx ~= "{" ~ cast(char)(line[i+1] - 1) ~ "}";
										i += 3;
										continue;
									}
								}
								mx ~= line[i];
							}
							file ~= mx;
							break;
						}
					}
				}
			}
			sort(file);
			write(location[start.length..$], file.join("\n"));
		}
	}

}
