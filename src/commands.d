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

import std.algorithm : sort, min;
import std.ascii : newline;
import std.conv : to, ConvException;
import std.json : parseJSON, JSON_TYPE, JSONValue;
import std.math : ceil;
import std.string;
import std.traits : hasUDA, getUDAs;
import std.typetuple : TypeTuple;

import sel.node.plugin;

import sel.entity.effect : Effect, Effects;
import sel.entity.living : Living;
import sel.event.world.damage : EntityDamageByCommandEvent;
import sel.player.player : InputMode;
import sel.util.command : Command;
import sel.world.rules : Gamemode;

alias Commands = TypeTuple!("clear", "deop", "effect", "gamemode", "help", "kick", "kill", "me", "op", "say", "seed", "stop", "tell", "time", "toggledownfall", "transfer", "transferserver", "world", "worlds");

class Main {

	@start load() {
		if(!exists("plugins.json")) {
			string[] file;
			foreach(immutable command ; Commands) {
				mixin("alias C = " ~ command ~ "0;");
				static if(hasUDA!(C, description)) {
					immutable description = getUDAs!(C, description)[0].description;
				} else {
					immutable description = "{commands." ~ command ~ ".description}";
				}
				static if(hasUDA!(C, aliases)) {
					string[] a = getUDAs!(C, aliases)[0].aliases;
				} else {
					string[] a;
				}
				file ~= createJSON(command, description, a, hasUDA!(C, op), hasUDA!(C, hidden));
			}
			write("plugins.json", "{" ~ newline ~ file.join("," ~ newline) ~ newline ~ "}" ~ newline);
		}
		auto json = parseJSON(cast(string)read("plugins.json"));
		foreach(immutable command ; Commands) {
			auto c = command in json;
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
		return ("\t\"" ~ command ~ "\": {" ~ newline ~
				"\t\t\"enabled\": true," ~ newline ~
				"\t\t\"description\": " ~ JSONValue(description).toString() ~ "," ~ newline ~
				(aliases.length ? "\t\t\"aliases\": " ~ to!string(aliases) ~ "," ~ newline : "") ~
				"\t\t\"op\": " ~ to!string(op) ~ "," ~ newline ~
				"\t\t\"hidden\": " ~ to!string(hidden) ~ newline ~ "\t}");
	}
	
	private void register(string command, size_t index)(bool op, bool hidden, string description, string[] aliases) {
		mixin("alias C = " ~ command ~ to!string(index) ~ ";");
		server.registerCommand!C(mixin("&this." ~ command ~ to!string(index)), command, description, aliases, [], op, hidden);
		static if(__traits(compiles, mixin(command ~ to!string(index + 1)))) {
			this.register!(command, index+1)(op, hidden, description, aliases);
		}
	}
	
	@op clear0(Player sender) {
		//TODO empty inventory
	}
	
	@op clear1(CommandSender sender, Target target) {
		//TODO empty inventory if the entity has one
	}

	@op deop0(CommandSender sender, Player[] players) {
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
		if(failed.length) sender.sendMessage(Text.red, translation("commands.deop.failed"), failed.join(", "));
		if(opped.length) sender.sendMessage(translation("commands.deop.success"), opped.join(", "));
	}

	@op effect0(CommandSender sender, Target target, SnakeCaseEnum!Effects effect, tick_t duration=30, ubyte level=0) {
		foreach(entity ; target.entities) {
			auto living = cast(Living)entity;
			if(living) {
				living.addEffect(Effect.fromId(effect, living, level, duration));
				sender.sendMessage(pocket_t("commands.effect.success"), effect.name, level, entity.name, duration);
			}
		}
	}
	
	@op effect1(CommandSender sender, Target target, SingleEnum!"clear" clear) {
		foreach(entity ; target.entities) {
			auto living = cast(Living)entity;
			if(living) {
				if(living.clearEffects()) sender.sendMessage(translation("commands.effect.success.removed.all"), entity.name);
				else sender.sendMessage(Text.red, translation("commands.effect.failure.notActive.all"), entity.name);
			}
		}
	}
	
	@op effect2(CommandSender sender, Target target, SingleEnum!"clear" clear, SnakeCaseEnum!Effects effect) {
		foreach(entity ; target.entities) {
			auto living = cast(Living)entity;
			if(living) {
				if(living.removeEffect(effect)) sender.sendMessage(translation("commands.effect.success.removed"), effect.name, entity.name);
				else sender.sendMessage(Text.red, translation("commands.effect.failure.notActive"), effect.name, entity.name);
			}
		}
	}
	
	@op @aliases("gm") gamemode0(Player sender, Gamemode gamemode) {
		if(sender.gamemode != gamemode) sender.gamemode = gamemode;
		sender.sendMessage(translation("commands.gamemode.success.self"), gamemode);
	}
	
	@op @aliases("gm") gamemode1(Player sender, int gamemode) {
		if(gamemode >= 0 && gamemode <= 3) {
			this.gamemode0(sender, cast(Gamemode)gamemode);
		} else {
			sender.sendMessage(Text.red, pocket_t("commands.gamemode.fail.invalid"), gamemode);
		}
	}
	
	@op @aliases("gm") gamemode2(CommandSender sender, Player[] target, Gamemode gamemode) {
		foreach(player ; target) {
			player.gamemode = gamemode;
			sender.sendMessage(translation("commands.gamemode.success.other"), player.name, gamemode);
		}
	}
	
	@op @aliases("gm") gamemode3(CommandSender sender, Player[] target, int gamemode) {
		if(gamemode >= 0 && gamemode <= 3) {
			this.gamemode2(sender, target, cast(Gamemode)gamemode);
		} else {
			sender.sendMessage(Text.red, pocket_t("commands.gamemode.fail.invalid"), gamemode);
		}
	}
	
	@aliases("?") help0(CommandSender sender, size_t page=1) {
		auto player = cast(Player)sender;
		if(player) {
			Command[] commands;
			foreach(command ; player.commandMap) {
				if(!command.hidden) commands ~= command;
			}
			sort!((a, b) => a.command < b.command)(commands);
			immutable pages = ceil(commands.length.to!float / 7); // commands.length should always be at least 1 (help command)
			if(--page >= pages) page = 0;
			sender.sendMessage(Text.darkGreen, translation("commands.help.header"), page+1, pages);
			string[] messages;
			foreach(command ; commands[page*7..min($, (page+1)*7)]) {
				messages ~= (command.command ~ " " ~ this.formatArgs(command)[0]);
			}
			sender.sendMessage(messages.join("\n"));
			if(player.inputMode == InputMode.keyboard) {
				sender.sendMessage(Text.green, translation("commands.help.footer"));
			}
		} else if(cast(Server)sender) {
			//TODO
		} else {
			sender.sendMessage("Sorry, no help today!");
		}
	}

	@aliases("?") help1(Player sender, string command) {
		auto cmd = sender.commandByName(command);
		if(cmd !is null) {
			string message = Text.yellow ~ cmd.command ~ ":";
			if(cmd.description.length > 2 && cmd.description[0] == '{' && cmd.description[$-1] == '}') {
				sender.sendMessage(message);
				sender.sendMessage(Text.yellow, pocket_t(cmd.description[1..$-1]));
			} else {
				sender.sendMessage(message, "\n", cmd.description);
			}
			auto params = formatArgs(cmd);
			foreach(ref param ; params) {
				param = "- /" ~ command ~ " " ~ param;
			}
			sender.sendMessage(translation("commands.generic.usage"), "");
			sender.sendMessage(params.join("\n"));
		} else {
			sender.sendMessage(Text.red, translation("commands.generic.notFound"));
		}
	}
	
	private string[] formatArgs(Command command) {
		string[] ret;
		foreach(o ; command.overloads) {
			string[] p;
			foreach(i, string param; o.params) {
				string full = param ~ ": " ~ o.typeOf(i);
				if(i < o.requiredArgs) {
					p ~= "<" ~ full ~ ">";
				} else {
					p ~= "[" ~ full ~ "]";
				}
			}
			ret ~= p.join(" ");
		}
		return ret;
	}
	
	@op kick0(CommandSender sender, Target target, string message="") {
		string[] kicked;
		foreach(player ; target.players) {
			player.kick(message);
			kicked ~= player.name;
		}
		if(kicked.length) sender.sendMessage(translation("commands.kick.success" ~ (message.length ? ".reason" : "")), kicked.join(", "), message);
		else if(!target.input.startsWith("@")) sender.sendMessage(Text.red, translation("commands.generic.player.notFound", "commands.kick.not.found"), target.input);
	}
	
	@op kill0(CommandSender sender, Target target) {
		string[] killed;
		foreach(entity ; target.entities) {
			if(entity.alive) {
				entity.attack(new EntityDamageByCommandEvent(entity));
				if(entity.dead) killed ~= entity.name;
			}
		}
		if(killed.length) sender.sendMessage(translation("commands.kill.successful"), killed.join(", "));
	}
	
	void me0(Player sender, string message) {
		sender.world.broadcast("* " ~ sender.displayName ~ " " ~ message);
	}
	
	@op op0(CommandSender sender, Player[] players) {
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
		if(failed.length) sender.sendMessage(Text.red, translation("commands.op.failed"), failed.join(", "));
		if(opped.length) sender.sendMessage(translation("commands.op.success"), opped.join(", "));
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
		sender.sendMessage(translation("commands.stop.start"));
		server.shutdown();
	}
	
	@aliases("msg", "w") tell0(Player sender, Player[] recipient, string message) {
		if(recipient.length) {
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
	
	enum TimeQuery { daytime, gametime, day }
	
	enum TimeString : int { day = 1000, night = 13000 }
	
	@op time0(WorldCommandSender sender, SingleEnum!"add" add, int amount) {
		sender.world.time = sender.world.time + amount;
		sender.sendMessage(translation("commands.time.added"), amount);
	}
	
	@op time1(WorldCommandSender sender, SingleEnum!"query" query, TimeQuery time) {
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
	
	@op time2(WorldCommandSender sender, SingleEnum!"set" set, int amount) {
		sender.world.time = amount;
		sender.sendMessage(translation("commands.time.set"), sender.world.time);
	}
	
	@op time3(WorldCommandSender sender, SingleEnum!"set" set, TimeString amount) {
		this.time2(sender, set, cast(int)amount);
	}
	
	@op toggledownfall0(WorldCommandSender sender) {
		sender.world.downfall = !sender.world.downfall;
		sender.sendMessage(translation("commands.downfall.success"));
	}
	
	@op transfer0(CommandSender sender, Player[] player, string node) {
		auto nodei = server.nodeWithName(node);
		if(nodei !is null) {
			foreach(p ; player) p.transfer(nodei);
		}
	}
	
	@aliases("ts") @op transferserver0(CommandSender sender, Player[] player, string ip, ushort port=19132) {
		foreach(p ; player) {
			try {
				p.transfer(ip, port);
				sender.sendMessage(pocket_t("commands.transferserver.successful"), p.name);
			} catch(Exception) {}
		}
	}
	
	@op @description("Adds, removes or transfer a player to a world") world0(CommandSender sender, SingleEnum!"add" add, string name) {
		server.addWorld(name);
		sender.sendMessage("World '", name, "' added");
	}
	
	@op world1(CommandSender sender, SingleEnum!"remove" remove, string world) {
		auto worlds = server.worldsWithName(world);
		foreach(w ; worlds) server.removeWorld(w);
		sender.sendMessage("Removed ", worlds.length, " world(s)");
	}
	
	@op world2(CommandSender sender, SingleEnum!"transfer" transfer, Player[] target, string world) {
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
	
	@op world3(Player sender, SingleEnum!"transfer" transfer, string world) {
		this.world2(sender, transfer, [sender], world);
	}
	
	@op @description("Display informations about the loaded worlds") worlds0(CommandSender sender) {
		string[] messages = server.worlds.length == 1 ? ["There is one world:"] : ["There are " ~ to!string(server.worlds.length) ~ " worlds:"];
		void addInfo(World[] worlds, string space) {
			foreach(world ; worlds) {
				messages ~= space ~ "- " ~ world.name ~ "(" ~ to!string(world.id) ~ ", " ~ to!string(world.entities.length) ~ " entitie(s), " ~ to!string(world.players.length) ~ " player(s))";
				if(world.children.length) addInfo(world.children, space ~ "   ");
			}
		}
		addInfo(server.worlds, "");
		sender.sendMessage(messages.join("\n"));
	}

	public @command("*") unknown(Player sender, arguments args) {
		if(args.length && sender.commandByName(args[0]) !is null) {
			sender.sendMessage(Text.red, translation("commands.generic.syntax"));
		} else {
			sender.sendMessage(Text.red, translation("commands.generic.notFound"));
		}
	}

}

private Translation translation(string minecraft, string pocket) {
	return Translation(pocket, minecraft, pocket);
}

private Translation translation(string message) {
	return Translation(message, message, message);
}

private Translation pocket_t(string message) {
	return Translation(message, "", message);
}
