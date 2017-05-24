/*
 * Copyright (c) 2017 SEL
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU Lesser General Public License for more details.
 * 
 */
module commands;

import std.algorithm : sort, min, canFind, clamp;
import std.ascii : newline;
import std.conv : to, ConvException;
import std.json : parseJSON, JSON_TYPE, JSONValue;
import std.math : ceil;
import std.string;
import std.traits : hasUDA, getUDAs;
import std.typetuple : TypeTuple;

import sel.node.plugin;

import sel.command : Command;
import sel.effect : Effect, Effects;
import sel.entity : Entity, Rotation;
import sel.entity.living : Living;
import sel.event.server : InvalidParametersEvent, UnknownCommandEvent;
import sel.event.world.damage : EntityDamageByCommandEvent;
import sel.format : unformat;
import sel.lang : translate, Translation;
import sel.math.vector : BlockPosition;
import sel.player.player : InputMode;
import sel.world.rules : Gamemode, Difficulty;

class Main {

	mixin((){
		string[] ret;
		foreach(immutable member ; __traits(allMembers, Main)) {
			mixin("alias M = " ~ member ~ ";");
			static if(member.endsWith("0")) {
				ret ~= "\"" ~ member[0..$-1] ~ "\"";
			}
		}
		return "alias Commands = TypeTuple!(" ~ ret.join(",") ~ ");";
	}());

	@start load() {
		if(!exists("plugins.json") || server.args.canFind("--reset-commands")) {
			string[] file;
			foreach(immutable command ; Commands) {
				mixin("alias C = " ~ command ~ "0;");
				static if(hasUDA!(C, description)) {
					immutable description = getUDAs!(C, description)[0].description;
				} else {
					immutable description = "%commands." ~ command ~ ".description";
				}
				static if(hasUDA!(C, aliases)) {
					string[] a = getUDAs!(C, aliases)[0].aliases;
				} else {
					string[] a;
				}
				file ~= createJSON(spaced!command, description, a, hasUDA!(C, op), hasUDA!(C, hidden));
			}
			write("plugins.json", "{" ~ newline ~ file.join("," ~ newline) ~ newline ~ "}" ~ newline);
		}
		auto json = parseJSON(cast(string)read("plugins.json"));
		foreach(immutable command ; Commands) {
			auto c = spaced!command in json;
			if(c) {
				auto _enabled = "enabled" in *c;
				auto _op = "op" in *c;
				auto _hidden = "hidden" in *c;
				auto _description = "description" in *c;
				auto _aliases = "aliases" in *c;
				if(_enabled && _enabled.type == JSON_TYPE.TRUE) {
					bool op = _op && _op.type == JSON_TYPE.TRUE;
					bool hidden = _hidden && _hidden.type == JSON_TYPE.TRUE;
					string description = _description && _description.type == JSON_TYPE.STRING ? _description.str : "";
					string[] aliases;
					if(_aliases && _aliases.type == JSON_TYPE.ARRAY) {
						foreach(_alias ; _aliases.array) {
							if(_alias.type == JSON_TYPE.STRING) aliases ~= _alias.str;
						}
					}
					this.register!(command, 0)(op, hidden, description, aliases);
				}
			}
		}
	}
	
	private string createJSON(string command, string description, string[] aliases, bool op, bool hidden) {
		string[] ret = [
			"\t\t\"enabled\": true",
			"\t\t\"description\": " ~ JSONValue(description).toString()
		];
		if(aliases.length) ret ~= "\t\t\"aliases\": " ~ aliases.to!string;
		if(op) ret ~= "\t\t\"op\": true";
		if(hidden) ret ~= "\t\t\"hidden\": true";
		return "\t\"" ~ command ~ "\": {" ~ newline ~ ret.join("," ~ newline) ~ newline ~ "\t}";
	}
	
	private void register(string command, size_t index)(bool op, bool hidden, string description, string[] aliases) {
		mixin("alias C = " ~ command ~ to!string(index) ~ ";");
		//TODO convert commandSpaced to command spaced
		server.registerCommand!C(mixin("&this." ~ command ~ to!string(index)), spaced!command, description, aliases, [], op, hidden);
		static if(__traits(compiles, mixin(command ~ to!string(index + 1)))) {
			this.register!(command, index+1)(op, hidden, description, aliases);
		}
	}
	
