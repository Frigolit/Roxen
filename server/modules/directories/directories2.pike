/*
 * $Id: directories2.pike,v 1.1.2.2 1997/02/14 03:16:24 grubba Exp $
 *
 * Directory listings mark 2
 *
 * Henrik Grubbström 1997-02-13
 */

string cvs_version = "$Id: directories2.pike,v 1.1.2.2 1997/02/14 03:16:24 grubba Exp $";
#include <module.h>
inherit "module";
inherit "roxenlib";

array register_module()
{
  return ({ MODULE_DIRECTORIES | MODULE_PARSER,
	      "Directory parsing module mk2",
	      "This module is an experimental directory parsing module. "
	      "It pretty prints a list of files much like the ordinary "
	      "directory parsing module. "
	      "The difference is that this one uses the flik-module "
	      "for the fold/unfolding, and uses relative URL's with "
	      "the help of some new tags: "
	      "&lt;REL&gt;, &lt;AREL&gt; and &lt;INSERT-QUOTED&gt;.",
	      ({ }), 1 });
}

void create()
{
  defvar("indexfiles", ({ "index.html", "Main.html", "welcome.html",
			  "index.cgi", "index.lpc", "index.pike" }),
	 "Index files", TYPE_STRING_LIST,
	 "If one of these files is present in a directory, it will "
	 "be returned instead of the directory listing.");

  defvar("readme", 1, "Include readme files", TYPE_FLAG,
	 "If set, include readme files in directory listings");
  
  defvar("override", 0, "Allow directory index file overrides", TYPE_FLAG,
	 "If this variable is set, you can get a listing of all files "
	 "in a directory by prepending '.' or '/' to the directory name, like this: "
	 "<a href=http://roxen.com//>http://roxen.com//</a>"
	 ". It is _very_ useful for debugging, but some people regard it as a "
	 "security hole.");
  
  defvar("size", 1, "Include file size", TYPE_FLAG,
	 "If set, include the size of the file in the listing.");
}

string quote_plain_text(string s)
{
  return(replace(s, ({"<",">","&"}),({"&lt;","&gt;","&amp;"})));
}

string tag_rel(string tag_name, mapping args, string contents,
	       object request_id, mapping defines)
{
  string old_base;
  string res;

  if (request_id->misc->rel_base) {
    old_base = request_id->misc->rel_base;
  } else {
    old_base = "";
  }
  request_id->misc->rel_base = old_base + args->base;
  
  res = parse_rxml(contents, request_id);

  request_id->misc->rel_base = old_base;
  return(res);
}

string tag_arel(string tag_name, mapping args, string contents,
		object request_id, mapping defines)
{
  if (request_id->misc->rel_base) {
    args->href = request_id->misc->rel_base+args->href;
  }

  return(make_tag("a", args)+contents+"</a>");
}

string tag_insert_quoted(string tag_name, mapping args, object request_id,
			 mapping defines)
{
  if (args->file) {
    string s = roxen->try_get_file(args->file, request_id);

    if (s) {
      return(quote_plain_text(s));
    }
    return("<!-- Couldn't open file \""+args->file+"\" -->");
  }
  return("<!-- File not specified -->");
}

mapping query_container_callers()
{
  return( ([ "rel":tag_rel, "arel":tag_arel ]) );
}

mapping query_tag_callers()
{
  return( ([ "insert-quoted":tag_insert_quoted ]) );
}

string find_readme(string d, object id)
{
  foreach(({ "README.html", "README"}), string f) {
    string readme = roxen->try_get_file(d+f, id);

    if (readme) {
      if (f[strlen(f)-5..] != ".html") {
	readme = "<pre>" + quote_plain_text(readme) +"</pre>";
      }
      return("<hr noshade>"+readme);
    }
  }
  return("");
}

