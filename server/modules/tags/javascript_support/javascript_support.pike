// This is a roxen module. Copyright � 1999 - 2001, Roxen IS.

constant cvs_version = "$Id: javascript_support.pike,v 1.41 2001/09/13 15:36:59 wellhard Exp $";

#include <module.h>
inherit "module";

#define INT_TAG "_js_quote"

constant module_type = MODULE_PARSER|MODULE_FILTER|MODULE_PROVIDER;
constant module_name = "Tags: Javascript Support";
constant module_doc  = ("This module provides some tags to support "
			"javascript development (i.e. Javascript popup menus).");

// This module is indeed thread-safe.
constant thread_safe = 1;

//  Mapping of known callback functions. A callback is defined as
//
//    string my_callback(string token, string path, RequestID id)
//
//  where token is the token used when registering the callback and path
//  is the remaining part of the URL. The function should return the
//  JavaScript code which gets sent to the browser.
static private mapping(string:function(string,string,object:string)) callbacks = ([ ]);

//  Mapping of serverside exludes.
static private mapping(string:string) externals;

string query_provides()
{
  return "javascript_support";
}


mapping file_cache = ([ ]);

mapping find_internal(string f, RequestID id)
{
  //  On-the-fly generation using callback function
  if (sscanf(f, "__cb/%s/%s", string token, string path) == 2) {
    function cb = callbacks[token];
    return Roxen.http_string_answer((cb && cb(token, path, id)) || "",
				    "application/x-javascript");
  }
  
  if (sscanf(f, "__ex/%s", string key) == 1) {
    mixed error = catch {key = MIME.decode_base64(key);};
    if(error || !externals[key])
      return 0;
    return Roxen.http_string_answer(externals[key], "application/x-javascript");
  }
  
  //  Cache the files
  string file = combine_path(__FILE__, "../scripts", (f-".."));
  int|string data;
  if (!(data = file_cache[file])) {
    //  Put entry in cache. Missing files are stored as -1.
    if (!file_stat(file)) {
      file_cache[file] = -1;
      return 0;
    }
    data = file_cache[file] = Stdio.read_bytes(file);
  }
  id->misc->cacheable = INITIAL_CACHEABLE;
  return
    stringp(data) && Roxen.http_string_answer(data, "application/x-javascript" );
}

// Provider function
string get_callback_url(string token)
{
  return "__cb/" + token + "/";
}

// Provider function
void register_callback(string token, function(string,string,object:string) cb)
{
  callbacks[token] = cb;
}

// Rewrote the JSSupport/JSInsert objects to work with p-code. All
// data must be stored with mapping/array types in RXML_CONTEXT->misc
// to be able to encode and decode p-code frames. /Wellhardh
class JSInsert
{
  static private string name;
  static private mapping(string:string) args;
  static private array content; // Must be a reference type.

  void add(string s)
  {
    content[0] += s;
  }

  string get()
  {
    return content[0];
  }
  
  string _sprintf(int i, mapping(string:int)|void m)
  {
    return sprintf("JSInsert: %O, %O, %O", name, args, content[0]);
  }

  void create(string|mapping data, mapping(string:string)|void _args)
  {
    if(mappingp(data)) {
      name = data->name;
      args = data->args;
      content = data->content;
      return;
    }

    name = data;
    args = _args;
    content = ({ "" });
  }

  mapping encode()
  {
    return ([ "name":name, "args":args, "content":content ]);
  }
}

class JSSupport
{
  static private mapping(string:mapping) inserts;
  static private mapping(string:int) keys;

  string get_unique_id(string name)
  {
    return name+sprintf("%02x", keys[name]++); 
  }
  
  void create_insert(string name, string tag_name,
		     mapping(string:string) args)
  {
    inserts[name] = JSInsert(tag_name, args)->encode();
  }

  JSInsert get_insert(string name)
  {
    if(!inserts[name])
      create_insert(name, 0, 0);
    
    return JSInsert(inserts[name]);
  }
  
  string _sprintf(int i, mapping(string:int)|void m)
  {
    return sprintf("JSSupport: %O", inserts);
  }

  void create(mapping|void jssupport)
  {
    if(!jssupport)
      jssupport = ([ ]);

    inserts = jssupport->inserts = jssupport->inserts || ([ ]);
    keys = jssupport->keys = jssupport->keys || ([ ]);
  }