	private string spaced(string command)() {
		string ret;
		foreach(c ; command) {
			if(c >= 'A' && c <= 'Z') {
				ret ~= " ";
				ret ~= cast(char)(c + 32);
			} else {
				ret ~= c;
			}
		}
		return ret;
	}
	
	@op clear0(CommandSender sender, Target target) {
		if(checkTarget(sender, target)) {
			//TODO empty inventory if the entity has one
		}
	}
	
	void clear1(Player sender) {
		//TODO empty inventory
	}
	
	enum MaskMode { filtered, masked, replace }
	
	enum CloneMode { force, move, normal }
	
	@op clone0(WorldCommandSender sender, Position begin, Position end, Position destination, MaskMode maskMode=MaskMode.replace, CloneMode cloneMode=CloneMode.normal) {
		if(maskMode != MaskMode.filtered) {
			auto _begin = cast(BlockPosition)begin.from(sender.position);
			auto _end = cast(BlockPosition)end.from(sender.position);
			auto _destination = cast(BlockPosition)destination.from(sender.position);
			int[3] from, to;
			foreach(i, coord; TypeTuple!("x", "y", "z")) {
				mixin("auto b = _begin." ~ coord ~ ";");
				mixin("auto e = _end." ~ coord ~ ";");
				if(b < e) {
					from[i] = b;
					to[i] = e;
				} else {
					to[i] = b;
					from[i] = e;
				}
			}
			if(cloneMode != CloneMode.force) {
				//TODO check overlapping
			}
			size_t cloned = 0;
			foreach(x ; 0..to[0]-from[0]) {
				foreach(z ; 0..to[2]-from[2]) {
					foreach(y ; 0..to[1]-from[1]) {
						sender.world[_destination + [x, y, z]] = sender.world[from[0] + x, from[1] + y, from[2] + z].id;
						cloned++;
					}
				}
			}
			if(cloned != 0) {
				sender.sendMessage(Translation.all("commands.clone.success"), cloned);
			} else {
				sender.sendMessage(Text.red, Translation.all("commands.clone.failed"));
			}
		} else {
			sender.sendMessage(pocket_t("commands.generic.notImplemented"));
		}
	}

	@op deop0(CommandSender sender, Player[] players) {
		if(checkTarget(sender, players)) {
			string[] failed, opped;
			foreach(player ; players) {
				if(player.op) {
					player.op = false;
					player.sendMessage(pocket_t("commands.deop.message"));
					opped ~= player.name;
				} else {
					failed ~= player.name;
				}
			}
			if(failed.length) sender.sendMessage(Text.red, Translation.all("commands.deop.failed"), failed.join(", "));
			if(opped.length) sender.sendMessage(Translation.all("commands.deop.success"), opped.join(", "));
		}
	}
	
	@op difficulty0(WorldCommandSender sender, Difficulty difficulty) {
		sender.world.rules.difficulty = difficulty;
		sender.sendMessage(Translation.all("commands.difficulty.success"), difficulty);
	}
	
	void difficulty1(WorldCommandSender sender, int difficulty) {
		if(difficulty >= 0 && difficulty <= 3) {
			this.difficulty0(sender, cast(Difficulty)difficulty);
		} else {
			sender.sendMessage(Text.red, Translation.all("commands.generic.syntax"));
		}
	}

	@op effect0(CommandSender sender, Target target, SnakeCaseEnum!Effects effect, tick_t seconds=30, ubyte amplifier=0) {
		if(checkTarget(sender, target)) {
			foreach(entity ; target.entities) {
				auto living = cast(Living)entity;
				if(living) {
					living.addEffect(Effect.fromId(effect, living, amplifier, seconds));
					sender.sendMessage(pocket_t("commands.effect.success"), effect.name, amplifier, entity.name, seconds);
				}
			}
		}
	}
	
	void effect1(CommandSender sender, Target target, SingleEnum!"clear" clear) {
		if(checkTarget(sender, target)) {
			foreach(entity ; target.entities) {
				auto living = cast(Living)entity;
				if(living) {
					if(living.clearEffects()) sender.sendMessage(Translation.all("commands.effect.success.removed.all"), entity.name);
					else sender.sendMessage(Text.red, Translation.all("commands.effect.failure.notActive.all"), entity.name);
				}
			}
		}
	}
	
