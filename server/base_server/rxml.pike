// The Roxen RXML Parser. See also the RXML Pike modules.
// Copyright � 1996 - 2000, Roxen IS.
//
// Per Hedbor, Henrik Grubbstr�m, Pontus Hagland, David Hedbor and others.
// New parser by Martin Stjernholm
// New RXML, scopes and entities by Martin Nilsson
//
// $Id: rxml.pike,v 1.265 2000/12/11 03:24:35 nilsson Exp $


inherit "rxmlhelp";
#include <request_trace.h>
#include <config.h>

#ifndef manual
#define _stat defines[" _stat"]
#define _error defines[" _error"]
#define _extra_heads defines[" _extra_heads"]
#define _rettext defines[" _rettext"]
#define _ok     defines[" _ok"]

// ----------------------- Error handling -------------------------

function _run_error;
string handle_run_error (RXML.Backtrace err, RXML.Type type)
// This is used to report thrown RXML run errors. See
// RXML.run_error().
{
  RequestID id=RXML.get_context()->id;
#ifdef MODULE_DEBUG
  report_notice ("Error in %s.\n%s", id->raw_url, describe_error (err));
#endif
  if(id->conf->get_provider("RXMLRunError")) {
    if(!_run_error)
      _run_error=id->conf->get_provider("RXMLRunError")->rxml_run_error;
    string res=_run_error(err, type, id);
    if(res) return res;
  }
  else
    _run_error=0;
  NOCACHE();
  id->misc->defines[" _ok"]=0;
  if (type->subtype_of (RXML.t_html) || type->subtype_of (RXML.t_xml))
    return "<br clear=\"all\" />\n<pre>" +
      Roxen.html_encode_string (describe_error (err)) + "</pre>\n";
  return describe_error (err);
}

function _parse_error;
string handle_parse_error (RXML.Backtrace err, RXML.Type type)
// This is used to report thrown RXML parse errors. See
// RXML.parse_error().
{
  RequestID id=RXML.get_context()->id;
#ifdef MODULE_DEBUG
  report_notice ("Error in %s.\n%s", id->raw_url, describe_error (err));
#endif
  if(id->conf->get_provider("RXMLParseError")) {
    if(!_parse_error)
      _parse_error=id->conf->get_provider("RXMLParseError")->rxml_parse_error;
    string res=_parse_error(err, type, id);
    if(res) return res;
  }
  else
    _parse_error=0;
  NOCACHE();
  id->misc->defines[" _ok"]=0;
  if (type->subtype_of (RXML.t_html) || type->subtype_of (RXML.t_xml))
    return "<br clear=\"all\" />\n<pre>" +
      Roxen.html_encode_string (describe_error (err)) + "</pre>\n";
  return describe_error (err);
}

#ifdef OLD_RXML_COMPAT
RoxenModule rxml_warning_cache;
void old_rxml_warning(RequestID id, string no, string yes) {
  if(!rxml_warning_cache) rxml_warning_cache=id->conf->get_provider("oldRXMLwarning");
  if(!rxml_warning_cache) return;
  rxml_warning_cache->old_rxml_warning(id, no, yes);
}
#endif


// ------------------------- RXML Parser ------------------------------