  mapping encode()
  {
    return ([ "inserts": inserts, "keys": keys ]);
  }
}

static private
string c_js_quote(string name, mapping args, string contents)
{
  string r = "var r = \"\";\n";
  r += Array.map(replace(contents, ({"\""}), ({ "\\\"" }) )/"\n", 
		 lambda(string row) {return "r += \""+row;})*"\\n\";\n";
  r += "\";\ndocument.write(r);\n";
  return r;
};

static private
string container_js_write(string name, mapping args, string contents, object id)
{
  string c_script(string name, mapping args, string contents, mapping xargs)
  {
    // Do not js-quote contents inside a <script>-tag with the same language-arg.
    if(upper_case(args->language||"") == upper_case(xargs->language||""))
      return "</"INT_TAG">"+contents+"<"INT_TAG">";
  };
  
  // Do not js-quote contents inside a <script>-tag with the same language-arg.
  contents = parse_html(contents, ([]), ([ "script": c_script ]), args);
  contents = parse_html("<"INT_TAG">"+contents+"</"INT_TAG">",
			([]), ([ INT_TAG: c_js_quote ]), args);
  return ("<script language='"+(args->language||"javascript")+
	  "'><!--\n"+contents+"//--></script>");
}

static private
string make_args_unquoted(mapping args)
{
  return map(indices(args),
	     lambda(string key)
	     { return key+"="+"\""+args[key]+"\""; })*" ";
}

static private
string make_container_unquoted(string name, mapping args, string contents)
{
  return "<"+name+" " + make_args_unquoted(args) + ">"+contents+"</"+name+">";
}

int jssp(RequestID id)
{
  return !!(RXML_CONTEXT? RXML_CONTEXT->misc->javascript_support:
	    id->misc->defines && id->misc->defines->javascript_support);
}

JSSupport get_jss(RequestID id)
{
  // The p-code codec can not handle objects so we have to store mapping
  // structures.
  mapping jssupport =
    (RXML_CONTEXT? RXML_CONTEXT->misc->javascript_support:
     id->misc->defines->javascript_support);
  
  if(!jssupport) {
    jssupport = JSSupport()->encode();
    if(RXML_CONTEXT)
      RXML_CONTEXT->set_misc("javascript_support", jssupport);
  }
  
  //werror("get_jss: %O\n", jssupport);
  return JSSupport(jssupport);
}

class TagEmitJsHidePopup {
  inherit RXML.Tag;
  constant name = "emit";
  constant plugin_name = "js-hide-popup";
  array get_dataset(mapping args, RequestID id)
  {
    string s = "clearToPopup('"+(id->misc->_popupparent||"none")+"');";
    return ({ ([
      "event":s,
      "args":"onMouseOver=\""+s+"\""
    ]) });
  }
}

// Compatibility. The tag js-link is depricated.
static private string container_js_link(string name, mapping args,
					string contents, object id)
{
  args->onMouseOver = "clearToPopup('"+(id->misc->_popupparent||"none")+"')";
  return make_container_unquoted("a", args, contents);
}

static private
string container_js_popup(string name, mapping args, string contents, object id)
{
  // Link arguments.
  mapping largs = copy_value(args - (< "args-variable", "label", "props", "event",
				       "ox", "oy", "op" >));
  // Compatibility. The arguments 'ox', 'oy' and 'op' are depricated.
  if(!args->props && (args->ox || args->oy || args->op))
  {
    args->props = "new PopupProperties("+args->ox+", "+args->oy+")";
    if(args->op){
      args->props = "("+args->props+").setParentRightOffset("+args->op+")";
    }
  }
  
  if(!args->props)
    args->props = "default_props";
  if(!largs->href) 
    largs->href = "javascript:void(0);";
  string popupname = get_jss(id)->get_unique_id("popup");
  string popupparent =
    (id->misc->_popupparent?id->misc->_popupparent:"none");
  if(zero_type(id->misc->_popuplevel) && args["z-index"])
    id->misc->_popuplevel = (int)args["z-index"];

  string event = "onMouseOver";
  if(lower_case(args->event||"") == "onclick")
    event = "onClick";
  
  largs[event] = "return showPopup(event, '"+popupname+"', '"+popupparent+
		 "', "+args->props+");";
  
  get_jss(id)->get_insert("style")->
    add("#"+popupname+" {position:absolute; "
	"left:0; top:0; visibility:hidden; "+
	(id->supports->msie?"width:1; ":"")+
	"z-index:"+
	(id->misc->_popuplevel+1)+"}\n");
  
  string old_pparent = id->misc->_popupparent;
  id->misc->_popupparent = popupname;
  id->misc->_popuplevel++;
  
  get_jss(id)->get_insert("div")->
    add("<div id='"+popupname+"'>\n"+
	Roxen.parse_rxml(contents, id)+"</div>\n");
  
  id->misc->_popupparent = old_pparent;
  id->misc->_popuplevel--;
  id->misc->_popupname = popupname;
  
  if(args["args-variable"])
    id->variables[args["args-variable"]] = make_args_unquoted(largs);

  if(!args->label)
    return "";
  
  return make_container_unquoted("a", largs, args->label);
}

