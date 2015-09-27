import cmd.Cmd;
import cmd.Cmd.*;
import haxe.Json;
import haxe.crypto.Crc32;
import haxe.io.Bytes;
import haxe.io.Path;
import haxe.zip.Entry;
import haxe.zip.Reader;
import haxe.zip.Writer;
import sys.FileSystem;
import sys.io.File;
import thx.semver.Version;

typedef Dependency =
{
	var id:String;
	var version:Version;
}

class Stencylrm
{
	/*-------------------------------------*\
	 * Main
	\*-------------------------------------*/ 
	
	public static function main():Void
	{
		var args = getArgs();
		
		if(args.length == 0)
		{
			printHelp();
			return;
		}
		
		var command = args.shift();
		
		switch(command)
		{
			case "setup":
				setup();
			case "add":
				addVersion(args);
			case "list":
				listExtensions(args);
			case "versions":
				listVersions(args);
			case "path":
				getVersionPath(args);
		}
	}
	
	public static function printHelp():Void
	{
		trace
		(
			"\nStencyl Repository Manager\n\n" +
			
			"setup\n" + 
			"   Sets the active repository to the current directory.\n" +
			"   Creates needed files to run the rest of the commands.\n\n" +
			
			"add {jar} {changes}\n" +
			"   Adds a new extension version to the repository.\n" +
			"   Pertinent info is taken from the jar's manifest to\n" +
			"   determine extension id, version, and other info.\n" +
			"   {jar} path to jar file.\n" +
			"   {changes} path to changeset file.\n\n" +
			
			"list {type} (options)\n" +
			"   Lists the extensions of specified type.\n" +
			"   {type} is engine or toolset.\n" +
			" Options:\n" +
			"   -json\n\n" +
			
			"versions {type} {name} (options)\n" +
			"   Lists the versions for the specified extension.\n" +
			"   {type} is engine or toolset.\n" +
			"   {name} is a unique id for the extension.\n" +
			" Options:\n" +
			"   -l only the latest version is returned.\n" +
			"   -f 1.0.0 only include versions after the one specified.\n" +
			"   -d extension.id-1.0 \n" +
			"   -json\n\n" +
			
			"path {type} {name} {version}\n" +
			"   Get the path where a specific version is stored.\n" +
			"   {type} is engine or toolset.\n" +
			"   {name} is a unique id for the extension.\n" +
			"   {version} is the desired version."
		);
	}
	
	/*-------------------------------------*\
	 * Commands
	\*-------------------------------------*/ 
	
	public static function setup():Void
	{
		var cwd = Sys.getCwd();
		var enginePath = Path.join([cwd, "engine"]);
		var toolsetPath = Path.join([cwd, "toolset"]);
		if(!FileSystem.exists(enginePath))
			FileSystem.createDirectory(enginePath);
		if(!FileSystem.exists(toolsetPath))
			FileSystem.createDirectory(toolsetPath);
		
		File.saveContent(getConfigFilePath(), cwd);
	}
	
	public static function addVersion(args:Array<String>):Void
	{
		var jarPath = args[0];
		var changePath = args[1];
		
		var entries = getEntries(jarPath);
		var m = getManifest(entries);
		var iconPath = m.get("Extension-Icon");
		var icon = getBytes(entries, iconPath);
		entries = null;
		
		var version = m.get("Extension-Version");
		var dep = m.get("Extension-Dependencies");
		var requiredStencyl = m.get("Extension-RequiredStencyl");
		var requiredJava = m.get("Extension-RequiredExecutionEnvironment");
		
		//basic info
		var id = m.get("Extension-ID");
		
		var name = m.get("Extension-Name");
		var description = m.get("Extension-Description");
		var authorName = m.get("Extension-Author");
		var website = m.get("Extension-Website");
		var type = m.get("Extension-Type");
		
		var extPath = getExtPath("toolset", id);
		if(!FileSystem.exists(extPath))
			FileSystem.createDirectory(extPath);
		
		zipFile(jarPath, '$extPath/$version.zip');
		
		var versions_json = FileSystem.exists('$extPath/versions') ?
				Json.parse(File.getContent('$extPath/versions')) :
				{"versions": []};
		var versionList = [];
		var added = false;
		var newVersion = {"version": version, "changes": File.getContent(changePath), "requires_ext": dep, "requires_stencyl": requiredStencyl, "requires_java": requiredJava};
		for(version_json in versions_json.versions)
		{
			if(version_json.version == version)
			{
				versionList.push(newVersion);
				added = true;
			}
			else
				versionList.push(version_json);
		}
		if(!added)
			versionList.push(newVersion);
		versions_json.versions = versionList;
		File.saveContent('$extPath/versions', Json.stringify(versions_json));
		
		File.saveContent
		(
			'$extPath/info',
			
			'Name=$name\n' +
			'Description=$description\n' +
			'Author=$authorName\n' +
			'Website=$website\n' +
			'Type=$type'
		);
		
		File.saveBytes('$extPath/icon.png', icon);
	}
	