	void effect2(CommandSender sender, Target target, SingleEnum!"clear" clear, SnakeCaseEnum!Effects effect) {
		if(checkTarget(sender, target)) {
			foreach(entity ; target.entities) {
				auto living = cast(Living)entity;
				if(living) {
					if(living.removeEffect(effect)) sender.sendMessage(Translation.all("commands.effect.success.removed"), effect.name, entity.name);
					else sender.sendMessage(Text.red, Translation.all("commands.effect.failure.notActive"), effect.name, entity.name);
				}
			}
		}
	}
	
	@op @aliases("gm") gamemode0(Player sender, Gamemode gamemode) {
		if(sender.gamemode != gamemode) sender.gamemode = gamemode;
		sender.sendMessage(Translation.all("commands.gamemode.success.self"), gamemode);
	}
	
	void gamemode1(Player sender, int gamemode) {
		if(gamemode >= 0 && gamemode <= 3) {
			this.gamemode0(sender, cast(Gamemode)gamemode);
		} else {
			sender.sendMessage(Text.red, pocket_t("commands.gamemode.fail.invalid"), gamemode);
		}
	}
	
	void gamemode2(CommandSender sender, Player[] target, Gamemode gamemode) {
		if(checkTarget(sender, target)) {
			foreach(player ; target) {
				player.gamemode = gamemode;
				sender.sendMessage(Translation.all("commands.gamemode.success.other"), player.name, gamemode);
			}
		}
	}
	
	void gamemode3(CommandSender sender, Player[] target, int gamemode) {
		if(gamemode >= 0 && gamemode <= 3) {
			if(checkTarget(sender, target)) {
				this.gamemode2(sender, target, cast(Gamemode)gamemode);
			}
		} else {
			sender.sendMessage(Text.red, pocket_t("commands.gamemode.fail.invalid"), gamemode);
		}
	}
	
	@aliases("?") help0(ServerCommandSender sender) {
		Command[] commands;
		foreach(command ; sender.registeredCommands) {
			if(!command.hidden && command.command != "*") {
				foreach(overload ; command.overloads) {
					if(overload.callableByServer) {
						commands ~= command;
						break;
					}
				}
			}
		}
		sort!((a, b) => a.command < b.command)(commands);
		foreach(cmd ; commands) {
			if(cmd.description.startsWith("%")) {
				sender.sendMessage(Text.yellow, Translation(cmd.description[1..$]));
			} else {
				sender.sendMessage(Text.yellow, cmd.description);
			}
			string[] usages;
			foreach(overload ; cmd.overloads) {
				if(overload.callableByServer) {
					usages ~= ("/" ~ cmd.command ~ " " ~ this.formatArg(overload));
				}
			}
			if(usages.length == 1) {
				sender.sendMessage(Translation("commands.generic.usage"), usages[0]);
			} else {
				sender.sendMessage(Translation("commands.generic.usage"), "");
				foreach(usage ; usages) {
					sender.sendMessage("- ", usage);
				}
			}
		}
	}
	
	void help1(WorldCommandSender sender, ptrdiff_t page=1) {
		auto player = cast(Player)sender;
		if(player) {
			Command[] commands;
			foreach(command ; player.commandMap) {
				if(!command.hidden) commands ~= command;
			}
			sort!((a, b) => a.command < b.command)(commands);
			immutable pages = cast(size_t)ceil(commands.length.to!float / 7); // commands.length should always be at least 1 (help command)
			page = clamp(--page, 0, pages - 1);
			sender.sendMessage(Text.darkGreen, Translation.all("commands.help.header"), page+1, pages);
			string[] messages;
			foreach(command ; commands[page*7..min($, (page+1)*7)]) {
				messages ~= (command.command ~ " " ~ this.formatArgs(command)[0]);
			}
			sender.sendMessage(messages.join("\n"));
			if(player.inputMode == InputMode.keyboard) {
				sender.sendMessage(Text.green, Translation.all("commands.help.footer"));
			}
		} else {
			sender.sendMessage("Sorry, no help today!");
		}
	}