class TagJSInclude {
  inherit RXML.Tag;
  constant name = "js-include";

  class Frame {
    inherit RXML.Frame;

    array do_return(RequestID id) {
      if(!id->supports["javascript1.2"] &&
	 id->client_var && (float)(id->client_var->javascript) < 1.2)
	result = "<!-- Client do not support Javascript 1.2 -->"; // Throw an run_error instead?
      else
	result = "<script language=\"javascript\" src=\"" +
	  query_absolute_internal_location(id) + args->file + "\"></script>";
      return 0;
    }
  }
}

class TagJSInsert {
  inherit RXML.Tag;
  constant name = "js-insert";

  class Frame {
    inherit RXML.Frame;

    array do_return(RequestID id) {
      get_jss(id); // Signal that filter is necessary.
      result = Roxen.make_tag("js-filter-insert", args);
      return 0;
    }
  }
}

class TagJsExternal
{
  inherit RXML.Tag;
  constant name = "js-external";
  class Frame
  {
    inherit RXML.Frame;

    array do_return(RequestID id)
    {
      string key = Crypto.md5()->update(string_to_utf8(content))->digest();
      if(!externals[key])
	externals[key] = c_js_quote("", ([]), content);
      return ({ "<script language=\"javascript\" src=\""+
		query_absolute_internal_location(id)+"__ex/"+
		MIME.encode_base64(key)+"\"></script>" });
    }
  }
  
  void create()
  {
    externals = ([]);
  }
}

class TagJsDynamicPopupDiv
{
  inherit RXML.Tag;
  constant name = "js-dynamic-popup-div";
  class Frame
  {
    inherit RXML.Frame;

    array do_return(RequestID id)
    {
      if(id->supports->layer)
	result = ("<layer id=\""+args->name+"\" "
		  " visibility=\"hidden\" z-index:"+(args->zindex||"1")+"></layer>");
      else
	result = ("<div id=\""+args->name+"\""
		  " style=\"position:absolute; z-index:"+(args->zindex||"1")+
		  " left:0; top:0; visibility:hidden;\"></div>");
    }
  }
}

// Provider function
string js_dynamic_popup_event(string name, string src, string props)
{
  if(!props)
    props = "default_props";
  return "return loadLayer(event, \""+name+"\", \""+src+"\", "+props+");";
}

class TagEmitJsDynamicPopup {
  inherit RXML.Tag;
  constant name = "emit";
  constant plugin_name = "js-dynamic-popup";
  array get_dataset(mapping args, RequestID id)
  {
    return ({ ([ "event":js_dynamic_popup_event(args["name"],
						args["src"], args["props"]) ]) });
  }
}

mapping filter(mapping response, RequestID id)
{
  mixed c_filter_insert(Parser.HTML parser, mapping args, RequestID id)
  {
    JSInsert js_insert = get_jss(id)->get_insert(args->name);
    
    if(!js_insert)
      return "";
    
    if(args->name == "javascript1.2")
      return ({ "<script language='javascript1.2'><!--\n"+
		js_insert->get()+"//--></script>" });
    
    if(args->jswrite)
      return container_js_write("js-post-write", ([]), js_insert->get(), id);
    
    return js_insert->get();
  };

  if(!response			// 404
  || !response->type		// no response type
  || !jssp(id)			// nothing to filter
  || !stringp(response->data)	// got Stdio.File object
  || !glob("text/html*",	// only touch HTML files
	   response->type))
    return 0;			// signal "didn't rewrite result"

  response->data = Parser.HTML()->add_tag("js-filter-insert", c_filter_insert)->
		   set_extra(id)->finish(response->data)->read();
  return response;
}