RXML.TagSet rxml_tag_set = class
// This tag set always has the highest priority.
{
  inherit RXML.TagSet;

  string prefix = RXML_NAMESPACE;

#ifdef THREADS
  Thread.Mutex lists_mutex = Thread.Mutex();
  // Locks destructive changes to the arrays modules and imported.
#endif

  array(RoxenModule) modules;
  // Each element in the imported array is the registered tag set of a
  // parser module. This array contains the corresponding module
  // object.

  void sort_on_priority()
  {
#ifdef THREADS
    Thread.MutexKey lock = lists_mutex->lock();
#endif
    int i = search (imported, Roxen.entities_tag_set);
    array(RXML.TagSet) new_imported = imported[..i-1] + imported[i+1..];
    array(RoxenModule) new_modules = modules[..i-1] + modules[i+1..];
    array(int) priorities = new_modules->query ("_priority", 1);
    priorities = replace (priorities, 0, 4);
    sort (priorities, new_imported, new_modules);
    new_imported = reverse (new_imported) + ({imported[i]});
    if (equal (imported, new_imported)) return;
    new_modules = reverse (new_modules) + ({modules[i]});
    `->= ("imported", new_imported);
    modules = new_modules;
  }

  mixed `->= (string var, mixed val)
  // Currently necessary due to misfeature in Pike.
  {
    if (var == "modules") modules = val;
    else ::`->= (var, val);
    return val;
  }

  void create (object rxml_object)
  {
    ::create ("rxml_tag_set");

    // Fix a better name later when we know the name of the
    // configuration.
    call_out (lambda () {
		string cname = sprintf ("%O", rxml_object);
		if (sscanf (cname, "Configuration(%s", cname) == 1 &&
		    sizeof (cname) && cname[-1] == ')')
		  cname = cname[..sizeof (cname) - 2];
		name = sprintf ("rxml_tag_set,%s", cname);
	      }, 0);

    imported = ({Roxen.entities_tag_set});
    modules = ({rxml_object});
  }
} (this_object());

RXML.Type default_content_type = RXML.t_html (RXML.PXml);
RXML.Type default_arg_type = RXML.t_text (RXML.PEnt);

int old_rxml_compat;

// A note on tag overriding: It's possible for old style tags to
// propagate their results to the tags they have overridden (new style
// tags can use RXML.Frame.propagate_tag()). This is done by an
// extension to the return value:
//
// If an array of the form
//
// ({int 1, string name, mapping(string:string) args, void|string content})
//
// is returned, the tag function with the given name is called with
// these arguments. If the name is the same as the current tag, the
// overridden tag function is called. If there's no overridden
// function, the tag is generated in the output. Any argument may be
// left out to default to its value in the current tag. ({1,�0,�0}) or
// ({1,�0,�0,�0}) may be shortened to ({1}).
//
// Note that there's no other way to handle tag overriding -- the page
// is no longer parsed multiple times.

string parse_rxml(string what, RequestID id,
		  void|Stdio.File file,
		  void|mapping defines )
// Note: Don't use this function to do recursive parsing inside an
// rxml parse session. The RXML module provides several different ways
// to accomplish that.
{
  id->misc->_rxml_recurse++;
#ifdef RXML_DEBUG
  werror("parse_rxml( "+strlen(what)+" ) -> ");
  int time = gethrtime();
#endif
  if(!defines)
    defines = id->misc->defines||([]);
  if(!_error)
    _error=200;
  if(!_extra_heads)
    _extra_heads=([ ]);
  if(!_stat) {
    if(id->misc->stat)
      _stat=id->misc->stat;
    else if(file)
      _stat=file->stat();
  }

  id->misc->defines = defines;

  RXML.PXml parent_parser = id->misc->_parser; // Don't count on that this exists.
  RXML.PXml parser;
  RXML.Context ctx;

  if (parent_parser && (ctx = parent_parser->context) && ctx->id == id) {
    parser = default_content_type->get_parser (ctx, 0, parent_parser);
    parser->recover_errors = parent_parser->recover_errors;
  }
  else {
    parser = rxml_tag_set (default_content_type, id);
    parser->recover_errors = 1;
    parent_parser = 0;
#ifdef OLD_RXML_COMPAT
    if (old_rxml_compat) parser->context->compatible_scope = 1;
#endif
  }
  id->misc->_parser = parser;

  // Hmm, how does this propagation differ from id->misc? Does it
  // matter? This is only used by the compatibility code for old style
  // tags.
  parser->_defines = defines;
  parser->_source_file = file;

  if (mixed err = catch {
    if (parent_parser && ctx == RXML.get_context())
      parser->finish (what);
    else
      parser->write_end (what);
    what = parser->eval();
    parser->_defines = 0;
    id->misc->_parser = parent_parser;
  }) {
#ifdef DEBUG
    if (!parser) {
      werror("RXML: Parser destructed!\n");
#if constant(_describe)
      _describe(parser);
#endif /* constant(_describe) */
      error("Parser destructed!\n");
    }
#endif
    parser->_defines = 0;
    id->misc->_parser = parent_parser;
    if (objectp (err) && err->thrown_at_unwind)
      error ("Can't handle RXML parser unwinding in "
	     "compatibility mode (error=%O).\n", err);
    else throw (err);
  }

  if(sizeof(_extra_heads) && !id->misc->moreheads)
  {
    id->misc->moreheads= ([]);
    id->misc->moreheads |= _extra_heads;
  }
  id->misc->_rxml_recurse--;
#ifdef RXML_DEBUG
  werror("%d (%3.3fs)\n%s", strlen(what),(gethrtime()-time)/1000000.0,
	 ("  "*id->misc->_rxml_recurse));
#endif
  return what;
}

#define COMPAT_TAG_TYPE \
  function(string,mapping(string:string),RequestID,void|Stdio.File,void|mapping: \
	   string|array(int|string))

#define COMPAT_CONTAINER_TYPE \
  function(string,mapping(string:string),string,RequestID,void|Stdio.File,void|mapping: \
	   string|array(int|string))

class CompatTag
{
  inherit RXML.Tag;

  string name;
  int flags;
  string|COMPAT_TAG_TYPE|COMPAT_CONTAINER_TYPE fn;

  RXML.Type content_type = RXML.t_same; // No preparsing.
  array(RXML.Type) result_types =
    ({RXML.t_xml (RXML.PXml), RXML.t_html (RXML.PXml)}); // Postparsing.

  void create (string _name, int empty, string|COMPAT_TAG_TYPE|COMPAT_CONTAINER_TYPE _fn)
  {
    name = _name, fn = _fn;
    flags = empty && RXML.FLAG_EMPTY_ELEMENT;
  }

  class Frame
  {
    inherit RXML.Frame;
    string raw_tag_text;

    array do_enter (RequestID id)
    {
      if (args->preparse)
	content_type = content_type (RXML.PXml);
    }

    array do_return (RequestID id)
    {
      id->misc->line = "0";	// No working system for this yet.

      if (stringp (fn)) return ({fn});
      if (!fn) {
	result_type = result_type (RXML.PNone);
	return ({propagate_tag()});
      }

      Stdio.File source_file;
      mapping defines;
      if (id->misc->_parser) {
	source_file = id->misc->_parser->_source_file;
	defines = id->misc->_parser->_defines;
      }

      string|array(string) result;
      if (flags & RXML.FLAG_EMPTY_ELEMENT)
	result = fn (name, args, id, source_file, defines);
      else {
	if(args->trimwhites) content = String.trim_all_whites(content);
	result = fn (name, args, content, id, source_file, defines);
      }

      if (arrayp (result)) {
	result_type = result_type (RXML.PNone);
	if (sizeof (result) && result[0] == 1) {
	  [string pname, mapping(string:string) pargs, string pcontent] =
	    (result[1..] + ({0, 0, 0}))[..2];
	  if (!pname || pname == name)
	    return ({!pargs && !pcontent ? propagate_tag () :
		     propagate_tag (pargs || args, pcontent || content)});
	  else
	    return ({RXML.make_unparsed_tag (pname, pargs || args, pcontent || content)});
	}
	else return result;
      }
      else if (result) {
	if (args->noparse) result_type = result_type (RXML.PNone);
	return ({result});
      }
      else {
	result_type = result_type (RXML.PNone);
	return ({propagate_tag()});
      }
    }
  }
}

class GenericTag {
  inherit RXML.Tag;
  constant is_generic_tag=1;
  string name;
  int flags;

  function(string,mapping(string:string),string,RequestID,RXML.Frame:
	   array|string) _do_return;

  void create(string _name, int _flags,
	      function(string,mapping(string:string),string,RequestID,RXML.Frame:
		       array|string) __do_return) {
    name=_name;
    flags=_flags;
    _do_return=__do_return;
    if(flags&RXML.FLAG_DONT_PREPARSE)
      content_type = RXML.t_same;
  }

  class Frame {
    inherit RXML.Frame;

    array do_return(RequestID id, void|mixed piece) {
      // Note: args may be zero here since this function is inherited
      // by GenericPITag.
      if (flags & RXML.FLAG_POSTPARSE)
	result_type = result_type (RXML.PXml);
      if (!(flags & RXML.FLAG_STREAM_CONTENT))
	piece = content || "";
      array|string res = _do_return(name, args, piece, id, this_object());
      return stringp (res) ? ({res}) : res;
    }
  }
}

class GenericPITag
{
  inherit GenericTag;

  void create (string _name, int _flags,
	       function(string,mapping(string:string),string,RequestID,RXML.Frame:
			array|string) __do_return)
  {
    ::create (_name, _flags | RXML.FLAG_PROC_INSTR, __do_return);
    content_type = RXML.t_text;
    // The content is always treated literally;
    // RXML.FLAG_DONT_PREPARSE has no effect.
  }
}

void add_parse_module (RoxenModule mod)
{
  RXML.TagSet tag_set =
    mod->query_tag_set ? mod->query_tag_set() : RXML.TagSet (mod->module_identifier());
  mapping(string:mixed) defs;

  if (mod->query_tag_callers &&
      mappingp (defs = mod->query_tag_callers()) &&
      sizeof (defs))
    tag_set->add_tags (map (indices (defs),
			    lambda (string name) {
			      return CompatTag (name, 1, defs[name]);
			    }));

  if (mod->query_container_callers &&
      mappingp (defs = mod->query_container_callers()) &&
      sizeof (defs))
    tag_set->add_tags (map (indices (defs),
			    lambda (string name) {
			      return CompatTag (name, 0, defs[name]);
			    }));

  if (mod->query_simpletag_callers &&
      mappingp (defs = mod->query_simpletag_callers()) &&
      sizeof (defs))
    tag_set->add_tags(Array.map(indices(defs),
				lambda(string tag){ return GenericTag(tag, @defs[tag]); }));

  if (mod->query_simple_pi_tag_callers &&
      mappingp (defs = mod->query_simple_pi_tag_callers()) &&
      sizeof (defs))
    tag_set->add_tags (map (indices (defs),
			    lambda (string name) {
			      return GenericPITag (name, @defs[name]);
			    }));

  if (search (rxml_tag_set->imported, tag_set) < 0) {
#ifdef THREADS
    Thread.MutexKey lock = rxml_tag_set->lists_mutex->lock();
#endif
    rxml_tag_set->modules += ({mod});
    rxml_tag_set->imported += ({tag_set});
#ifdef THREADS
    lock = 0;
#endif
    remove_call_out (rxml_tag_set->sort_on_priority);
    call_out (rxml_tag_set->sort_on_priority, 0);
  }
}

void remove_parse_module (RoxenModule mod)
{
  int i = search (rxml_tag_set->modules, mod);
  if (i >= 0) {
    RXML.TagSet tag_set = rxml_tag_set->imported[i];
    rxml_tag_set->modules =
      rxml_tag_set->modules[..i - 1] + rxml_tag_set->modules[i + 1..];
    rxml_tag_set->imported =
      rxml_tag_set->imported[..i - 1] + rxml_tag_set->imported[i + 1..];
    if (tag_set) destruct (tag_set);
  }
}

void ready_to_receive_requests (object this)
{
  remove_call_out (rxml_tag_set->sort_on_priority);
  rxml_tag_set->sort_on_priority();
}


// ------------------------- RXML Core tags --------------------------

class TagHelp {
  inherit RXML.Tag;
  constant name = "help";
  constant flags = RXML.FLAG_EMPTY_ELEMENT;

  class Frame {
    inherit RXML.Frame;

    array do_return(RequestID id) {
      array tags=map(indices(RXML.get_context()->tag_set->get_tag_names()),
		     lambda(string tag) {
		       if(tag[..3]=="!--#" || !has_value(tag, "#"))
			 return tag;
		       return "";
		     } ) - ({ "" });
      tags += map(indices(RXML.get_context()->tag_set->get_proc_instr_names()),
		  lambda(string tag) { return "&lt;?"+tag+"?&gt;"; } );
      tags = Array.sort_array(tags,
			      lambda(string a, string b) {
				if(a[..4]=="&lt;?") a=a[5..];
				if(b[..4]=="&lt;?") b=b[5..];
				if(lower_case(a)==lower_case(b)) return a>b;
				return lower_case(a)>lower_case(b); })-({"\x266a"});
      string help_for = args->for || id->variables->_r_t_h;
      string ret="<h2>Roxen Interactive RXML Help</h2>";

      if(!help_for) {
	string char;
	ret += "<b>Here is a list of all defined tags. Click on the name to "
	  "receive more detailed information. All these tags are also availabe "
	  "in the \""+RXML_NAMESPACE+"\" namespace.</b><p>\n";
	array tag_links;

	foreach(tags, string tag) {
	  if(tag[0]!='&' && lower_case(tag[0..0])!=char) {
	    if(tag_links && char!="/") ret+="<h3>"+upper_case(char)+"</h3>\n<p>"+
					 String.implode_nicely(tag_links)+"</p>";
	    char=lower_case(tag[0..0]);
	    tag_links=({});
	  }
	  if (tag[0]=='&' && lower_case(tag[5..5])!=char) {
	    if(tag_links && char!="/") ret+="<h3>"+upper_case(char)+"</h3>\n<p>"+
					 String.implode_nicely(tag_links)+"</p>";
	    char=lower_case(tag[5..5]);
	    tag_links=({});
	  }
	  if(tag[0..sizeof(RXML_NAMESPACE)]!=RXML_NAMESPACE+":") {
	    string enc=tag;
	    if(enc[0..4]=="&lt;?") enc="<?"+enc[5..sizeof(enc)-6];
	    if(undocumented_tags && undocumented_tags[tag])
	      tag_links += ({ tag });
	    else
	      tag_links += ({ sprintf("<a href=\"%s?_r_t_h=%s\">%s</a>\n",
				      id->not_query, Roxen.http_encode_url(enc), tag) });
	    }
	}

	ret+="<h3>"+upper_case(char)+"</h3>\n<p>"+String.implode_nicely(tag_links)+"</p>";
	/*
	ret+="<p><b>This is a list of all currently defined RXML scopes and their entities</b></p>";

	RXML.Context context=RXML.get_context();
	foreach(sort(context->list_scopes()), string scope) {
	  ret+=sprintf("<h3><a href=\"%s?_r_t_h=%s\">%s</a></h3>\n",
		       id->not_query, Roxen.http_encode_url("&"+scope+";"), scope);
	  ret+="<p>"+String.implode_nicely(Array.map(sort(context->list_var(scope)),
						       lambda(string ent) { return ent; }) )+"</p>";
	}
	*/
	return ({ ret });
      }

      result=ret+find_tag_doc(help_for, id);
    }
  }
}

class TagNumber {
  inherit RXML.Tag;
  constant name = "number";
  constant flags = RXML.FLAG_EMPTY_ELEMENT;

  class Frame {
    inherit RXML.Frame;
    array do_return(RequestID id) {
      if(args->type=="roman") return ({ Roxen.int2roman((int)args->num) });
      if(args->type=="memory") return ({ Roxen.sizetostring((int)args->num) });
      result=roxen.language(args->lang||args->language||
                            id->misc->defines->theme_language,
			    args->type||"number",id)( (int)args->num );
    }
  }
}

private array(string) list_packages()
{
  return filter(((get_dir("../local/rxml_packages")||({}))
                 |(get_dir("rxml_packages")||({}))),
                lambda( string s ) {
                  return (Stdio.file_size("../local/rxml_packages/"+s)+
                          Stdio.file_size( "rxml_packages/"+s )) > 0;
                });

}

private string read_package( string p )
{
  string data;
  p = combine_path("/", p);
  if(file_stat( "../local/rxml_packages/"+p ))
    catch(data=Stdio.File( "../local/rxml_packages/"+p, "r" )->read());
  if(!data && file_stat( "rxml_packages/"+p ))
    catch(data=Stdio.File( "rxml_packages/"+p, "r" )->read());
  return data;
}

private string use_file_doc(string f, string data)
{
  string res="", doc="";
  int help=0; /* If true, all tags support the 'help' argument. */
  sscanf(data, "%*sdoc=\"%s\"", doc);
  sscanf(data, "%*shelp=%d", help);
  res += "<dt><b>"+f+"</b></dt><dd>"+(doc?doc+"<br />":"")+"</dd>";

  mapping d=(["tag":({}),
	      "container":({}),
	      "if":({}),
	      "variable":({}) ]);

  parse_html(data, ([]), (["define":
			   lambda(string t, mapping m, string c) {
			     foreach(indices(d), string type)
			       if(m[type]) d[type]+=({m[type]});
			     return "";
			   },
			   "undefine":
			   lambda(string t, mapping m, string c) {
			     foreach(indices(d), string type)
			       if(m[type]) d[type]+=({m[type]});
			     return "";
			   } ]) );

  foreach(indices(d), string type) {
    array ind=d[type];
    if(sizeof(ind))
      res += "defines the following tag"+
	(sizeof(ind)!=1?"s":"") +": "+
	String.implode_nicely( sort(ind) )+"<br />";
  }

  if(help) res+="<br /><br />All tags accept the <i>help</i> attribute.";

  return res;
}

class TagUse {
  inherit RXML.Tag;
  constant name = "use";
  constant flags = RXML.FLAG_EMPTY_ELEMENT;

  class Frame {
    inherit RXML.Frame;

    array do_return(RequestID id) {
      if(args->packageinfo) {
	NOCACHE();
	string res ="<dl>";
	foreach(list_packages(), string f)
	  res += use_file_doc(f, read_package( f ));
	return ({ res+"</dl>" });
      }

      if(!args->file && !args->package)
	parse_error("No file or package selected.\n");


      array res;
      if(!id->misc->_ifs) id->misc->_ifs=([]);
      string name, filename;
      if(args->file)
      {
	filename = Roxen.fix_relative(args->file, id);
	name = id->conf->get_config_id() + "|" + filename;
      }
      else
	name = "|" + args->package;
      RXML.Context ctx = RXML.get_context();

      if(args->info || id->pragma["no-cache"] ||
	 !(res=cache_lookup("macrofiles",name)) ) {
	res = ({ ([]), ({}) });

	string file;
	if(filename)
	  file = try_get_file( filename, id );
	else
	  file = read_package( args->package );

	if(!file)
	  run_error("Failed to fetch "+(args->file||args->package)+".\n");

	if( args->info )
	  return ({"<dl>"+use_file_doc( args->file || args->package, file )+"</dl>"});

	multiset before=ctx->get_runtime_tags();
	mapping before_ifs = mkmapping(indices(id->misc->_ifs),
				       indices(id->misc->_ifs));
	parse_rxml( file, id );

	res[0] = id->misc->_ifs - before_ifs;
	res[1]=indices(RXML.get_context()->get_runtime_tags()-before);
	cache_set("macrofiles", name, res);
      }

      id->misc->_ifs += res[0];
      foreach(res[1], RXML.Tag tag)
	ctx->add_runtime_tag(tag);

      return 0;
    }
  }
}

class UserTagContents
{
  inherit RXML.Tag;
  constant name = "contents";
  constant flags = RXML.FLAG_EMPTY_ELEMENT;
  array(RXML.Type) result_types = ({RXML.t_any (RXML.PXml)});

  class Frame
  {
    inherit RXML.Frame;
    RXML.Frame user_tag_up;
    array do_return()
    {
      RXML.Frame frame = up;
      while (frame && !frame->user_tag_contents)
	frame = frame->user_tag_up || frame->up;
      if (!frame) parse_error ("No contents to insert.\n");
      user_tag_up = frame->up;
      return ({frame->user_tag_contents});
    }
  }
}

RXML.TagSet user_tag_contents_tag_set =
  RXML.TagSet ("user_tag_contents", ({UserTagContents()}));

class UserTag {
  inherit RXML.Tag;
  string name;
  int flags = 0;
  RXML.Type content_type = RXML.t_same;
  array(RXML.Type) result_types = ({ RXML.t_any(RXML.PXml) });

  string c;
  mapping defaults;
  string scope;

  void create(string _name, string _c, mapping _defaults,
	      int tag, void|string scope_name) {
    name=_name;
    c=_c;
    defaults=_defaults;
    if(tag) flags=RXML.FLAG_EMPTY_ELEMENT;
    scope=scope_name;
  }

  class Frame {
    inherit RXML.Frame;
    RXML.TagSet additional_tags = user_tag_contents_tag_set;
    mapping vars;
    string scope_name;
    string user_tag_contents;

    array do_return(RequestID id) {
      mapping nargs=defaults+args;
      id->misc->last_tag_args = nargs;
      scope_name=scope||name;
      vars = nargs;

      if(!(RXML.FLAG_EMPTY_ELEMENT&flags) && args->trimwhites)
	content=String.trim_all_whites(content);

#ifdef OLD_RXML_COMPAT
      if(old_rxml_compat) {
	array replace_from, replace_to;
	if (flags & RXML.FLAG_EMPTY_ELEMENT) {
	  replace_from = map(indices(nargs),Roxen.make_entity)+({"#args#"});
	  replace_to = values(nargs)+({ Roxen.make_tag_attributes(nargs)[1..] });
	}
	else {
	  replace_from = map(indices(nargs),Roxen.make_entity)+({"#args#", "<contents>"});
	  replace_to = values(nargs)+({ Roxen.make_tag_attributes(nargs)[1..], content });
	}
	string c2;
	c2 = replace(c, replace_from, replace_to);
	if(c2!=c) {
	  vars=([]);
	  return ({c2});
	}
      }
#endif

      vars->args = Roxen.make_tag_attributes(nargs)[1..];
      vars["rest-args"] = Roxen.make_tag_attributes(args - defaults)[1..];
      user_tag_contents = vars->contents = content;
      return ({ c });
    }
  }
}

class TagDefine {
  inherit RXML.Tag;
  constant name = "define";
  constant flags = RXML.FLAG_DONT_REPORT_ERRORS;

  class Frame {
    inherit RXML.Frame;

    array do_enter(RequestID id) {
      if(args->preparse)
	m_delete(args, "preparse");
      else
	content_type = RXML.t_xml;
      return 0;
    }

    array do_return(RequestID id) {
      result = "";
      string n;

      if(n=args->variable) {
	if(args->trimwhites) content=String.trim_all_whites(content);
	RXML.user_set_var(n, content, args->scope);
	return 0;
      }

      if (n=args->tag||args->container) {
#ifdef OLD_RXML_COMPAT
	n = old_rxml_compat?lower_case(n):n;
#endif
	int tag=0;
	if(args->tag) {
	  tag=1;
	  m_delete(args, "tag");
	} else
	  m_delete(args, "container");

	mapping defaults=([]);

#ifdef OLD_RXML_COMPAT
	if(old_rxml_compat)
	  foreach( indices(args), string arg )
	    if( arg[..7] == "default_" )
	      {
		defaults[arg[8..]] = args[arg];
		old_rxml_warning(id, "define attribute "+arg,"attrib container");
		m_delete( args, arg );
	      }
#endif
	content=parse_html(content||"",([]),
			   (["attrib":
			     lambda(string tag, mapping m, string cont) {
			       if(m->name) defaults[m->name]=parse_rxml(cont,id);
			       return "";
			     }
			   ]));

	if(args->trimwhites) {
	  content=String.trim_all_whites(content);
	  m_delete (args, "trimwhites");
	}

#ifdef OLD_RXML_COMPAT
	if(old_rxml_compat) content = replace( content, indices(args), values(args) );
#endif

	RXML.get_context()->add_runtime_tag(UserTag(n, content, defaults,
						    tag, args->scope));
	return 0;
      }

      if (n=args->if) {
	if(!id->misc->_ifs) id->misc->_ifs=([]);
	id->misc->_ifs[args->if]=UserIf(args->if, content);
	return 0;
      }

#ifdef OLD_RXML_COMPAT
      if (n=args->name) {
	id->misc->defines[n]=content;
	old_rxml_warning(id, "attempt to define name ","variable");
	return 0;
      }
#endif

      parse_error("No tag, variable, if or container specified.\n");
    }
  }
}

class TagUndefine {
  inherit RXML.Tag;
  int flags = RXML.FLAG_EMPTY_ELEMENT;
  constant name = "undefine";
  class Frame {
    inherit RXML.Frame;
    array do_enter(RequestID id) {
      string n;

      if(n=args->variable) {
	RXML.get_context()->user_delete_var(n, args->scope);
	return 0;
      }

      if (n=args->tag||args->container) {
	RXML.get_context()->remove_runtime_tag(n);
	return 0;
      }

      if (n=args->if) {
	m_delete(id->misc->_ifs, n);
	return 0;
      }

#ifdef OLD_RXML_COMPAT
      if (n=args->name) {
	m_delete(id->misc->defines, args->name);
	return 0;
      }
#endif

      parse_error("No tag, variable, if or container specified.\n");
    }
  }
}

class Tracer
{
  // Note: \n is used sparingly in output to make it look nice even
  // inside <pre>.
  string resolv="<ol>";
  int level;

  string _sprintf()
  {
    return "Tracer()";
  }

#if constant (gethrtime)
  mapping et = ([]);
#endif
#if constant (gethrvtime)
  mapping et2 = ([]);
#endif

  local void start_clock()
  {
#if constant (gethrvtime)
    et2[level] = gethrvtime();
#endif
#if constant (gethrtime)
    et[level] = gethrtime();
#endif
  }

  local string stop_clock()
  {
    string res;
#if constant (gethrtime)
    res = sprintf("%.5f", (gethrtime() - et[level])/1000000.0);
#else
    res = "";
#endif
#if constant (gethrvtime)
    res += sprintf(" (CPU = %.2f)", (gethrvtime() - et2[level])/1000000.0);
#endif
    return res;
  }

  void trace_enter_ol(string type, function|object thing)
  {
    level++;

    if (thing) {
      string name = Roxen.get_modfullname (Roxen.get_owning_module (thing));
      if (name)
	name = "module " + name;
      else if (this_program conf = Roxen.get_owning_config (thing))
	name = "configuration " + Roxen.html_encode_string (conf->query_name());
      else
	name = Roxen.html_encode_string (sprintf ("object %O", thing));
      type += " in " + name;
    }

    string efont="", font="";
    if(level>2) {efont="</font>";font="<font size=-1>";}

    resolv += font + "<li><b>�</b> " + type + "<ol>" + efont;
    start_clock();
  }

  void trace_leave_ol(string desc)
  {
    level--;

    string efont="", font="";
    if(level>1) {efont="</font>";font="<font size=-1>";}

    resolv += "</ol>" + font;
    if (sizeof (desc))
      resolv += "<b>�</b> " + Roxen.html_encode_string(desc);
    string time = stop_clock();
    if (sizeof (time)) {
      if (sizeof (desc)) resolv += "<br />";
      resolv += "<i>Time: " + time + "</i>";
    }
    resolv += efont + "</li>\n";
  }

  string res()
  {
    while(level>0) trace_leave_ol("");
    return resolv + "</ol>";
  }
}

class TagTrace {
  inherit RXML.Tag;
  constant name = "trace";

  class Frame {
    inherit RXML.Frame;
    function a,b;
    Tracer t;

    array do_enter(RequestID id) {
      NOCACHE();
      //   if(args->summary)
      //     t = SumTracer();
      //   else
      t = Tracer();
      a = id->misc->trace_enter;
      b = id->misc->trace_leave;
      id->misc->trace_enter = t->trace_enter_ol;
      id->misc->trace_leave = t->trace_leave_ol;
      t->start_clock();
      return 0;
    }

    array do_return(RequestID id) {
      id->misc->trace_enter = a;
      id->misc->trace_leave = b;
      result = "<h3>Tracing</h3>" + content +
	"<h3>Trace report</h3>" + t->res();
      string time = t->stop_clock();
      if (sizeof (time))
	result += "<h3>Total time: " + time + "</h3>";
      return 0;
    }
  }
}

class TagNoParse {
  inherit RXML.Tag;
  constant name = "noparse";
  RXML.Type content_type = RXML.t_same;
  class Frame {
    inherit RXML.Frame;
  }
}

class TagPINoParse {
  inherit TagNoParse;
  constant flags = RXML.FLAG_PROC_INSTR;
}

class TagPICData
{
  inherit RXML.Tag;
  constant name = "cdata";
  constant flags = RXML.FLAG_PROC_INSTR;
  RXML.Type content_type = RXML.t_text;
  class Frame
  {
    inherit RXML.Frame;
  }
}

class TagEval {
  inherit RXML.Tag;
  constant name = "eval";
  array(RXML.Type) result_types = ({ RXML.t_any(RXML.PXml) });

  class Frame {
    inherit RXML.Frame;
    array do_return(RequestID id) {
      return ({ content });
    }
  }
}

class TagNoOutput {
  inherit RXML.Tag;
  constant name = "nooutput";
  constant flags = RXML.FLAG_DONT_REPORT_ERRORS;

  class Frame {
    inherit RXML.Frame;
    array do_process() {
      return ({""});
    }
  }
}

class TagStrLen {
  inherit RXML.Tag;
  constant name = "strlen";
  constant flags = RXML.FLAG_DONT_REPORT_ERRORS;

  class Frame {
    inherit RXML.Frame;
    array do_return() {
      if(!stringp(content)) {
	result="0";
	return 0;
      }
      result = (string)strlen(content);
    }
  }
}

class TagCase {
  inherit RXML.Tag;
  constant name = "case";

  static Parser.HTML lowercaser =
    lambda () {
      Parser.HTML p = Parser.HTML();
      p->_set_data_callback (
	lambda (Parser.HTML p, string data) {
	  return ({lower_case (data)});
	});
      p->_set_entity_callback (
	lambda (Parser.HTML p, string data) {
	  if (string char = Roxen.decode_charref (data))
	    return ({Roxen.encode_charref (lower_case (char))});
	  return 0;
	});
      return p;
    }();

  static Parser.HTML uppercaser =
    lambda () {
      Parser.HTML p = Parser.HTML();
      p->_set_data_callback (
	lambda (Parser.HTML p, string data) {
	  return ({upper_case (data)});
	});
      p->_set_entity_callback (
	lambda (Parser.HTML p, string data) {
	  if (string char = Roxen.decode_charref (data))
	    return ({Roxen.encode_charref (upper_case (char))});
	  return 0;
	});
      return p;
    }();

  static Parser.HTML capitalizer =
    lambda () {
      Parser.HTML p = Parser.HTML();
      p->_set_data_callback (
	lambda (Parser.HTML p, string data) {
	  p->_set_data_callback (0);
	  p->_set_entity_callback (0);
	  return ({String.capitalize (data)});
	});
      p->_set_entity_callback (
	lambda (Parser.HTML p, string data) {
	  p->_set_data_callback (0);
	  p->_set_entity_callback (0);
	  if (string char = Roxen.decode_charref (data))
	    return ({Roxen.encode_charref (upper_case (char))});
	  return 0;
	});
      return p;
    }();

  class Frame {
    inherit RXML.Frame;
    int cap=0;
    array do_process(RequestID id) {
      if(args->case)
	switch(lower_case(args->case)) {
	case "lower":
	  return ({content_type->encoding_type == "xml" ?
		   lowercaser->clone()->finish (content)->read() :
		   lower_case (content)});
	case "upper":
	  return ({content_type->encoding_type == "xml" ?
		   uppercaser->clone()->finish (content)->read() :
		   upper_case (content)});
	case "capitalize":
	  if(cap) return ({content});
	  if (sizeof (content)) cap=1;
	  return ({content_type->encoding_type == "xml" ?
		   capitalizer->clone()->finish (content)->read() :
		   String.capitalize (content)});
	}

#ifdef OLD_RXML_COMPAT
      if(args->lower) {
	content = lower_case(content);
	old_rxml_warning(id, "attribute lower","case=lower");
      }
      if(args->upper) {
	content = upper_case(content);
	old_rxml_warning(id, "attribute upper","case=upper");
      }
      if(args->capitalize){
	content = capitalize(content);
	old_rxml_warning(id, "attribute capitalize","case=capitalize");
      }
#endif
      return ({ content });
    }
  }
}

#define LAST_IF_TRUE id->misc->defines[" _ok"]

class FrameIf {
  inherit RXML.Frame;
  int do_iterate = -1;

  array do_enter(RequestID id) {
    int and = 1;

    if(args->not) {
      m_delete(args, "not");
      do_enter(id);
      do_iterate=do_iterate==1?-1:1;
      return 0;
    }

    if(args->or)  { and = 0; m_delete( args, "or" ); }
    if(args->and) { and = 1; m_delete( args, "and" ); }
    mapping plugins=get_plugins();
    if(id->misc->_ifs) plugins+=id->misc->_ifs;
    array possible = indices(args) & indices(plugins);

    int ifval=0;
    foreach(possible, string s) {
      ifval = plugins[ s ]->eval( args[s], id, args, and, s );
      if(ifval) {
	if(!and) {
	  do_iterate = 1;
	  return 0;
	}
      }
      else
	if(and)
	  return 0;
    }
    if(ifval) {
      do_iterate = 1;
      return 0;
    }
    return 0;
  }

  array do_return(RequestID id) {
    if(do_iterate==1) {
      LAST_IF_TRUE = 1;
      result = content;
    }
    else
      LAST_IF_TRUE = 0;
    return 0;
  }
}

class TagIf {
  inherit RXML.Tag;
  constant name = "if";
  constant flags = RXML.FLAG_SOCKET_TAG;
  program Frame = FrameIf;
}

class TagElse {
  inherit RXML.Tag;
  constant name = "else";
  constant flags = 0;
  class Frame {
    inherit RXML.Frame;
    int do_iterate=1;
    array do_enter(RequestID id) {
      if(LAST_IF_TRUE) do_iterate=-1;
      return 0;
    }
  }
}

class TagThen {
  inherit RXML.Tag;
  constant name = "then";
  constant flags = 0;
  class Frame {
    inherit RXML.Frame;
    int do_iterate=1;
    array do_enter(RequestID id) {
      if(!LAST_IF_TRUE) do_iterate=-1;
      return 0;
    }
  }
}

class TagElseif {
  inherit RXML.Tag;
  constant name = "elseif";

  class Frame {
    inherit FrameIf;
    int last;
    array do_enter(RequestID id) {
      last=LAST_IF_TRUE;
      if(last) return 0;
      return ::do_enter(id);
    }

    array do_return(RequestID id) {
      if(last) return 0;
      return ::do_return(id);
    }

    mapping(string:RXML.Tag) get_plugins() {
      return RXML.get_context()->tag_set->get_plugins ("if");
    }
  }
}

class TagTrue {
  inherit RXML.Tag;
  constant name = "true";
  constant flags = RXML.FLAG_EMPTY_ELEMENT;

  class Frame {
    inherit RXML.Frame;
    array do_enter(RequestID id) {
      LAST_IF_TRUE = 1;
    }
  }
}

class TagFalse {
  inherit RXML.Tag;
  constant name = "false";
  constant flags = RXML.FLAG_EMPTY_ELEMENT;
  class Frame {
    inherit RXML.Frame;
    array do_enter(RequestID id) {
      LAST_IF_TRUE = 0;
    }
  }
}

class TagCond
{
  inherit RXML.Tag;
  constant name = "cond";
  RXML.Type content_type = RXML.t_nil (RXML.PXml);
  array(RXML.Type) result_types = ({RXML.t_any});

  class TagCase
  {
    inherit RXML.Tag;
    constant name = "case";
    array(RXML.Type) result_types = ({RXML.t_nil});

    class Frame
    {
      inherit FrameIf;

      array do_enter (RequestID id)
      {
	if (up->result != RXML.Void) return 0;
	content_type = up->result_type (RXML.PXml);
	return ::do_enter (id);
      }

      array do_return (RequestID id)
      {
	::do_return (id);
	if (up->result != RXML.Void) return 0;
	up->result = result;
	result = RXML.Void;
	return 0;
      }

      // Must override this since it's used by FrameIf.
      mapping(string:RXML.Tag) get_plugins()
	{return RXML.get_context()->tag_set->get_plugins ("if");}
    }
  }

  class TagDefault
  {
    inherit RXML.Tag;
    constant name = "default";
    array(RXML.Type) result_types = ({RXML.t_nil});

    class Frame
    {
      inherit RXML.Frame;
      int do_iterate = 1;

      array do_enter()
      {
	if (up->result != RXML.Void) {
	  do_iterate = -1;
	  return 0;
	}
	content_type = up->result_type (RXML.PNone);
	return 0;
      }

      array do_return()
      {
	up->default_data = content;
	return 0;
      }
    }
  }

  RXML.TagSet cond_tags =
    RXML.TagSet ("TagCond.cond_tags", ({TagCase(), TagDefault()}));

  class Frame
  {
    inherit RXML.Frame;
    RXML.TagSet local_tags = cond_tags;
    string default_data;

    array do_return (RequestID id)
    {
      if (result == RXML.Void && default_data) {
	LAST_IF_TRUE = 0;
	return ({RXML.parse_frame (result_type (RXML.PXml), default_data)});
      }
      return 0;
    }
  }
}

class TagEmit {
  inherit RXML.Tag;
  constant name = "emit";
  constant flags = RXML.FLAG_SOCKET_TAG|RXML.FLAG_DONT_REPORT_ERRORS;
  mapping(string:RXML.Type) req_arg_types = (["source":RXML.t_text(RXML.PEnt)]);

  class TagDelimiter {
    inherit RXML.Tag;
    constant name = "delimiter";

    class Frame {
      inherit RXML.Frame;

      array do_return(RequestID id) {
	if( RXML.get_var("counter") < id->misc->emit_rowinfo )
	  result = content;
	return 0;
      }
    }
  }

  RXML.TagSet internal = RXML.TagSet("TagEmit.internal", ({ TagDelimiter() }) );

  // A slightly modified Array.dwim_sort_func
  // used as emits sort function.
  static int compare(string a0,string b0) {
    if (!a0) {
      if (b0)
	return -1;
      return 0;
    }

    if (!b0)
      return 1;

    string a2="",b2="";
    int a1,b1;
    sscanf(a0,"%s%d%s",a0,a1,a2);
    sscanf(b0,"%s%d%s",b0,b1,b2);
    if (a0>b0) return 1;
    if (a0<b0) return -1;
    if (a1>b1) return 1;
    if (a1<b1) return -1;
    if (a2==b2) return 0;
    return compare(a2,b2);
  }

  class Frame {
    inherit RXML.Frame;
    RXML.TagSet additional_tags = internal;
    string scope_name;
    mapping vars;

    int upper_size;
    object plugin;
    array(mapping(string:mixed))|function res;
    mapping filter;

    array do_enter(RequestID id) {
      if(!(plugin=get_plugins()[args->source]))
	parse_error("The emit source %O doesn't exist.\n", args->source);
      scope_name=args->scope||args->source;

      TRACE_ENTER("Fetch emit dataset for source "+args->source, 0);
      res=plugin->get_dataset(args, id);
      TRACE_LEAVE("");

      if(plugin->skiprows && args->skiprows)
	m_delete(args, "skiprows");
      if(plugin->maxrows && args->maxrows)
	m_delete(args, "maxrows");

      if(arrayp(res)) {
	vars = (["counter":0]);
	if(args->sort && !plugin->sort)
	{
	  array(string) order = (args->sort - " ")/"," - ({ "" });
	  res = Array.sort_array( res,
				  lambda (mapping(string:string) m1,
					  mapping(string:string) m2)
				  {
				    foreach (order, string field)
				    {
				      int tmp;
				      
				      if (field[0] == '-')
					tmp = compare( m2[field[1..]],
						       m1[field[1..]] );
				      else if (field[0] == '+')
					tmp = compare( m1[field[1..]],
						       m2[field[1..]] );
				      else
					tmp = compare( m1[field], m2[field] );

				      if (tmp == 1)
					return 1;
				      else if (tmp == -1)
					return 0;
				    }
				    return 0;
				  } );
	}
	
	if(args->filter) {
	  array pairs = args->filter / ",";
	  filter = ([]);
	  foreach( args->filter / ",", string pair) {
	    string v,g;
	    if( sscanf(pair, "%s=%s", v,g) != 2)
	      continue;
	    v = String.trim_whites(v);
	    if(g != "*"*sizeof(g))
	      filter[v] = g;
	  }

	  if(args->rowinfo) {
	    m_delete(args, "filter");
	    for(int i; i<sizeof(res); i++)
	      if(should_filter(res[i])) {
		res = res[..i-1] + res[i+1..];
		i--;
	      }
	  }
	  else {
	    args->skiprows = (int)args->skiprows;
	    vars->real_counter = 0;
	    do_iterate = array_filter_iterate;
	  }
	}

	if(!args->filter) {
	  if(args->skiprows) {
	    if(args->skiprows[0]=='-') args->skiprows=sizeof(res)-(int)args->skiprows-1;
	    res=res[(int)args->skiprows..];
	  }

	  if(args->remainderinfo)
	    RXML.user_set_var(args->remainderinfo, (int)args->maxrows?
			      max(sizeof(res)-(int)args->maxrows, 0): 0);

	  if(args->maxrows) res=res[..(int)args->maxrows-1];

	  if(args->rowinfo) RXML.user_set_var(args->rowinfo, sizeof(res));
	  if(args["do-once"] && sizeof(res)==0) res=({ ([]) });

	  if(id->misc->emit_rowinfo)
	    upper_size = id->misc->emit_rowinfo;
	  id->misc->emit_rowinfo = sizeof(res);

	  do_iterate = array_iterate;
	}

	if(sizeof(res))
	  LAST_IF_TRUE = 1;
	else
	  LAST_IF_TRUE = 0;

	return 0;
      }

      if(functionp(res)) {
	// FIXME: Filters are not handled here.
	do_iterate=function_iterate;
	LAST_IF_TRUE = 1;
	upper_size = 0;
	return 0;
      }

      parse_error("Wrong return type from emit source plugin.\n");
    }

    int(0..1) should_filter(mapping vs) {
      foreach(indices(filter), string v) {
	if(!vs[v])
	  return 1;
	if(!glob(filter[v], vs[v]))
	  return 1;
      }
      return 0;
    }

    int(0..1) do_once_more() {
      if(vars->counter>0 || !args["do-once"]) return 0;
      vars->counter = 1;
      return 1;
    }

    function do_iterate;

    int(0..1) function_iterate(RequestID id) {
      int counter = vars->counter;
      vars=res(args, id);
      vars->counter = counter++;
      return mappingp(vars);
    }

    int(0..1) array_iterate(RequestID id) {
      int counter=vars->counter;
      if(counter>=sizeof(res)) return 0;
      vars=res[counter++];
      vars->counter=counter;
      return 1;
    }

    int(0..1) array_filter_iterate(RequestID id) {
      int real_counter = vars->real_counter;
      int counter = vars->counter;

      if(real_counter>=sizeof(res)) return do_once_more();
      if(args->maxrows && counter == (int)args->maxrows)
	return do_once_more();
      if(args->skiprows>0) {
	if(args->skiprows > sizeof(res)) return do_once_more();
	while(--args->skiprows)
	  while(should_filter(res[real_counter++]))
	    if(real_counter>=sizeof(res)) return do_once_more();
      }
      while(should_filter(res[real_counter++]))
	if(real_counter>=sizeof(res)) return do_once_more();
      vars=res[real_counter-1];

      vars->real_counter = real_counter;
      vars->counter = counter+1;
      return 1;
    }

    array do_return(RequestID id) {
      result = content;
      if(upper_size)
	id->misc->emit_rowinfo = upper_size;
      if(args->filter && args->remainderinfo) {
	int rem;
	if(vars->real_counter < sizeof(res))
	  for(int i=vars->real_counter; i<sizeof(res); i++)
	    if(!should_filter(res[i]))
	      rem++;
	RXML.user_set_var(args->remainderinfo, rem);
      }
      return 0;
    }

  }
}

class TagEmitSources {
  inherit RXML.Tag;
  constant name="emit";
  constant plugin_name="sources";

  array(mapping(string:string)) get_dataset(mapping m, RequestID id) {
    return Array.map( indices(RXML.get_context()->tag_set->get_plugins("emit")),
		      lambda(string source) { return (["source":source]); } );
  }
}


class TagPathplugin
{
  inherit RXML.Tag;
  constant name = "emit";
  constant plugin_name = "path";

  array get_dataset(mapping m, RequestID id)
  {
    string fp = "";
    array res = ({});
    string p = id->not_query;
    if( m->trim )
      sscanf( p, "%s"+m->trim, p );
    if( p[-1] == '/' )
      p = p[..strlen(p)-2];
    array q = p / "/";
    if( m->skip )
      q = q[(int)m->skip..];
    foreach( q, string elem )
    {
      fp += "/" + elem;
      fp = replace( fp, "//", "/" );
      res += ({
        ([
          "name":elem,
          "path":fp
        ])
      });
    }
    return res;
  }
}

class TagEmitValues {
  inherit RXML.Tag;
  constant name="emit";
  constant plugin_name="values";

  array(mapping(string:string)) get_dataset(mapping m, RequestID id) {
    if(m["from-scope"]) {
      m->values=([]);
      RXML.Context context=RXML.get_context();
      map(context->list_var(m["from-scope"]),
	  lambda(string var){ m->values[var]=context->get_var(var, m["from-scope"]);
	  return ""; });
    }

    if( m->variable )
      m->values = RXML.get_context()->user_get_var( m->variable );

    if(!m->values)
      return ({});

    if(stringp(m->values)) {
      if(m->advanced) {
	switch(m->advanced) {
	case "chars":
	  m->split="";
	  break;
	case "lines":
	  m->values = replace(m->values, ({ "\n\r", "\r\n", "\r" }),
			      ({ "\n", "\n", "\n" }));
	  m->split = "\n";
	  break;
	case "words":
	  m->values = replace(m->values, ({ "\n\r", "\r\n", "\r" }),
			      ({ "\n", "\n", "\n" }));
	  m->values = replace(m->values, ({ "-\n", "\n", "\t" }),
			      ({ "", " ", " " }));
	  m->values = map(m->values/" " - ({""}),
			  lambda(string word) {
			    if(word[-1]=='.' || word[-1]==',' || word[-1]==';' ||
			       word[-1]==':' || word[-1]=='!' || word[-1]=='?')
			      return word[..sizeof(word)-2];
			    return word;
			  });
	  break;
	}
      }
      m->values=m->values / (m->split || "\000");
    }

    if(mappingp(m->values))
      return map( indices(m->values),
		  lambda(mixed ind) { return (["index":ind,"value":m->values[ind]]); });

    if(arrayp(m->values))
      return map( m->values,
		  lambda(mixed val) {
		    if(m->trimwhites) val=String.trim_all_whites((string)val);
		    if(m->case=="upper") val=upper_case(val);
		    else if(m->case=="lower") val=lower_case(val);
		    return (["value":val]);
		  } );

    RXML.run_error("Values variable has wrong type %t.\n", m->values);
  }
}

class TagComment {
  inherit RXML.Tag;
  constant name = "comment";
  constant flags = RXML.FLAG_DONT_REPORT_ERRORS;
  class Frame {
    inherit RXML.Frame;
    int do_iterate=-1;
    array do_enter() {
      if(args && args->preparse)
	do_iterate=1;
      return 0;
    }
    array do_return = ({});
  }
}

class TagPIComment
{
  inherit TagComment;
  constant flags = RXML.FLAG_PROC_INSTR;
}

RXML.TagSet query_tag_set()
{
  // Note: By putting the tags in rxml_tag_set, they will always have
  // the highest priority.
  rxml_tag_set->add_tags (filter (rows (this_object(),
					glob ("Tag*", indices (this_object()))),
				  functionp)());
  return Roxen.entities_tag_set;
}


// ---------------------------- If callers -------------------------------

class UserIf
{
  inherit RXML.Tag;
  constant name = "if";
  string plugin_name;
  string rxml_code;

  void create(string pname, string code) {
    plugin_name = pname;
    rxml_code = code;
  }

  int eval(string ind, RequestID id) {
    int otruth, res;
    string tmp;

    TRACE_ENTER("user defined if argument "+plugin_name, UserIf);
    otruth = LAST_IF_TRUE;
    LAST_IF_TRUE = -2;
    tmp = parse_rxml(rxml_code, id);
    res = LAST_IF_TRUE;
    LAST_IF_TRUE = otruth;

    TRACE_LEAVE("");

    if(ind==plugin_name && res!=-2)
      return res;

    return (ind==tmp);
  }
}

class IfIs
{
  inherit RXML.Tag;
  constant name = "if";

  constant cache = 0;
  function source;
  function eval = match_in_map;

  int match_in_string( string value, RequestID id )
  {
    string is;
    if(!this_object()->cache) NOCACHE();
    sscanf( value, "%s is %s", value, is );
    if(!is) return strlen(value);
    value = lower_case( value );
    is = lower_case( is );
    return ((is==value)||glob(is,value)||
            sizeof(filter( is/",", glob, value )));
  }

  int match_in_map( string value, RequestID id )
  {
    if(!this_object()->cache) NOCACHE();
    array arr=value/" ";
    string|int|float var=source(id, arr[0]);
    if( !var && zero_type( var ) ) return 0;
    if(sizeof(arr)<2) return !!var;
    var = lower_case( (var+"") );
    if(sizeof(arr)==1) return !!var;
    string is=lower_case(arr[2..]*" ");

    if(arr[1]=="==" || arr[1]=="=" || arr[1]=="is")
      return ((is==var)||glob(is,var)||
            sizeof(filter( is/",", glob, var )));
    if(arr[1]=="!=") return is!=var;

    string trash;
    if(sscanf(var,"%f%s",float f_var,trash)==2 && trash=="" &&
       sscanf(is ,"%f%s",float f_is ,trash)==2 && trash=="") {
      if(arr[1]=="<") return f_var<f_is;
      if(arr[1]==">") return f_var>f_is;
    }
    else {
      if(arr[1]=="<") return (var<is);
      if(arr[1]==">") return (var>is);
    }

    value=source(id, value);
    return !!value;
  }
}

class IfMatch
{
  inherit RXML.Tag;
  constant name = "if";

  constant cache = 0;
  function source;

  int eval( string is, RequestID id ) {
    array|string value=source(id);
    if(!this_object()->cache) NOCACHE();
    if(!value) return 0;
    if(arrayp(value)) value=value*" ";
    value = lower_case( value );
    is = lower_case( "*"+is+"*" );
    return (glob(is,value)||sizeof(filter( is/",", glob, value )));
  }
}

class TagIfDate {
  inherit RXML.Tag;
  constant name = "if";
  constant plugin_name = "date";

  int eval(string date, RequestID id, mapping m) {
    CACHE(60); // One minute accuracy is probably good enough...
    int a, b;
    mapping c;
    c=localtime(time(1));
    b=(int)sprintf("%02d%02d%02d", c->year, c->mon + 1, c->mday);
    a=(int)replace(date,"-","");
    if(a > 999999) a -= 19000000;
    else if(a < 901201) a += 10000000;
    if(m->inclusive || !(m->before || m->after) && a==b)
      return 1;
    if(m->before && a>b)
      return 1;
    else if(m->after && a<b)
      return 1;
  }
}

class TagIfTime {
  inherit RXML.Tag;
  constant name = "if";
  constant plugin_name = "time";

  int eval(string ti, RequestID id, mapping m) {
    CACHE(time(1)%60); // minute resolution...

    int tok, a, b, d;
    mapping c;
    c=localtime(time(1));

    b=(int)sprintf("%02d%02d", c->hour, c->min);
    a=(int)replace(ti,":","");

    if(m->until) {
      d = (int)m->until;
      if (d > a && (b > a && b < d) )
	return 1;
      if (d < a && (b > a || b < d) )
	return 1;
      if (m->inclusive && ( b==a || b==d ) )
	return 1;
    }
    else if(m->inclusive || !(m->before || m->after) && a==b)
      return 1;
    if(m->before && a>b)
      return 1;
    else if(m->after && a<b)
      return 1;
  }
}

class TagIfUser {
  inherit RXML.Tag;
  constant name = "if";
  constant plugin_name = "user";

  int eval(string u, RequestID id, mapping m) {
    if(!id->auth)
      return 0;
    NOCACHE();
    if(u == "any")
      if(m->file)
	return match_user(id->auth,id->auth[1],m->file,!!m->wwwfile, id);
      else
	return id->auth[0];
    else
      if(m->file)
	// FIXME: wwwfile attribute doesn't work.
	return match_user(id->auth,u,m->file,!!m->wwwfile,id);
      else
	return id->auth[0] && (search(u/",", id->auth[1]) != -1);
  }

  private int match_user(array u, string user, string f, int wwwfile, RequestID id) {
    string s, pass;
    if(u[1]!=user)
      return 0;
    if(!wwwfile)
      s=Stdio.read_bytes(f);
    else
      s=id->conf->try_get_file(Roxen.fix_relative(f,id), id);
    return ((pass=simple_parse_users_file(s, u[1])) &&
	    (u[0] || match_passwd(u[2], pass)));
  }

  private int match_passwd(string try, string org) {
    if(!strlen(org)) return 1;
    if(crypt(try, org)) return 1;
  }

  private string simple_parse_users_file(string file, string u) {
    if(!file) return 0;
    foreach(file/"\n", string line)
      {
	array(string) arr = line/":";
	if (arr[0] == u && sizeof(arr) > 1)
	  return(arr[1]);
      }
  }
}

class TagIfGroup {
  inherit RXML.Tag;
  constant name = "if";
  constant plugin_name = "group";

  int eval(string u, RequestID id, mapping m) {
    if( !id->auth )
      return 0;
    NOCACHE();
    return ((m->groupfile && sizeof(m->groupfile))
	    && group_member(id->auth, m->group, m->groupfile, id));
  }

  private int group_member(array auth, string group, string groupfile, RequestID id) {
    if(!auth)
      return 0; // No auth sent

    string s;
    catch { s = Stdio.read_bytes(groupfile); };

    if (!s)
      s = id->conf->try_get_file( Roxen.fix_relative( groupfile, id), id );

    if (!s) return 0;

    s = replace(s,({" ","\t","\r" }), ({"","","" }));

    multiset(string) members = simple_parse_group_file(s, group);
    return members[auth[1]];
  }

  private multiset simple_parse_group_file(string file, string g) {
    multiset res = (<>);
    array(string) arr ;
    foreach(file/"\n", string line)
      if(sizeof(arr = line/":")>1 && (arr[0] == g))
	res += (< @arr[-1]/"," >);
    return res;
  }
}

class TagIfExists {
  inherit RXML.Tag;
  constant name = "if";
  constant plugin_name = "exists";

  int eval(string u, RequestID id) {
    CACHE(5);
    return id->conf->is_file(Roxen.fix_relative(u, id), id);
  }
}

class TagIfNserious {
  inherit RXML.Tag;
  constant name = "if";
  constant plugin_name = "nserious";

  int eval() {
#ifdef NSERIOUS
    return 1;
#else
    return 0;
#endif
  }
}

class TagIfModule {
  inherit RXML.Tag;
  constant name = "if";
  constant plugin_name = "module";

  int eval(string u, RequestID id) {
    if (!u || !sizeof(u)) return 0;
    return sizeof(glob(u+"#*", indices(id->conf->enabled_modules)));
  }
}

class TagIfTrue {
  inherit RXML.Tag;
  constant name = "if";
  constant plugin_name = "true";

  int eval(string u, RequestID id) {
    return LAST_IF_TRUE;
  }
}

class TagIfFalse {
  inherit RXML.Tag;
  constant name = "if";
  constant plugin_name = "false";

  int eval(string u, RequestID id) {
    return !LAST_IF_TRUE;
  }
}

class TagIfAccept {
  inherit IfMatch;
  constant plugin_name = "accept";
  array source(RequestID id) {
    NOCACHE();
    return id->misc->accept;
  }
}

class TagIfConfig {
  inherit IfIs;
  constant plugin_name = "config";
  int source(RequestID id, string s) {
    NOCACHE();
    return id->config[s];
  }
}

class TagIfCookie {
  inherit IfIs;
  constant plugin_name = "cookie";
  string source(RequestID id, string s) {
    NOCACHE();
    return id->cookies[s];
  }
}

class TagIfClient {
  inherit IfMatch;
  constant plugin_name = "client";
  array source(RequestID id) {
    NOCACHE();
    return id->client;
  }
}

#ifdef OLD_RXML_COMPAT
class TagIfName {
  inherit TagIfClient;
  constant plugin_name = "name";
}
#endif

class TagIfDefined {
  inherit IfIs;
  constant plugin_name = "defined";
  constant cache = 1;
  string|int|float source(RequestID id, string s) {
    mixed val;
    NOCACHE();
    if(!id->misc->defines || !(val=id->misc->defines[s])) return 0;
    if(stringp(val) || intp(val) || floatp(val)) return val;
    return 1;
  }
}

class TagIfDomain {
  inherit IfMatch;
  constant plugin_name = "domain";
  string source(RequestID id) {
    NOCACHE();
    return id->host;
  }
}

class TagIfIP {
  inherit IfMatch;
  constant plugin_name = "ip";
  string source(RequestID id) {
    NOCACHE();
    return id->remoteaddr;
  }
}

#ifdef OLD_RXML_COMPAT
class TagIfHost {
  inherit TagIfIP;
  constant plugin_name = "host";
}
#endif

class TagIfLanguage {
  inherit IfMatch;
  constant plugin_name = "language";
  array source(RequestID id) {
    NOCACHE();
    return id->misc->pref_languages->get_languages();
  }
}

class TagIfMatch {
  inherit IfIs;
  constant plugin_name = "match";
  string source(RequestID id, string s) {
    return s;
  }
}

class TagIfPragma {
  inherit IfIs;
  constant plugin_name = "pragma";
  int source(RequestID id, string s) {
    NOCACHE();
    return id->pragma[s];
  }
}

class TagIfPrestate {
  inherit IfIs;
  constant plugin_name = "prestate";
  constant cache = 1;
  int source(RequestID id, string s) {
    return id->prestate[s];
  }
}

class TagIfReferrer {
  inherit IfMatch;
  constant plugin_name = "referrer";
  array source(RequestID id) {
    NOCACHE();
    return id->referer;
  }
}

class TagIfSupports {
  inherit IfIs;
  constant plugin_name = "supports";
  int source(RequestID id, string s) {
    NOCACHE();
    return id->supports[s];
  }
}

class TagIfVariable {
  inherit IfIs;
  constant plugin_name = "variable";
  constant cache = 1;
  string source(RequestID id, string s) {
    mixed var=RXML.user_get_var(s);
    if(!var) return var;
    return RXML.t_text->encode (var);
  }
}

class TagIfSizeof {
  inherit IfIs;
  constant plugin_name = "sizeof";
  constant cache = 1;
  int source(RequestID id, string s) {
    mixed var=RXML.user_get_var(s);
    if(!var) {
      if(zero_type(RXML.user_get_var(s))) return 0;
      return 1;
    }
    if(stringp(var) || arrayp(var) ||
       multisetp(var) || mappingp(var)) return sizeof(var);
    if(objectp(var) && var->_sizeof) return sizeof(var);
    return sizeof((string)var);
  }
}

class TagIfClientvar {
  inherit IfIs;
  constant plugin_name = "clientvar";
  string source(RequestID id, string s) {
    NOCACHE();
    return id->client_var[s];
  }
}

#endif

// ------------------------ Documentation -----------------------------

mapping tagdocumentation() {
  Stdio.File file=Stdio.File();
  if(!file->open(__FILE__,"r")) return 0;
  mapping doc=compile_string("#define manual\n"+file->read())->tagdoc;
  file->close();
  if(!file->open("etc/supports","r")) return doc;
  parse_html(file->read(), ([]), (["flags":format_support,
				   "vars":format_support]), doc);
  return doc;
}

static int format_support(string t, mapping m, string c, mapping doc) {
  string key=(["flags":"if#supports","vars":"if#clientvar"])[t];
  c=Roxen.html_encode_string(c)-"#! ";
  c=(Array.map(c/"\n", lambda(string row) {
			 if(sscanf(row, "%*s - %*s")!=2) return "";
			 return "<li>"+row+"</li>";
		       }) - ({""})) * "\n";
  doc[key]+="<ul>\n"+c+"</ul>\n";
  return 0;
}

#ifdef manual
constant tagdoc=([
"&roxen;":#"<desc scope><short>This scope contains information specific to this Roxen WebServer.</short></desc>",
"&roxen.domain;":#"<desc ent>The domain name of this site.</desc>",
"&roxen.hits;":#"<desc ent>The number of hits, i.e. requests the
 webserver has accumulated since it was last started.</desc>",
"&roxen.hits-per-minute;":"<desc ent>The number of hits per minute, in average.</desc>",
"&roxen.pike-version;":"<desc ent>The version of Pike the webserver is using.</desc>",
"&roxen.sent;":"<desc ent>The total amount of data the webserver has sent. </desc>",
"&roxen.sent-kbit-per-second;":"<desc ent>The average amount of data the webserver has sent, in Kibibits.</desc>",
"&roxen.sent-mb;":"<desc ent>The total amount of data the webserver has sent, in Mebibits.</desc>",
"&roxen.sent-per-minute;":"<desc ent></desc>",
"&roxen.server;":"<desc ent>The URL of the webserver.</desc>",
"&roxen.ssl-strength;":"<desc ent>How many bits encryption strength are the SSL capable of</desc>",
"&roxen.time;":"<desc ent>The current posix time.</desc>",
"&roxen.uptime;":"<desc ent>The total uptime of the webserver, in seconds.</desc>",
"&roxen.uptime-days;":"<desc ent>The total uptime of the webserver, in days.</desc>",
"&roxen.uptime-hours;":"<desc ent>The total uptime of the webserver, in hours.</desc>",
"&roxen.uptime-minutes;":"<desc ent>The total uptime of the webserver, in minutes.</desc>",
"&roxen.version;":"<desc ent>Which version of Roxen WebServer that is running.</desc>",

"&client;":#"<desc scope><short>
 This scope contains information specific to the client/browser that
 is accessing the page.</short>
</desc>",

"&page;":"<desc scope><short>This scope contains information specific to this page.</short></desc>",

"&form;":#"<desc scope><short hide>
 This scope contains form variables.</short>This scope contains the
 form variables, i.e. the answers to HTML forms sent by the client.
 There are no predefined entities for this scope.
</desc>",


"&cookie;":#"<desc scope><short>
 This scope contains the cookies sent by the client.</short> Adding,
 deleting or changing in this scope updates the clients cookies. There
 are no predefined entities for this scope.</short>
</desc>",

"&var;":#"<desc scope><short>
 This scope is empty when the page parsing begins.</short> There are
 no predefined entities for this scope.
</desc>",


"case":#"<desc cont><short>
 Alters the case of the contents.</short>
</desc>

<attr name='case' value='upper|lower|capitalize' required>
 Changes all characters to upper or lower case letters, or
 capitalizes the first letter in the content.

<ex><case upper=''>upper</case></ex>
<ex><case lower=''>lower</case></ex>
<ex><case capitalize=''>captalize</case></ex>
</attr>",

"cond":({ #"<desc cont><short hide>This tag makes a boolean test on a specified list of cases.</short>
 This tag is almost eqvivalent to the <tag>if</tag>/<tag>else</tag>
 tag combination. The main diffirence is that the <tag>default</tag>
 tag may be put whereever you want it within the <tag>cond</tag> tag.
 This will of course affect the order the content is parsed. The
 <tag>case</tag> tag is required.</desc>",

	  (["case":#"<desc cont>
 This tag takes the argument that is to be tested and if it's true,
 it's content is executed before exiting the <tag>cond</tag>. If the
 argument is false the content is skipped and the next <tag>case</tag>
 tag is parsed.</desc>

<ex type='vert'>
<set variable='var.foo' value='17'/>
<cond>
  <case true=''><ent>var.foo</ent><set variable='var.foo' expr='&var.foo;+1'/></case>
  <default><ent>var.foo</ent><set variable='var.foo' expr='&var.foo;+2'/></default>
</cond>
<ent>var.foo</ent>
</ex>",

	    "default":#"<desc cont>
 The <tag>default</tag> tag is eqvivalent to the <tag>else</tag> tag
 in an <tag>if</tag> statement. The difference between the two is that
 the <tag>default</tag> may be put anywhere in the <tag>cond</tag>
 statement. This affects the parseorder of the statement. If the
 <tag>default</tag> tag is put first in the statement it will allways
 be executed, then the next <tag>case</tag> tag will be executed and
 perhaps add to the result the <tag>default</tag> performed.</desc>

<ex type='vert'>
<set variable=\"var.foo\" value=\"17\"/>
<cond>
  <default><ent>var.foo</ent><set variable=\"var.foo\" expr=\"&var.foo;+2\"/></default>
  <case true=''><ent>var.foo</ent><set variable=\"var.foo\" expr=\"&var.foo;+1\"/></case>
</cond>
<ent>var.foo</ent>
</ex>
<br/>
<ex type='vert'>
<set variable=\"var.foo\" value=\"17\"/>
<cond>
  <case false=''><ent>var.foo</ent><set variable=\"var.foo\" expr=\"&var.foo;+1\"/></case>
  <default><ent>var.foo</ent><set variable=\"var.foo\" expr=\"&var.foo;+2\"/></default>
</cond>
<ent>var.foo</ent>
</ex>"
	    ])
	  }),

"comment":#"<desc cont><short>
 The enclosed text will be removed from the document.</short> The
 difference from a normal SGML (HTML/XML) comment is that the text is
 removed from the document, and can not be seen even with <i>view
 source</i> in the browser.

 <p>Note that since this is a normal tag, it requires that the content
 is properly formatted. Therefore it's ofter better to use the
 &lt;?comment&nbsp;...&nbsp;?&gt; processing instruction tag to
 comment out arbitrary text (which doesn't contain '?&gt;').</p>

 <p>Just like any normal tag, the <tag>comment</tag> tag nests inside
 other <tag>comment</tag> tags. E.g:</p>

 <ex>
   <comment> a <comment> b </comment> c </comment>
 </ex>

 <p>Here 'c' is not output since the comment starter before 'a'
 matches the ender after 'c' and not the one before it.</p>
</desc>

<attr name=preparse>
 Parse and execute any RXML inside the comment tag. This is useful to
 do stuff without producing any output in the response.
</attr>",


"<?comment":#"<desc pi><short>
 Processing instruction tag for comments.</short> This tag is similar
 to the RXML <ref type='tag'><tag>comment</tag> tag but should be used
 when commenting arbitrary text that doesn't contain '?&gt;'.
</desc>",


"define":({ #"<desc cont><short>
 Defines variables, tags, containers and if-callers.</short> One, and only one,
 attribute must be set.
</desc>

<attr name=variable value=name>
 Sets the value of the variable to the contents of the container.
</attr>

<attr name=tag value=name>
 Defines a tag that outputs the contents of the container.
</attr>

<attr name=container value=name>
 Defines a container that outputs the contents of the container.
</attr>

<attr name=if value=name>
 Defines an if-caller that compares something with the contents of the
 container.
</attr>

<attr name=trimwhites>
 Trim all white space characters from the begining and the end of the contents.
</attr>

The values of the attributes given to the defined tag are available in the
scope created within the define tag.

<ex><define tag=\"hi\">Hello <ent>_.name</ent>!</define>
<hi name=\"Martin\"/></ex>",

	    (["attrib":#"<desc cont>
 When defining a tag or a container the container <tag>attrib</tag>
 can be used to define default values of the attributes that the
 tag/container can have.</desc>

 <attr name=name value=name>
  The name of the attribute which default value is to be set.
 </attr>",

"&_.args;":#"<desc ent>
 The full list of the attributes, and their arguments, given to the
 tag.
</desc>",

"&_.rest-args;":#"<desc ent>
 A list of the attributes, and their arguments, given to the tag,
 excluding attributes with default values defined.
</desc>",

"&_.contents;":#"<desc ent>
 The containers contents.
</desc>",

"contents":#"<desc tag>
 As the contents entity, but unquoted.
</desc>"
	    ])

}),

"else":#"<desc cont><short hide>
 Show the contents if the previous <if> tag didn't, or if there was a
 <false> tag above.</short>Show the contents if the previous <tag><ref
 type='tag'>if</ref></tag> tag didn't, or if there was a <tag><ref
 type='tag'>false</ref></tag> tag above. The result is undefined if there
 has been no <tag><ref type='tag'>if</ref></tag>, <true> or <tag><ref
 type='tag'>false</ref></tag> tag above. </desc>",

"elseif":#"<desc cont><short hide>
 Same as the <if> tag, but it will only evaluate if the previous <if>
 tag returned false.</short>Same as the <tag><ref
 type='tag'>if</ref></tag>, but it will only evaluate if the previous
 <tag><ref type='tag'>if</ref></tag> tag returned false. </desc>",

"false":#"<desc tag><short hide>
 Internal tag used to set the return value of <if> tags.
 </short>Internal tag used to set the return value of <tag><ref
 type='tag'>if</ref></tag> tags. It will ensure that the next
 <tag><ref type='tag'>else</ref></tag> tag will show its contents. It
 can be useful if you are writing your own <tag><ref
 type='tag'>if</ref></tag> lookalike tag. </desc>",

"help":#"<desc tag><short>
 Gives help texts for tags.</short> If given no arguments, it will
 list all available tags. By inserting <tag>help/</tag> in a page, a
 full index of the tags available in that particular Roxen WebServer
 will be presented. If a particular tag is missing from that index, it
 is not available at that moment. All tags are available through
 modules, hence that particular tags' module hasn't been added to the
 Roxen WebServer. Ask an administrator to add the module.
</desc>

<attr name=for value=tag>
 Gives the help text for that tag.
<ex type='vert'><help for='roxen'/></ex>
</attr>",

"if":#"<desc cont><short hide>
 <if> is used to conditionally show its contents.</short><tag><ref
 type='tag'>If</ref></tag> is used to conditionally show its contents.
 <tag><ref type='tag'>else</ref></tag>, <tag><ref
 type='tag'>elif</ref></tag> or <tag><ref
 type='tag'>elseif</ref></tag> can be used to suggest alternative
 content.

 <p>It is possible to use glob patterns in almost all attributes,
 where * means match zero or more characters while ? matches one
 character. * Thus t*f?? will match trainfoo as well as * tfoo but not
 trainfork or tfo. It is not possible to use regexp's together
 with any of the if-plugins.</p>

 <p>The <ref type='tag'>if</ref> tag itself is useless without its
 plugins. Its main functionality is to provide a framework for the
 plugins.</p>

 <p>It is mandatory to add a plugin as one attribute. The other
 attributes provided are and, or and not, used for combining plugins
 or logical negation.</p>

 <ex type='box'>
  <if variable='var.foo > 0' and='' match='var.bar is No'>
    ...
  </if>
 </ex>

 <ex type='box'>
  <if variable='var.foo > 0' not=''>
    <ent>var.foo</ent> is lesser than 0
  </if>
  <else>
    <ent>var.foo</ent> is greater than 0
  </else>
 </ex>

 <p>Operators valid in attribute expressions are: '=', '==', 'is', '!=',
 '&lt;' and '&gt;'.</p>

 <p>The If plugins are sorted according to their function into five
 categories: Eval, Match, State, Utils and SiteBuilder.</p>

 <p>The Eval category is the one corresponding to the regular tests made
 in programming languages, and perhaps the most used. They evaluate
 expressions containing variables, entities, strings etc and are a sort
 of multi-use plugins. All If-tag operators and global patterns are
 allowed.</p>

 <ex>
  <set variable='var.x' value='6'/>
  <if variable='var.x > 5'>More than one hand</if>
 </ex>

 <p>The Match category contains plugins that match contents of
 something, e.g. an IP package header, with arguments given to the
 plugin as a string or a list of strings.</p>

 <ex>
  Your domain <if ip='130.236.*'> is </if>
  <else> isn't </else> liu.se.
 </ex>

 <p>State plugins check which of the possible states something is in,
 e.g. if a flag is set or not, if something is supported or not, if
 something is defined or not etc.</p>

 <ex>
   Your browser
  <if supports='javascript'>
   supports Javascript version <ent>client.javascript</ent>
  </if>
  <else>doesn't support Javascript</else>.
 </ex>

 <p>Utils are additonal plugins specialized for certain tests, e.g.
 date and time tests.</p>

 <ex>
  <if time='1700' after=''>
    Are you still at work?
  </if>
  <elseif time='0900' before=''>
     Wow, you work early!
  </elseif>
  <else>
   Somewhere between 9 to 5.
  </else
 </ex>

 <p>SiteBuilder plugins requires a Roxen Platform SiteBuilder
 installed to work. They are adding test capabilities to web pages
 contained in a SiteBuilder administrated site.</p>
</desc>

<attr name=not>
 Inverts the result (true-&gt;false, false-&gt;true).
</attr>

<attr name=or>
 If any criterion is met the result is true.
</attr>

<attr name=and>
 If all criterions are met the result is true. And is default.
</attr>",

"if#true":#"<desc plugin><short>
 This will always be true if the truth value is set to be
 true.</short> Equivalent with <tag><ref type=cont>then</ref></tag>.
 True is a <i>State</i> plugin.
</desc>
<attr name='true' required>
 Show contents if truth value is false.
</attr>",

"if#false":#"<desc plugin><short>
 This will always be true if the truth value is set to be
 false.</short> Equivalent with <tag><ref type='tag'>else</ref></tag>.
 False is a <i>State</i> plugin.
</desc>
<attr name='false' required>
 Show contents if truth value is true.
</attr>",

"if#module":#"<desc plugin><short>Enables true if the selected module is enabled
 in the current server.</short></desc>
 <attr name='module' value='name'>
 The \"real\" name of the module to look for, i.e. its filename without extension.
 </attr>",

"if#accept":#"<desc plugin><short>
 Returns true if the browser accepts certain content types as specified
 by it's Accept-header, for example image/jpeg or text/html.</short> If
 browser states that it accepts */* that is not taken in to account as
 this is always untrue. Accept is a <i>Match</i> plugin.
</desc>
<attr name='accept' value='type1[,type2,...]' required>
</attr>",

"if#config":#"<desc plugin><short>
 Has the config been set by use of the <tag><ref
 type='tag'>aconf</ref></tag> tag?</short> Config is a <i>State</i> plugin.
</desc>
<attr name='config' value='name' required>
</attr>",

"if#cookie":#"<desc plugin><short>
 Does the cookie exist and if a value is given, does it contain that
 value?</short> Cookie is an <i>Eval</i> plugin.
</desc>
<attr name='cookie' value='name[ is value]' required>
</attr>",

"if#client":#"<desc plugin><short>
 Compares the user agent string with a pattern.</short> Client and name is an
 <i>Match</i> plugin.
</desc>
<attr name='client' value='' required>
</attr>",

"if#date":#"<desc plugin><short>
 Is the date yyyymmdd?</short> The attributes before, after and inclusive
 modifies the behavior. Date is a <i>Utils</i> plugin.
</desc>
<attr name='date' value='yyyymmdd' required>
 Choose what date to test.
</attr>

<attr name=after>
 The date after todays date.
</attr>

<attr name=before>
 The date before todays date.
</attr>

<attr name=inclusive>
 Adds todays date to after and before.

 <ex>
  <if date='19991231' before='' inclusive=''>
     - 19991231
  </if>
  <else>
    20000101 -
  </else>
 </ex>
</attr>",

"if#defined":#"<desc plugin><short hide>
 Tests if a certain RXML define is defined by use of the <define> tag.
 </short> Tests if a certain RXML define is defined by use of the
 <tag>define</tag> tag.Defined is a <i>State</i> plugin.
</desc>
<attr name='defined' value='define' required>
 Choose what define to test.
</attr>",

"if#domain":#"<desc plugin><short>
 Does the user's computer's DNS name match any of the patterns?</short> Note
 that domain names are resolved asynchronously, and that the first time
 someone accesses a page, the domain name will probably not have been
 resolved. Domain is a <i>Match</i> plugin.
</desc>
<attr name='domain' value='pattern1[,pattern2,...]' required>
 Choose what pattern to test.
</attr>
",

"if#exists":#"<desc plugin><short>
 Returns true if the file path exists.</short> If path does not begin
 with /, it is assumed to be a URL relative to the directory
 containing the page with the <tag><ref
 type='tag'>if</ref></tag>-statement. Exists is a <i>Utils</i>
 plugin.
</desc>
<attr name='exists' value='path' required>
 Choose what path to test.
</attr>",

"if#group":#"<desc plugin><short>
 Checks if the current user is a member of the group according
 the groupfile.</short> Group is a <i>Utils</i> plugin.
</desc>
<attr name='group' value='name' required>
 Choose what group to test.
</attr>

<attr name='groupfile' value='path' required>
 Specify where the groupfile is located.
</attr>",

"if#ip":#"<desc plugin><short>

 Does the users computers IP address match any of the
 patterns?</short> This plugin replaces the Host plugin of earlier
 RXML versions. Ip is a <i>Match</i> plugin.
</desc>
<attr name='ip' value='pattern1[,pattern2,...]' required>
 Choose what IP-adress pattern to test.
</attr>
",

"if#language":#"<desc plugin><short>
 Does the client prefer one of the languages listed, as specified by the
 Accept-Language header?</short> Language is a <i>Match</i> plugin.
</desc>
<attr name='language' value='language1[,language2,...]' required>
 Choose what language to test.
</attr>
",

"if#match":#"<desc plugin><short>
 Evaluates patterns.</short> Match is an <i>Eval</i> plugin.
</desc>
<attr name='match' value='pattern' required>
 Choose what pattern to test.
</attr>
",

"if#pragma":#"<desc plugin><short>
 Compares the HTTP header pragma with a string.</short> Pragma is a
 <i>State</i> plugin.
</desc>
<attr name='pragma' value='string' required>
 Choose what pragma to test.

<ex>
 <if pragma='no-cache'>The page has been reloaded!</if>
 <else>Reload this page!</else>
</ex>
</attr>
",

"if#prestate":#"<desc plugin><short>
 Are all of the specified prestate options present in the URL?</short>
 Prestate is a <i>State</i> plugin.
</desc>
<attr name='prestate' value='option1[,option2,...]' required>
 Choose what prestate to test.
</attr>
",

"if#referrer":#"<desc plugin><short>
 Does the referrer header match any of the patterns?</short> Referrer
 is a <i>Match</i> plugin.
</desc>
<attr name='referrer' value='pattern1[,pattern2,...]' required>
 Choose what pattern to test.
</attr>
",

// The list of support flags is extracted from the supports database and
// concatenated to this entry.
"if#supports":#"<desc plugin><short>
 Does the browser support this feature?</short> Supports is a
 <i>State</i> plugin.
</desc>

<attr name=supports'' value='feature' required required>
 Choose what supports feature to test.
</attr>

The following features are supported:",

"if#time":#"<desc plugin><short>
 Is the time hhmm?</short> The attributes before, after and inclusive modifies
 the behavior. Time is a <i>Utils</i> plugin.
</desc>
<attr name='time' value='hhmm' required>
 Choose what time to test.
</attr>

<attr name=after>
 The time after present time.
</attr>

<attr name=before>
 The time before present time.
</attr>

<attr name=inclusive>
 Adds present time to after and before.

 <ex>
  <if time='1200' before='' inclusive=''>
    ante meridiem
  </if>
  <else>
    post meridiem
  </else>
 </ex>
</attr>",

"if#user":#"<desc plugin><short>
 Has the user been authenticated as one of these users?</short> If any
 is given as argument, any authenticated user will do. User is a
 <i>Utils</i> plugin.
</desc>
<attr name='user' value='name1[,name2,...]|any' required>
 Specify which users to test.
</attr>
",

"if#variable":#"<desc plugin><short>
 Does the variable exist and, optionally, does it's content match the
 pattern?</short> Variable is an <i>Eval</i> plugin.
</desc>
<attr name='variable' value='name[ is pattern]' required>
 Choose variable to test. Valid operators are '=', '==', 'is', '!=',
 '&lt;' and '&gt;'.
</attr>
",

// The list of support flags is extracted from the supports database and
// concatenated to this entry.
"if#clientvar":#"<desc plugin><short>
Evaluates expressions with client specific values.</short> Clientvar
is an <i>Eval</i> plugin.
</desc>
<attr name='clientvar' value='variable [is value]' required>
 Choose which variable to evaluate against. Valid operators are '=',
 '==', 'is', '!=', '&lt;' and '&gt;'.
</attr>

Available variables are:",

"if#sizeof":#"<desc plugin><short>Compares the size of a variable with a number.</short>
<ex>
<set variable=\"var.x\" value=\"hello\"/>
<set variable=\"var.y\" value=\"\"/>
<if sizeof=\"var.x == 5\">Five</if>
<if sizeof=\"var.y > 0\">Nonempty</if>
</ex>
</desc>",

"nooutput":#"<desc cont><short>
 The contents will not be sent through to the page.</short> Side effects, for
 example sending queries to databases, will take effect.
</desc>",

"noparse":#"<desc cont><short>
 The contents of this container tag won't be RXML parsed.</short>
</desc>",

"number":#"<desc tag><short>
 Prints a number as a word.</short>
</desc>

<attr name=num value=number required>
 Print this number.
<ex type='vert'><number num='4711'/></ex>
</attr>

<attr name=language value=langcodes>
 The language to use.
 <lang/>
 <ex type='vert'>Mitt favoritnummer �r <number num='11' language='sv'/>.</ex>
 <ex type='vert'>Il mio numero preferito <ent>egrave</ent><number num='15' language='it'/>.</ex>
</attr>

<attr name=type value=number|ordered|roman|memory default=number>
 Sets output format.
 <ex type='vert'>It was his <number num='15' type='ordered'/> birthday yesterday.</ex>
 <ex type='vert'>Only <number num='274589226' type='memory'/> left on the Internet.</ex>
 <ex type='vert'>Spock Garfield <number num='17' type='roman'/> rests here.</ex>
</attr>",

"strlen":#"<desc cont><short>
 Returns the length of the contents.</short>
</desc>",

"then":#"<desc cont><short>
 Shows its content if the truth value is true.</short>

 <ex>There is <strlen>foo bar gazonk</strlen> characters inside the
 tag.</ex>
</desc>",

"trace":#"<desc cont><short>
 Executes the contained RXML code and makes a trace report about how
 the contents are parsed by the RXML parser.</short>
</desc>",

"true":#"<desc tag><short hide>
 An internal tag used to set the return value of <if> tags. </short>An
 internal tag used to set the return value of <tag><ref
 type='tag'>if</ref></tag> tags. It will ensure that the next
 <tag><ref type='tag'>else</ref></tag> tag will not show its contents.
 It can be useful if you are writing your own
 <tag><ref type='tag'>if</ref></tag> lookalike tag.
</desc>",

"undefine":#"<desc tag><short>
 Removes a definition made by the define container.</short> One
 attribute is required.
</desc>

<attr name=variable value=name>
 Undefines this variable.

 <ex>
  <define variable='var.hepp'>hopp</define>
  <ent>var.hepp</ent>
  <undefine variable='var.hepp'/>
  <ent>var.hepp</ent>
 </ex>
</attr>

<attr name=tag value=name>
 Undefines this tag.
</attr>

<attr name=container value=name>
 Undefines this container.
</attr>

<attr name=if value=name>
 Undefines this if-plugin.
</attr>",

"use":#"<desc cont><short>
 Reads tags, container tags and defines from a file or package.
</short></desc>

<attr name=packageinfo>
 Show a all available packages.
</attr>

<attr name=package value=name>
 Reads all tags, container tags and defines from the given package.
 Packages are files located in rxml_packages/ and local/rxml_packages/.
</attr>

<attr name=file value=path>
 Reads all tags and container tags and defines from the file.

 <p>This file will be fetched just as if someone had tried to fetch it
 with an HTTP request. This makes it possible to use Pike script
 results and other dynamic documents. Note, however, that the results
 of the parsing are heavily cached for performance reasons. If you do
 not want this cache, use <tag><ref type='tag'>insert file=...
 nocache</ref></tag> instead.</p>
</attr>

<attr name=info>
 Show a list of all defined tags/containers and if arguments in the file
</attr>
 The <tag>use</tag> tag is much faster than the
 <tag>insert</tag>, since the parsed definitions
 is cached.",

"eval":#"<desc cont><short>
 Postparses its content.</short> Useful when an entity contains
 RXML-code. <tag>eval</tag> is then placed around the entity to get
 its content parsed.
</desc>",

"emit#path":({ #"<desc plugin><short>
 Prints paths.</short> This plugin traverses over all directories in
 the path from the root up to the current one.
</desc>

<attr name='trim' value='string'>
 Removes all of the remaining path after and including the specified
 string.
</attr>

<attr name='skip' value='number'>
 Skips the 'number' of slashes ('/') specified, with beginning from
 the root.
</attr>",
	       ([
"&_.name;":#"<desc ent>
 Returns the name of the most recently traversed directory.
</desc>",

"&_.path;":#"<desc ent>
 Returns the path to the most recently traversed directory.
</desc>"
	       ])
	    })

"emit#sources":({ #"<desc plugin>
 Provides a list of all available emit sources.
</desc>",
  ([ "&_.source;":"<desc ent>The name of the source.</desc>" ]) }),

"emit#values":({ #"<desc plugin>
 Splits the string provided in the values attribute and outputs the parts in a loop. The
 value in the values attribute may also be an array or mapping.
</desc>
<attr name=values value='string, mapping or array' required>
An array or the string to be splitted into an array.
</attr>
<attr name=split value=string default=NULL>
The string the values string is splitted with.
</attr>
<attr name=advanced value=lines|words|chars>
If the input is a string it can be splitted into separate lines, words or characters by
using this attribute.
</attr>
<attr name=case value=upper|lower>
Changes the case of the value.
</attr>
<attr name=trimwhites>
Trims away all leading and trailing white space charachters from the values.
</attr>
<attr name=from-scope value=name>
Create a mapping out of a scope and give it as indata to the emit.
</attr>
",
  ([ "&_.value;":"<desc ent>The value of one part of the splitted string</desc>",
     "&_.index;":"<desc ent>The index of this mapping entry, if input was a mapping</desc>" ]) }),

"emit":({ #"<desc cont><short>Provides data, fetched from different sources, as
 entities</short></desc>

<attr name=source value=plugin required>
 The source from which the data should be fetched.
</attr>

<attr name=scope value=name default='The emit source'>
 The name of the scope within the emit tag.
</attr>

<attr name=maxrows value=number>
 Limits the number of rows to this maximum.
</attr>

<attr name=skiprows value=number>
 Makes it possible to skip the first rows of the result. Negative numbers means
 to skip everything execept the last n rows.
</attr>

<attr name=rowinfo value=variable>
 The number of rows in the result, after it has been limited by maxrows
 and skiprows, will be put in this variable, if given.
</attr>

<attr name=do-once>
 Indicate that at least one loop should be made. All variables in the
 emit scope will be empty.
</attr>",

	  ([

"&_.counter;":#"<desc ent>
 Gives the current number of loops inside the <tag>emit</tag> tag.
</desc>"

	  ])
       }),

]);
#endif