	void help2(Player sender, string command) {
		auto cmd = sender.commandByName(command);
		if(cmd !is null) {
			string message = Text.yellow ~ cmd.command ~ ":";
			if(cmd.description.startsWith("%")) {
				sender.sendMessage(message);
				sender.sendMessage(Text.yellow, pocket_t(cmd.description[1..$]));
			} else {
				sender.sendMessage(message, "\n", cmd.description);
			}
			auto params = formatArgs(cmd);
			foreach(ref param ; params) {
				param = "- /" ~ command ~ " " ~ param;
			}
			sender.sendMessage(Translation.all("commands.generic.usage"), "");
			sender.sendMessage(params.join("\n"));
		} else {
			sender.sendMessage(Text.red, Translation.all("commands.generic.notFound"));
		}
	}
	
	private string[] formatArgs(Command command) {
		string[] ret;
		foreach(overload ; command.overloads) {
			ret ~= this.formatArg(overload);
		}
		return ret;
	}
	
	private string formatArg(Command.Overload overload) {
		string[] p;
		foreach(i, param; overload.params) {
			if(overload.pocketTypeOf(i) == "stringenum" && overload.enumMembers(i).length == 1) {
				p ~= overload.enumMembers(i)[0];
			} else {
				string full = param ~ ": " ~ overload.typeOf(i);
				if(i < overload.requiredArgs) {
					p ~= "<" ~ full ~ ">";
				} else {
					p ~= "[" ~ full ~ "]";
				}
			}
		}
		return p.join(" ");
	}
	
	@op kick0(CommandSender sender, Target target, string message) {
		if(checkTarget(sender, target)) {
			string[] kicked;
			foreach(player ; target.players) {
				player.kick(message);
				kicked ~= player.name;
			}
			if(kicked.length) sender.sendMessage(Translation.all("commands.kick.success.reason"), kicked.join(", "), message);
			else if(!target.input.startsWith("@")) sender.sendMessage(Text.red, Translation("commands.kick.notFound", "commands.generic.player.notFound", "commands.kick.not.found"), target.input);
		}
	}

	@op kick1(CommandSender sender, Target target) {
		if(checkTarget(sender, target)) {
			string[] kicked;
			foreach(player ; target.players) {
				player.kick();
				kicked ~= player.name;
			}
			if(kicked.length) sender.sendMessage(Translation.all("commands.kick.success"), kicked.join(", "));
			else if(!target.input.startsWith("@")) sender.sendMessage(Text.red, Translation("commands.kick.notFound", "commands.generic.player.notFound", "commands.kick.not.found"), target.input);
		}
	}
	
	@op kill0(CommandSender sender, Target target) {
		if(checkTarget(sender, target)) {
			string[] killed;
			foreach(entity ; target.entities) {
				if(entity.alive) {
					entity.attack(new EntityDamageByCommandEvent(entity));
					if(entity.dead) killed ~= entity.name;
				}
			}
			if(killed.length) sender.sendMessage(Translation.all("commands.kill.successful"), killed.join(", "));
		}
	}
	
	void kill1(Player sender) {
		this.kill0(sender, Target(sender.name, [sender]));
	}
	
	void list0(CommandSender sender) {
		string[] names;
		foreach(player ; server.players) {
			names ~= player.displayName;
		}
		sender.sendMessage(Translation.all("commands.players.list"), server.online, server.max);
		if(names.length) sender.sendMessage(names.join(", "));
	}
	
	void me0(Player sender, string message) {
		sender.world.broadcast("* " ~ sender.displayName ~ " " ~ message);
	}
	
	@op op0(CommandSender sender, Player[] players) {
		if(checkTarget(sender, players)) {
			string[] failed, opped;
			foreach(player ; players) {
				if(player.op) {
					failed ~= player.name;
				} else {
					player.op = true;
					player.sendMessage(pocket_t("commands.op.message"));
					opped ~= player.name;
				}
			}
			if(failed.length) sender.sendMessage(Text.red, Translation.all("commands.op.failed"), failed.join(", "));
			if(opped.length) sender.sendMessage(Translation.all("commands.op.success"), opped.join(", "));
		}
	}