	public static function listExtensions(args:Array<String>):Void
	{
		var switches = processSwitches(args, ["json"]);
		var type = args[0];
		
		var files = FileSystem.readDirectory('${getRepositoryPath()}/$type');
		
		if(switches.exists("json"))
		{
			Sys.println(Json.stringify({"extensions": files}));
		}
		else
		{
			for(file in files)
				Sys.println(file);
		}
	}
	
	public static function listVersions(args:Array<String>):Void
	{
		var switches = processSwitches(args, ["json", "l"]);
		var type = args[0];
		var name = args[1];
		
		var latest = switches.exists("l");
		var fromVersion:Version = switches.exists("f") ?
				switches.get("f") :
				null;
		var depends = switches.get("d");
		var stencyl = switches.get("s");
		var json = switches.exists("json");
		
		var deps = (depends == null) ? [] :
			depends.split(",").map(function(d) { return asDep(d);});
		
		var extPath = getExtPath(type, name);
		
		var versions_json = Json.parse(File.getContent('$extPath/versions'));
		
		var list = [];
		
		for(version_json in (versions_json.versions:Array<Dynamic>))
		{
			var curVer:Version = (version_json.version:String);
			if(fromVersion != null && curVer <= fromVersion)
				continue;
			if(stencyl != null && Std.parseInt(stencyl.substring(1)) < Std.parseInt((version_json.requires_stencyl:String).substring(1)))
				continue;
			/*
			if(deps != null)
			{
				var versionDeps = version_json.requires_ext.split(",").map(function(d) { return asDep(d); });
				
				for(dep in deps)
				{
					
				}				
			}
			*/
			
			list.push(version_json);
		}
		if(latest && list.length > 1)
			list.splice(0, list.length - 1);
		
		if(json)
			Sys.println(Json.stringify({"versions": list}));
		else
			for(version in list)
				Sys.println(version);
	}
	
	public static function getVersionPath(args:Array<String>):Void
	{
		var type = args[0];
		var name = args[1];
		var version = args[2];
		
		Sys.print(getExtPath(type, name) + '/$version.zip');
	}
	
	// ----
	
	static function asDep(d:String):Dependency
	{
		var split = d.split("-");
		if(split.length == 1)
			return {"id": split[0], "version": "0.0.1"};
		var values = split[1].split(".").map(function (v) { return Std.parseInt(v); });
		return {"id": split[0], "version":values};
	}
	
	/*-------------------------------------*\
	 * Paths
	\*-------------------------------------*/ 
	
	static function getConfigFilePath():String
	{
		if(Sys.systemName() == "Windows")
			return Sys.getEnv("HOMEDRIVE") + Sys.getEnv("HOMEPATH") + "/.stencylrm";
		else
			return Sys.getEnv("HOME") + "/.stencylrm";
	}
	
	static function getRepositoryPath():String
	{
		var cfgPath = getConfigFilePath();
		
		if(!FileSystem.exists(cfgPath))
			return null;
		
		return File.getContent(cfgPath).split("\n")[0];
	}
	
	static function getExtPath(type:String, name:String):String
	{
		return '${getRepositoryPath()}/$type/$name';
	}
	
