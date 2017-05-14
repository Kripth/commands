// rdmd generate.d <mcpe-apk-location>
module generate;

import std.file;
import std.regex;
import std.string;
import std.zip;

enum commands_file = "alias Commands = TypeTuple!(";

enum start = "assets/resource_packs/vanilla/texts/";
enum end = ".lang";

void main(string[] args) {

	string[] commands;
	
	foreach(line ; split(cast(string)read("../src/commands.d"), "\n")) {
		line = line.strip;
		if(line.startsWith(commands_file)) {
			foreach(command ; split(line[commands_file.length..$-2], ",")) {
				command = command.strip;
				if(command.length >= 2) commands ~= command[1..$-1];
			}
			break;
		}
	}
	
	auto apk = new ZipArchive(read(args[1]));
	foreach(location, member; apk.directory) {
		if(location.startsWith(start) && location.endsWith(end)) {
			apk.expand(member);
			string[] file = ["## Automatically generated using Minecraft: Pocket Edition's language files."];
			foreach(line ; split(cast(string)member.expandedData, "\n")) {
				if(line.startsWith("commands.")) {
					immutable cmp = line[9..$];
					foreach(command ; commands) {
						if(cmp.startsWith(command ~ '.') || cmp.startsWith("generic.")) {
							line = line.strip;
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
			write(location[start.length..$], file.join("\n"));
		}
	}

}