	@op say0(CommandSender sender, string message) {
		message = Text.lightPurple ~ "Server: " ~ message;
		if(cast(WorldCommandSender)sender) {
			(cast(WorldCommandSender)sender).world.broadcast(message);
		} else {
			server.broadcast(message);
		}
	}
	
	@op seed0(WorldCommandSender sender) {
		sender.sendMessage(to!string(sender.world.seed));
	}
	
	@op stop0(CommandSender sender) {
		sender.sendMessage(Translation.all("commands.stop.start"));
		server.shutdown();
	}
	
	@op @aliases("tp") @description("%commands.tp.description") teleport0(Player sender, Position destination, float yaw=Rotation.KEEP, float pitch=Rotation.KEEP) {
		sender.teleport(destination); //TODO yaw and pitch
		sender.sendMessage(pocket_t("commands.tp.successVictim"), destination.toCoordsString());
	}
	
	void teleport1(CommandSender sender, Target victim, Position destination, float yaw=Rotation.KEEP, float pitch=Rotation.KEEP) {
		if(checkTarget(sender, victim)) {
			string[] names;
			foreach(entity ; victim.entities) {
				entity.teleport(destination); //TODO yaw and pitch
				names ~= entity.name;
			}
			sender.sendMessage(Translation.all("commands.tp.success"), names.join(", "), destination.toCoordsString());
		}
	}
	
	void teleport2(CommandSender sender, Target victim, Entity destination) {
		if(checkTarget(sender, victim) && checkTarget(sender, destination)) {
			string[] names;
			foreach(entity ; victim.entities) {
				entity.teleport(destination.position);
				names ~= entity.name;
			}
			sender.sendMessage(Translation.all("commands.tp.success"), names.join(", "), destination.name);
		}
	}
	
	void teleport3(Player sender, Entity destination) {
		if(checkTarget(sender, destination)) {
			sender.teleport(destination.position);
			sender.sendMessage(pocket_t("commands.tp.successVictim"), destination.name);
		}
	}
	
	@aliases("msg", "w") tell0(Player sender, Player[] recipient, string message) {
		if(checkTarget(sender, recipient)) {
			string[] names;
			foreach(player ; recipient) {
				names ~= player.name;
			}
			message = Text.italic ~ "[" ~ sender.name ~ " -> " ~ names.join(", ") ~ "] " ~ message;
			sender.sendMessage(message);
			foreach(player ; recipient) {
				player.sendMessage(message);
			}
		}
	}
	
	@op timeAdd0(WorldCommandSender sender, int amount) {
		sender.world.time = sender.world.time + amount;
		sender.sendMessage(Translation.all("commands.time.added"), amount);
	}
	
	enum TimeQuery { daytime, gametime, day }
	
	@op timeQuery0(WorldCommandSender sender, TimeQuery time) {
		final switch(time) {
			case TimeQuery.daytime:
				sender.sendMessage(pocket_t("commands.time.query.daytime"), sender.world.time);
				break;
			case TimeQuery.gametime:
				sender.sendMessage(pocket_t("commands.time.query.gametime"), sender.world.ticks);
				break;
			case TimeQuery.day:
				sender.sendMessage(pocket_t("commands.time.query.day"), cast(uint)sender.world.ticks/24000);
				break;
		}
	}
	
	enum TimeString : int { day = 1000, night = 13000 }
	
	@op timeSet0(WorldCommandSender sender, int time) {
		sender.world.time = time;
		sender.sendMessage(Translation.all("commands.time.set"), sender.world.time);
	}
	
	void timeSet1(WorldCommandSender sender, TimeString time) {
		this.timeSet0(sender, cast(int)time);
	}
	
	@op toggledownfall0(WorldCommandSender sender) {
		sender.world.downfall = !sender.world.downfall;
		sender.sendMessage(Translation.all("commands.downfall.success"));
	}
	
	@op @description("Transfer player(s) to another node") transfer0(CommandSender sender, Player[] player, string node) {
		auto nodei = server.nodeWithName(node);
		if(nodei !is null) {
			foreach(p ; player) p.transfer(nodei);
		}
	}
	