mapping query_container_callers()
{
  return ([ "js-popup"       : container_js_popup,
	    "js-write"       : container_js_write,
	    "js-link"        : container_js_link,
  ]);
}

TAGDOCUMENTATION;
#ifdef manual

constant props_arg =
#"<p>A javascript PopupProperties object containing properties for the
  popup. PopupProperties is defined in the <i>Popup.js</i> component and takes
  two arguments: x, and y offsets from the target event for positioning
  of the popup at a desired location.</p>

  <p>There are some methods available in the object to set properties:</p>

  <list type=\"dl\">
    <item name=\"setHideDelay\"><p>
    The time in ms it takes before the popup is hidden when the mouse
    leaves the popup (default is 300 ms).</p></item>

    <item name=\"setParentRightOffset\"><p>
    The x offset from the parent popups right border. This offset
    will only be used if the popup has a parent popup i.e. not at the top
    level. This offset overrides the x_offset.</p></item>

    <item name=\"setParentBottomOffset\"><p>
    The y offset from the parent popups bottom border. This offset
    will only be used if the popup has a parent popup i.e. not at the top
    level. This offset overrides the y_offset.</p></item>
  </list>";

constant tagdoc = ([
"js-include":#"<desc>
  <p><short>Includes a javascript component.</short></p>
</desc>

<attr name='file' value='component' required='required'>
 <p>The component to include.</p>
</attr>",

//----------------------------------------------------------------------

"js-insert":#"<desc>
  <p><short>Inserts a javascript support string.</short></p>
</desc>

<attr name='name' value='string' required='required'>
  <p>The name of the javascript support string to insert.</p>
</attr>

<attr name='jswrite'>
  <p>The output will be turned into a javascript tag and written to
  the page with the <i>document.write</i> funtion. This is usefull for
  compatibility with browsers that has disabled javascript.</p>
</attr>",

//----------------------------------------------------------------------

"js-popup":#"<desc cont='cont'>
  <p><short hide=\"hide\">Creates a javascript popup.</short>
  This tag creates a popup of its content and returns a link that
  activates the popup if the cursor hovers over the link.</p>
  
  <p>This tag generates some javascript support strings that has to be
  inserted inte the page with the <tag>js-insert</tag> tag. The strings are:
  <i>div</i> and <i>style</i>.</p>

  <p>The components <tt>CrossPlatform.js</tt> and <tt>Popup.js</tt> must be
  included with the <tag>js-include</tag> tag in order to use this tag.</p>

  <p>All arguments exept those given below are also transferred to
  the link.</p>
</desc>

<attr name='label' value='string'>
  <p>The link text. If omitted no link will be returned, useful in
  combination with the args-variable argument.</p>
</attr>

<attr name='props' value='javascript object name' default='default_props'>"+
props_arg+
#"<p>A small example that uses a props object:</p>
  <ex type='box'>
<js-include file='CrossPlatform.js'/>
<js-include file='Popup.js'/>

<style><js-insert name='style'/></style>
<js-insert name='div'/>

<script language='javascript'>
  popup_props = new PopupProperties(15, 0);
  popup_props.setHideDelay(500);
</script>

<js-popup props='popup_props' label='popup'>
  <h1>This is a popup!</h1>
</js-popup></ex>
</attr>

<attr name='args-variable' value='RXML variable name'>
  <p>Arguments to the generated anchor tag will be stored in this variable.
  This argument is useful if the target to the popup should be an image,
  see the example below.</p>
  <ex type='box'>
<js-include file='CrossPlatform.js'/>
<js-include file='Popup.js'/>

<style><js-insert name='style'/></style>
<js-insert name='div'/>

<js-popup args-variable='popup-args'>
  <h1>This is a popup!</h1>
</js-popup>

<gtext ::='&form.popup-args;'>popup</gtext>
</ex>
</attr>

<attr name='event' value='javascript event' default='onMouseOver'>
  <p>The javascript event that should trigger the popup.</p>
</attr>

<attr name='z-index' value='number' default='1'>
  <p>The z index for the popup's div tag.</p>
</attr>",

//----------------------------------------------------------------------

"js-write":#"<desc cont='cont'>
  <p><short>Converts its content into javascript
  document.write.</short> The output will be turned into a javascript
  tag and written to the page with the <i>document.write</i> funtion.
  This is useful for compatibility with browsers that has disabled
  javascript.</p>
</desc>",

//----------------------------------------------------------------------

"emit#js-hide-popup":({ #"<desc plugin='plugin'>
  <p><short>Creates a link event to hide popups.</short>
  This plugin can be used in hierarchical menues on those links that are not
  popups, i.e. direct links on the same level as other links that leads to
  a popup.</p>
  <ex type='box'>
<js-include file='CrossPlatform.js'/>
<js-include file='Popup.js'/>

<style><js-insert name='style'/></style>
<js-insert name='div'/>

<emit source='js-hide-popup'>
  <a href='index.xml' ::='&_.args;'>Hide</a>
</emit><br />
<js-popup label='Show'>
    ...
</js-popup></ex>
</desc>",
([
  "&_.args;":#"<desc ent='ent'>
    <p>The javascript event arguments.</p>
  </desc>"
]) }),

//----------------------------------------------------------------------

"emit#js-dynamic-popup":({ #"<desc plugin='plugin'>
  <p><short>Creates a dynamic load popup.</short>
  This plugin creates a link to a dynamic loaded popup. The content of
  the popup will be loaded from the specified url.</p>

  <p>Before this tag can be used a layer with the same name as this popup
  must be created with the <tag>js-dynamic-popup-div</tag> tag.</p>

  <p>In order to use this tag the components; <tt>CrossPlatform.js</tt>,
  <tt>Popup.js</tt> and <tt>DynamicLoading.js</tt> must be included in
  the page with the <tag>js-include</tag> tag.</p>

  <p>Note that dynamic loaded layers don't work with Netscape 6 browsers.
  Please see the comment in the beginning of the <tt>DynamicLoading.js</tt>
  component file for more information.</p>
</desc>

<attr name='src' value='url' required='required'>
  <p>The page that should be loaded inte the popup.</p>
</attr>

<attr name='name' value='string' required='required'>
  <p>The name of the popup.</p>
</attr>

<attr name='props' value='javascript object name' default='default_props'>"+
props_arg+
#"</attr>

<p>An example that loads index.xml into a popup layer when the link is
clicked.</p>

<ex type='box'>
<js-include file='CrossPlatform.js'/>
<js-include file='Popup.js'/>
<js-include file='DynamicLoading.js'/>

<js-dynamic-popup-div name='popup'/>

<emit source='js-dynamic-popup' name='popup' src='index.xml'>
  <a href='javascript:void(0);' onClick='&_.event;'>Show</a>
</emit></ex>",
([
  "&_.event;":#"<desc ent='ent'>
    <p>The javascript event.</p>
  </desc>"
])}),

//----------------------------------------------------------------------

"js-dynamic-popup-div":#"<desc>
  <p><short>Creates a dynamic popup div/layer tag.</short> This tag
  creates a div or layer tag depending on the browser used. Use this
  tag together with the <tag>emit#js-dunamic-popup</tag> tag.</p>
</desc>

<attr name='name' value='string' required='required'>
  <p>The name of the div/layer.</p>
</attr>

<attr name='z-index' value='number' default='1'>
  <p>The z index for the div/layer.</p>
</attr>",

//----------------------------------------------------------------------

"js-external":#"<desc cont='cont'>
  <p><short hide='hide'>Creates an external javascript file of its
  content.</short> The tag creates an external javascript file
  containing the content of the tag in javascript
  <i>document.write</i> fashion. When the browser loads the document
  the external file will write the contents back to the document.</p>

  <p>This tag can be used to exclude some parts of the document, replacing
  each with a reference to an external file. By sharing fragments that are
  identical and occur in several pages, page loading time can be shortened.
  The gain depends on the cache policy of the browser.</p>

  <p>An important issue is that if the server uses a https port then
  the browsers won't cache the external files and using this tag will not
  result in increased performance.</p>

  <p>Note that it is not possible to put a <tag>js-insert</tag> tag inside
  this tag because that tag uses a filter module to insert its content.
  Other RXML tags should work, however.</p>

  <p>Note that this tag is not compatible with serverside persistent caching
  because the generated external file is only stored in the servers memory. A
  restart of the server will clear the information about the external files
  but the referenses to them do still exists in pages that are cached
  persistent.</p>
</desc>",

]);
#endif