string describe_directory(string d, object id)
{
  array(string) path = d/"/" - ({ "" });
  array(string) dir;
  int override = (path[-1] == ".");
  string result = "";

  // werror(sprintf("describe_directory(%s)\n", d));
  
  path -= ({ "." });
  d = "/"+path*"/" + "/";

  dir = roxen->find_dir(d, id);

  if (!id->misc->dir_no_head) {
    id->misc->dir_no_head = 1;

    result += "<h1>Directory listing of "+d+"</h1>\n<p>";

    if (QUERY(readme)) {
      result += find_readme(d, id);
    }
    result += "<hr noshade>\n";
  }
  result += "<pre><fl folded>\n";

  if (dir && sizeof(dir)) {
    foreach(sort(dir), string file) {
      array stats = roxen->stat_file(d + file, id);
      string type = "Unknown";
      string icon;
      int len = stats?stats[1]:0;
	
      // werror(sprintf("stat_file(\"%s\")=>%O\n", d+file, stats));

      switch(-len) {
      case 3:
      case 2:
	type = "   "+({ 0,0,"Directory","Module location" })[-stats[1]];

	/* Directory or module */
	file += "/";
	icon = "internal-gopher-menu";

	break;
      default:
	array tmp = roxen->type_from_filename(file,1);
	if (tmp) {
	  type = tmp[0];
	}
	icon = image_from_type(type);
	if (tmp && tmp[1]) {
	  type += " " + tmp[1];
	}

	break;
      }
      result += sprintf("<ft><img border=0 src=\"%s\" alt=\"\"> "
			"<arel href=\"%s\">%-40s</arel> %8s %-20s\n",
			icon, file, file, sizetostring(len), type);

      array(string) split_type = type/"/";
      string extras = "Not supported for this file type";

      switch(split_type[0]) {
      case "text":
	if (sizeof(split_type) > 1) {
	  switch(split_type[1]) {
	  case "html":
	    extras = "</pre>\n<insert file=\""+d+file+"\"><pre>";
	    break;
	  case "plain":
	    extras = "<insert-quoted file=\""+d+file+"\">";
	    break;
	  }
	}
	break;
      case "application":
	if (sizeof(split_type) > 1) {
	  switch(split_type[1]) {
	  case "x-include-file":
	  case "x-c-code":
	    extras = "<insert-quoted file=\""+d+file+"\">";
	    break;
	  }
	}
	break;
      case "image":
	extras = "<img src=\""+d+file+"\" border=0>";
	break;
      case "   Directory":
      case "   Module location":
	extras = "<rel base=\""+file+"\">"
	  "<insert nocache file=\""+d+file+".\"></rel>";
	break;
      case "Unknown":
	switch(lower_case(file)) {
	case ".cvsignore":
	case "configure":
	case "configure.in":
	case "bugs":
	case "copying":
	case "copyright":
	case "changelog":
	case "disclaimer":
	case "makefile":
	case "makefile.in":
	case "readme":
	  extras = "<insert-quoted file=\""+d+file+"\">";
	  break;
	}
	break;
      }
      result += "<fd>"+extras+"\n";
    }
  }
  result += "</fl></pre>\n";

  // werror(sprintf("describe_directory()=>\"%s\"\n", result));

  return(result);
}

string|mapping parse_directory(object id)
{
  string f = id->not_query;

  // werror(sprintf("parse_directory(%s)\n", id->raw_url));

  /* First fix the URL
   *
   * It must end with "/" or "/."
   */
  if (!(((sizeof(f) > 1) && ((f[-1] == '/') ||
			     ((f[-2] == '/') && (f[-1] == '.')))) ||
	(f == "/"))) {
    return(http_redirect(f + "/", id));
  }
  /* If the pathname ends with '.', and the 'override' variable
   * is set, a directory listing should be sent instead of the
   * indexfile.
   */
  if(!(sizeof(f)>1 && f[-2]=='/' && f[-1]=='.' && QUERY(override))) {
    /* Handle indexfiles */
    string file, old_file;
    string old_not_query;
    mapping got;
    old_file = old_not_query = id->not_query;
    if(old_file[-1]=='.') old_file = old_file[..strlen(old_file)-2];
    foreach(query("indexfiles")-({""}), file) { // Make recursion impossible
      id->not_query = old_file+file;
      if(got = roxen->get_file(id))
	return got;
    }
    id->not_query = old_not_query;
  }
  if (f[-1] != '.') {
    return(http_redirect(f+".",id));
  }
  
  return http_string_answer(parse_rxml(describe_directory(f, id), id));
}