	@aliases("ts") @op transferserver0(CommandSender sender, Player[] target, string ip, int port=19132) {
		if(checkTarget(sender, target)) {
			ushort _port = cast(ushort)port;
			if(port == _port) {
				foreach(p ; target) {
					try {
						p.transfer(ip, _port);
						sender.sendMessage(pocket_t("commands.transferserver.successful"), p.name);
					} catch(Exception) {}
				}
			} else {
				sender.sendMessage(pocket_t("commands.transferserver.invalid.port"));
			}
		}
	}
	
	void transferserver1(Player sender, string ip, int port=19132) {
		this.transferserver0(sender, [sender], ip, port);
	}
	
	enum WeatherType : string { rain = "rain", thunder = "thunder" }
	
	@op weather0(WorldCommandSender sender, WeatherType type, int duration=0) {
		if(duration <= 0 || duration > 1000000) duration = sender.world.random.range(6000, 18000);
		// cannot set weather using type/duration in SEL yet
		sender.world.downfall = true;
		sender.sendMessage(Translation.all("commands.weather." ~ type));
	}
	
	void weather1(WorldCommandSender sender, SingleEnum!"clear" clear) {
		sender.world.downfall = false;
		sender.sendMessage(Translation.all("commands.weather.clear"));
	}
	
	@op @description("Creates and registers a world") worldAdd0(CommandSender sender, string name) {
		server.addWorld(name);
		sender.sendMessage("World '", name, "' added");
	}
	
	@op @description("Removes a world") worldRemove0(CommandSender sender, string world) {
		auto worlds = server.worldsWithName(world);
		foreach(w ; worlds) server.removeWorld(w);
		sender.sendMessage("Removed ", worlds.length, " world(s)");
	}
	
	@op @description("Transfers player(s) between worlds") worldTransfer0(CommandSender sender, Player[] target, string world) {
		auto worlds = server.worldsWithName(world);
		if(worlds.length) {
			string[] names;
			foreach(player ; target) {
				player.world = worlds[0];
				names ~= player.name;
			}
			if(names.length) sender.sendMessage("Transferred ", names.join(", "), " to ", world);
		} else {
			sender.sendMessage("Cannot find world '", world, "'");
		}
	}
	
	void worldTransfer1(Player sender, string world) {
		this.worldTransfer0(sender, [sender], world);
	}
	
	@op @description("Shows informations about the loaded worlds") worlds0(CommandSender sender) {
		string[] messages = server.worlds.length == 1 ? ["There is one world:"] : ["There are " ~ to!string(server.worlds.length) ~ " worlds:"];
		void addInfo(World[] worlds, string space) {
			foreach(world ; worlds) {
				messages ~= space ~ "- " ~ world.name ~ "(" ~ to!string(world.id) ~ ", " ~ to!string(world.loadedChunks) ~ " chunk(s), " ~ to!string(world.entities.length) ~ " entitie(s), " ~ to!string(world.players.length) ~ " player(s))";
				if(world.children.length) addInfo(world.children, space ~ "   ");
			}
		}
		addInfo(server.worlds, "");
		sender.sendMessage(messages.join("\n"));
	}
	
	@event invalidParameters(InvalidParametersEvent event) {
		event.sender.sendMessage(Text.red, Translation.all("commands.generic.syntax"));
	}
	
	@event unknownCommand(UnknownCommandEvent event) {
		event.sender.sendMessage(Text.red, Translation.all("commands.generic.notFound"));
	}

}

/**
 * Cheks whether the target is valid and sends an error message
 * to sender if it's not.
 */
private bool checkTarget(T)(CommandSender sender, T target) {
	static if(is(T == Target)) {
		return checkTargetImpl(sender, target.entities.length != 0);
	} else static if(is(T == Player[]) || is(T == Entity[])) {
		return checkTargetImpl(sender, target.length != 0);
	} else static if(is(T == Player) || is(T == Entity)) {
		return checkTargetImpl(sender, target !is null);
	} else {
		return checkTargetImpl(sender, false);
	}
}

/// ditto
private bool checkTargetImpl(CommandSender sender, bool valid) {
	if(!valid) sender.sendMessage(Text.red, pocket_t("commands.generic.noTargetMatch"));
	return valid;
}

private Translation pocket_t(string message) {
	return Translation(message, "", message);
}