	static function getExtPathCwd():String
	{
		var propPath = Path.join([Sys.getCwd(), ".stencylrm"]);
		var props = parsePropertiesFile(propPath);
		
		var type = props.get("type");
		var name = props.get("name");
		
		return getExtPath(type, name);
	}
	
	/*-------------------------------------*\
	 * Properties Files
	\*-------------------------------------*/ 
	
	static function parsePropertiesFile(path:String):Map<String, String>
	{
		return parseProperties(File.getContent(path));
	}
	
	// https://gist.github.com/YellowAfterlife/9643940
	static function parseProperties(text:String):Map<String, String>
	{
		var map:Map<String, String> = new Map(),
			ofs:Int = 0,
			len:Int = text.length,
			i:Int, j:Int,
			endl:Int;
		while (ofs < len)
		{
			// find line end offset:
			endl = text.indexOf("\n", ofs);
			if (endl < 0) endl = len; // last line
			// do not process comment lines:
			i = text.charCodeAt(ofs);
			if (i != "#".code && i != "!".code)
			{
				// find key-value delimiter:
				i = text.indexOf("=", ofs);
				j = text.indexOf(":", ofs);
				if (j != -1 && (i == -1 || j < i)) i = j;
				//
				if (i >= ofs && i < endl)
				{
					// key-value pair "key: value\n"
					map.set(StringTools.trim(text.substring(ofs, i)),
					StringTools.trim(text.substring(i + 1, endl)));
				}
				else
				{
					// value-less declaration "key\n"
					map.set(StringTools.trim(text.substring(ofs, endl)), "");
				}
			}
			// move on to next line:
			ofs = endl + 1;
		}
		return map;
	}
	
	/*-------------------------------------*\
	 * Manifest Reading
	\*-------------------------------------*/ 
	
	static function getEntries(jarPath:String):List<Entry>
	{
		var fileIn = File.read(jarPath);
		var entries = Reader.readZip(fileIn);
		fileIn.close();
		
		return entries;
	}
	
	static function getManifest(entries:List<Entry>):Map<String, String>
	{
		var map = new Map<String, String>();
		var bytes = getBytes(entries, "META-INF/MANIFEST.MF");
		
		if(bytes == null)
			return map;
		
		var content = bytes.toString();
		
		var key = null;
		var value = "";
		
		for(line in content.split("\r\n"))
		{
			if(line.length == 0)
				continue;
			
			if(line.charAt(0) == " ")
				value += line.substring(1);
			else
			{
				if(key != null)
				{
					map.set(key, value);
					key = null;
				}
				key = line.substring(0, line.indexOf(":"));
				value = line.substring(line.indexOf(":") + 2);
			}
		}
		if(key != null)
			map.set(key, value);
		
		return map;
	}
	
	static function getBytes(entries:List<Entry>, path:String):Bytes
	{
		for(entry in entries)
			if(entry.fileName == path)
				return Reader.unzip(entry);
		
		return null;
	}
	
	static function zipFile(path:String, out:String):Void
	{
		var zipdata = new List<Entry>();
		addEntries(path, "", zipdata);
		
		var output = File.write(out);
		var zipWriter = new Writer(output);
		zipWriter.write(zipdata);
		output.close();
	}
	
	static function addEntries(path:String, prefix:String, entries:List<Entry>):Void
	{
		var fpath = new Path(path);
		var filename = fpath.file;
		if(fpath.ext != null)
			filename += '.${fpath.ext}';
		
		if(FileSystem.isDirectory(path))
		{
			entries.add({
				fileName : prefix + filename,
				fileSize : 0, 
				fileTime : Date.now(), 
				compressed : false, 
				dataSize : 0,
				data : null,
				crc32 : 0,
				extraFields : new List()
			});
			
			for(file in FileSystem.readDirectory(path))
				addEntries(file, '$prefix/filename', entries);
		}
		else
		{
			var data = File.getBytes(path);
			
			var entry = {
				fileName : prefix + filename,
				fileSize : data.length, 
				fileTime : Date.now(), 
				compressed : false, 
				dataSize : data.length,
				data : data,
				crc32 : Crc32.make(data),
				extraFields : new List()
			};
			
			haxe.zip.Tools.compress(entry, 4);
			
			entries.add(entry);
		}
	}
}
