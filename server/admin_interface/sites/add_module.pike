#include <admin_interface.h>
#include <module.h>
#include <module_constants.h>

//$Id: add_module.pike,v 1.86 2004/06/06 11:03:53 _cvs_stephen Exp $

int no_reload()
{
  if( sizeof( already_added ) )
    return 1; // Reloading this script now would destroy state.
}

// Class is the name of the directory.
array(string) class_description( string d, RequestID id )
{
  string name, doc;
  while(!(< "", "/" >)[d] && !file_stat( d+"/INFO" ))
    d = dirname(d);
  if((< "", "/" >)[d])
    return ({"Local modules", "" });

  string n = Stdio.read_bytes( d+"/INFO" );
  sscanf( n, "<"+id->misc->config_locale+">%s"
          "</"+id->misc->config_locale+">", n );
  sscanf( n, "%*s<name>%s</name>", name  );
  sscanf( n, "%*s<doc>%s</doc>", doc  );
  if( search(n, "<noshow/>" ) != -1 )
    return ({ "", "" });

  if(!name)
    return ({"Local modules", "" });

  if(!doc)
    doc ="";

  return ({ name, doc });
}

array(string) module_class( object m, RequestID id )
{
  return class_description( m->filename, id );
}

object module_nomore(string name, object modinfo, object conf)
{
  mapping module;
  object o;

  if(!modinfo)
    return 0;

  if(!modinfo->multiple_copies && (module = conf->modules[name]) &&
     sizeof(module->copies) )
    return modinfo;

  if(((modinfo->type & MODULE_DIRECTORIES) && (o=conf->dir_module))
     || ((modinfo->type & MODULE_AUTH)  && (o=conf->auth_module))
     || ((modinfo->type & MODULE_TYPES) && (o=conf->types_module)))
    return core.find_module( conf->otomod[o] );
}

// To redirect to when done with module addition
string site_url( RequestID id, string site )
{
  return "/sites/site.html/"+site+"/";
}

string page_base( RequestID id, string content, int|void noform )
{
  return sprintf( "<use file='/template' />\n"
                  "<tmpl title=' %s'%s>"
                  "<topmenu base='/' selected='sites'/>\n"
                  "<content><cv-split>"
                  "<subtablist width='100%%'>"
                  "<st-tabs></st-tabs>"
                  "<st-page>"
                  "<if not='1' variable='form.initial'>"
                  "<gbutton href='add_module.pike?config=&form.config:http;"
                  "&reload_module_list=yes' "
		  "> %s </gbutton> "
                  "<gbutton href='site.html/&form.config;/' "
		  "> %s </gbutton>"
                  "<p>\n</if>%s\n</p>\n"
                  "</st-page></subtablist></td></tr></table>"
                  "</cv-split></content></tmpl>", 
		  "Add module",
		  noform?" noform='noform'":"",
                  "Reload module list",
		  "Cancel", content );
}



string module_name_from_file( string file )
{
  string data, name;

  catch(data = Stdio.read_bytes( file ));
  
  if( data
      && sscanf( data, "%*smodule_name%*s=%[^;];", name )
      && sscanf( name, "%*[^\"]\"%s\"", name ) )
    return Roxen.html_encode_string(name);
  return Roxen.html_encode_string(((file/"/")[-1]/".")[0]);
}

string pafeaw( string errors, string warnings)
// Parse And Format Errors And Warnings.
// Your ordinary prettyprinting function.
{
  mapping by_module = ([]);
  int cnt = 0;
  foreach( (errors+warnings)/"\n", string e )
  {
    string file;
    int row;
    string type, error;
    sscanf( e, "%s:%d%s", file, row, error );
    if( error )
    {
      sscanf( error, "%*[ \t]%s", error );
      sscanf( error, "%s: %s", type, error );
      if( by_module[ file ] )
        by_module[ file ] += ({ ({ row*10000 + cnt++, row, type, error }) });
      else
        by_module[ file ] = ({ ({ row*10000 + cnt++, row, type, error }) });
    }
  }


  string da_string = "";

  int header_added;
  foreach( sort((array)by_module), [string module, array errors] )
  {
    array res = ({ });
    int remove_suspicious = 0;
    sort( errors );
    foreach( errors, array e )
    { 
      if( e[2]  == "Error" )
      {
        remove_suspicious = 1;
        switch( e[3] )
        {
         case "Must return a value for a non-void function.":
         case "Class definition failed.":
         case "Illegal program pointer.":
         case "Illegal program identifier":
           continue;
        }
      }
      res += ({ e });
    }
    if( sizeof( res ) )
    {
      string he( string what )
      {
        if( what == "Error" )
          return "<font color='&usr.warncolor;'>"+what+"</font>";
        return what;
      };

      string hc( string what )
      {
        return what;
      };

      string trim_name( string what )
      {
        array q = (what / "/");
        return q[sizeof(q)-2..]*"/";
      };

#define RELOAD(X) sprintf("<gbutton "                                         \
			  "img-align='middle' "                               \
                          "href='add_module.pike?config=&form.config:http;"   \
                          "&random=%d&only=%s&reload_module_list=yes#"        \
                          "errors_and_warnings'> %s </gbutton>",              \
                          random(4711111),                                    \
                          (X),                                                \
                          "Reload")

      if( !header_added++ )
        da_string += 
                  "<p><a name='errors_and_warnings'></a><br />"
                  "<font size='+2'><b><font color='&usr.warncolor;'>"
                  "Compile errors and warnings</font></b><br />"
                  "<table width=100% cellpadding='3' cellspacing='0' border='0'>";

      da_string += "<tr><td></td>"
                "<td colspan='3' bgcolor='&usr.content-titlebg;'>"
                + "<b><font color='&usr.content-titlefg;' size='+1'>"
                + module_name_from_file(module)+"</font></b></td>"
                + "<td align='right' bgcolor='&usr.content-titlebg;'>"
                "<font color='&usr.content-titlefg;' size='+1'>"
                + trim_name(module)
                + "</font>&nbsp;"+RELOAD(module)+"</td><td></td></tr>";

      foreach( res, array e )
        da_string += 
                  "<tr valign='top'><td></td><td><img src='/$/unit' width='30' height='1' alt='' />"
                  "</td><td align='right'>"
                  "<tt>"+e[1]+":</tt></td><td align='right'><tt>"+
                  he(e[2])+":</tt></td><td><tt>"+hc(e[3])+"</tt></td></tr>\n";
      da_string += "<tr valign='top'><td colspan='5'>&nbsp;</td><td></td></tr>\n";

    }
  }
  if( sizeof( da_string ) )
    da_string += "</table>";
// "<pre>"+Roxen.html_encode_string( sprintf( "%O", by_module ) )+"</pre>";
  
  return da_string;
}

array(string) get_module_list( function describe_module,
                               function class_visible,
                               RequestID id )
{
  object conf = core.find_configuration( id->variables->config );
  object ec = loader.LowErrorContainer();
  int do_reload;
  master()->set_inhibit_compile_errors( ec );

  if( id->variables->reload_module_list )
    core->clear_all_modules_cache();

  array(ModuleInfo) mods;
  loader.push_compile_error_handler( ec );
  mods = core->all_modules();
  loader.pop_compile_error_handler();

  foreach( mods, ModuleInfo m )
    if( module_nomore( m->sname, m, conf ) )
      mods -= ({ m });

  string res = "";
  string doubles="", already="";
  array w = map(mods, module_class, id);

  mapping classes = ([]);
  sort(w,mods);
  for(int i=0; i<sizeof(w); i++)
  {
    mixed r = w[i];
    if(!classes[r[0]])
      classes[r[0]] = ([ "doc":r[1], "modules":({}) ]);
    if( mods[i]->get_description() )
      classes[r[0]]->modules += ({ mods[i] });
  }

  foreach( sort(indices(classes)), string c )
  {
    mixed r;
    if( c == "" )
      continue;
    if( (r = class_visible( c, classes[c]->doc, sizeof(classes[c]->modules), id )) &&
	r[0] )
    {
      res += r[1];
      array m = classes[c]->modules;
      array q = m->get_name();
      sort( q, m );
      foreach(m, object q)
      {
        if( q->get_description() == "Undocumented" &&
            q->type == 0 )
          continue;
        object b = module_nomore(q->sname, q, conf);
        res += describe_module( q, b );
      }
    } else
      res += r[1];
  }
  master()->set_inhibit_compile_errors( 0 );
  return ({ res, pafeaw( ec->get(), ec->get_warnings()) });
}

string module_image( int type )
{
  return "";
}

string strip_leading( string what )
{
  if( !what ) return 0;
  sscanf( (string)what, "%*s:%*[ \t]%s", what );
  return what;
}


function describe_module_normal( int image )
{
  return lambda( object module, object block)
  {
    if(!block)
    {
      return sprintf(
	#"
  <tr>
   <td colspan='2'>
     <table width='100%%'>
      <tr>
       <td><font size='+2'>%s</font></td>
       <td align='right'>(%s) %s</td>
      </tr>
     </table>
     </td>
   </tr>
   <tr>
     <td valign='top'>
       <form method='post' action='add_module.pike'>
         <roxen-automatic-charset-variable/>
         <input type='hidden' name='module_to_add' value='%s'>
         <input type='hidden' name='config' value='&form.config;'>
         <submit-gbutton preparse='1'>%s</submit-gbutton>
       </form>
     </td>
     <td valign='top'>
        %s
       <p>
         %s
       </p>
    </td>
  </tr>
",
	//Roxen.html_encode_string(strip_leading(module->get_name())),
	Roxen.html_encode_string(module->get_name()),
	Roxen.html_encode_string (module->sname),
	(image?module_image(module->type):""),
     module->sname,
   "Add Module",
   module->get_description(),
     "Will be loaded from: "+module->filename
);
    } else {
      if( block == module )
        return "";
      return "";
    }
  };
}

array(int|string) class_visible_normal( string c, string d, int size,
					RequestID id )
{
  int x;
  string header = ("<tr><td colspan='2'><table width='100%' "
                   "cellspacing='0' border='0' cellpadding='3' "
                   "bgcolor='&usr.content-titlebg;'><tr><td>");

  if( id->variables->unfolded == c ) {
    header+=("<a name="+Roxen.http_encode_string(c)+
	     "></a><gbutton "
	     "href='add_module.pike?config=&form.config;"
	     "#"+Roxen.http_encode_string(c)+"' > Hide </gbutton>");
    x=1;
  }
  else
    header+=("<a name="+Roxen.http_encode_string(c)+
	     "></a><gbutton "
	     "href='add_module.pike?config=&form.config;"
	     "&unfolded="+Roxen.http_encode_string(c)+
	     "#"+Roxen.http_encode_string(c)+"' > View </gbutton>");

  header+=("</td><td width='100%'>"
	   "<font color='&usr.content-titlefg;' size='+2'>"+c+"</font>"
	   "<br />"+d+"</td></tr></table></td></tr>\n");

  return ({ x, header });
}

string page_normal( RequestID id, int|void noimage )
{
  string content = "";
  content += "<table>";
  string desc, err;
  [desc,err] = get_module_list( describe_module_normal(!noimage),
                                class_visible_normal, id );
  content += (desc+"</table>"+err);
  return page_base( id, content, 1 );
}

string page_fast( RequestID id )
{
  return page_normal( id, 1 );
}

string describe_module_faster( object module, object block)
{
  if(!block)
  {
return sprintf(
   #"
    <tr><td colspan='2'><table width='100%%'>
        <td><font size='+2'>%s</font></td>
        <td align='right'>(%s) %s</td></table></td></tr>
    <tr><td valign='top'><select multiple='multiple' name='module_to_add'>
                       <option value='%s'>%s</option></select>
        </td><td valign='top'>%s<p>%s</p></td>
    </tr>
",
   //Roxen.html_encode_string(strip_leading(module->get_name())),
   Roxen.html_encode_string(module->get_name()),
   Roxen.html_encode_string (module->sname),
   module_image(module->type),
   module->sname,
   //Roxen.html_encode_string(strip_leading(module->get_name())),
   Roxen.html_encode_string(module->get_name()),
   module->get_description(),
   "Will be loaded from: "+module->filename
  );
  } else {
    if( block == module )
      return "";
    return "";
  }
}

array(int|string) class_visible_faster( string c, string d, int size,
					RequestID id )
{
  int x;
  string header = ("<tr><td colspan='2'><table width='100%' cellspacing='0' "
                   "border='0' cellpadding='3' bgcolor='&usr.content-titlebg;'>"
                   "<tr><td>");

  if( id->variables->unfolded == c ) {
    header+=("<a name="+Roxen.http_encode_string(c)+
	     "></a><gbutton dim='1'> View </gbutton>"
	     "<tr><td><submit-gbutton> Add Module"
	     " </submit-gbutton></td></tr>");
    x=1;
  }
  else
    header+=("<a name="+Roxen.http_encode_string(c)+
	     "></a><gbutton "
	     "href='add_module.pike?config=&form.config;"
	     "&unfolded="+Roxen.http_encode_string(c)+
	     "#"+Roxen.http_encode_string(c)+"' > View </gbutton>");

  header+=("</td><td width='100%'>"
	   "<font color='&usr.content-titlefg;' size='+2'>"+c+"</font>"
	   "<br />"+d+"</td></tr></table></td></tr>\n");

  return ({ x, header });
}

string page_faster( RequestID id )
{
  string content = "";
  content += "<form method='post' action='add_module.pike'>"
             "<input type='hidden' name='config' value='&form.config;'>"
             "<table>";
  string desc, err;
  [desc,err] = get_module_list( describe_module_faster,
                                class_visible_faster, id );
  content += (desc+"</table></form>"+err);
  return page_base( id, content );
}

int first;

array(int|string) class_visible_compact( string c, string d, int size,
					 RequestID id )
{
  string res="";
  if(first++)
    res = "</select><br /><submit-gbutton> Add Module </submit-gbutton> ";
  res += "<p><a name="+Roxen.http_encode_string(c)+
    "></a><font size='+2'>"+c+"</font><br />"+d+"<p>"
    "<select size='"+size+"' multiple name='module_to_add' class='add-module-select'>";
  return ({ 1, res });
}

string describe_module_compact( object module, object block )
{
  if(!block) {
    //string modname = strip_leading (module->get_name());
    string modname = module->get_name();
    return "<option value='"+module->sname+"'>"+
      Roxen.html_encode_string(modname)
      + "&nbsp;" * max (0, (int) ((49 - sizeof (modname)))) +
      " (" + Roxen.html_encode_string(module->sname) + ")"+
      "</option>\n";
  }
  return "";
}

string page_compact( RequestID id )
{
  first=0;
  string desc, err;
  [desc,err] = get_module_list( describe_module_compact,
                                class_visible_compact, id );
  return page_base(id,
                   "<form action='add_module.pike' method='POST'>"
                   "<input type='hidden' name='config' value='&form.config;'>"+
                   desc+"</select><br /><submit-gbutton> "
                   "Add Module </submit-gbutton><p>"
                   +err+"</form>",
                   );
}

string page_really_compact( RequestID id )
{
  first=0;

  object conf = core.find_configuration( id->variables->config );
  object ec = loader.LowErrorContainer();
  master()->set_inhibit_compile_errors( ec );

  if( id->variables->reload_module_list )
  {
    if( id->variables->only )
    {
      master()->clear_compilation_failures();
      m_delete( core->modules, (((id->variables->only/"/")[-1])/".")[0] );
      core->all_modules_cache = 0;
    }
    else
      core->clear_all_modules_cache();
  }

  array mods;
  loader.push_compile_error_handler( ec );
  mods = core->all_modules();
  loader.pop_compile_error_handler();

  sort(map(mods->get_name(), lower_case), mods);
  string res = "";

  mixed r;

  if( (r = class_visible_compact( "Add module",
				  "Select one or several modules to add.",
				  sizeof(mods), id )) && r[0] ) {
    res += r[1];
    foreach(mods, object q) {
      if( (!q->get_description() ||
	   (q->get_description() == "Undocumented")) &&
	  q->type == 0 )
	continue;
      object b = module_nomore(q->sname, q, conf);
      res += describe_module_compact( q, b );
    }
  } else
    res += r[1];

  master()->set_inhibit_compile_errors( 0 );

  return page_base(id,
                   "<form action=\"add_module.pike\" method=\"post\">"
                   "<input type=\"hidden\" name=\"config\" value=\"&form.config;\" />"+
                   res+"</select><br /><submit-gbutton> "
                   "Add Module </submit-gbutton><br />"
                   +pafeaw(ec->get(),ec->get_warnings())+"</form>",
                   );
}

string decode_site_name( string what )
{
  if( (int)what ) 
    return (string)((array(int))(what/","-({""})));
  return what;
}




array initial_form( RequestID id, Configuration conf, array modules )
{
  id->variables->initial = "1";
  id->real_variables->initial = ({ "1" });

  string res = "";
  int num;

  foreach( modules, string mod )
  {
    ModuleInfo mi = core.find_module( (mod/"!")[0] );
    RoxenModule moo = conf->find_module( replace(mod,"!","#") );
    foreach( indices(moo->query()), string v )
    {
      if( moo->getvar( v )->get_flags() & VAR_INITIAL )
      {
        num++;
        res += "<tr><td colspan='3'><h2>"
        "Initial variables for "+
	  //Roxen.html_encode_string(strip_leading(mi->get_name()))
	  Roxen.html_encode_string(mi->get_name())
	  +"</h2></td></tr>"
        "<emit source='module-variables' "
	  " configuration=\""+conf->name+"\""
        " module=\""+mod+#"\"/>
        <emit noset='1' source='module-variables' "
	  " configuration=\""+conf->name+"\""
        " module=\""+mod+#"\">
 <tr>
 <td width='150' valign='top' colspan='2'><b>&_.name;</b></td>
 <td valign='top'><eval>&_.form:none;</eval></td></tr>
 <tr>
<td width='30'><img src='/$/unit' width=50 height=1 alt='' /></td>
  <td colspan=2>&_.doc:none;</td></tr>
 <tr><td colspan='3'><img src='/$/unit' height=18 width=1 alt='' /></td></tr>
</emit>";
        break;
      }
    }
  }
  return ({res,num});
}

mapping already_added =  ([]);

mixed do_it_pass_2( array modules, Configuration conf,
                    RequestID id )
{
  id->misc->do_not_goto = 1;  
  foreach( modules, string mod ) 
  {
    if( already_added[mod] )
      mod = already_added[ mod ];
    if( !has_value(mod, "!") || !conf->find_module( replace(mod,"!","#") ) )
    {
      RoxenModule mm = conf->enable_module( mod,0,0,1 );
      if( !mm || !conf->otomod[mm] )
      {
	report_error("Failed to enable %s\n", mod);
	return Roxen.http_redirect( site_url(id,conf->name), id );
      }      
      conf->call_low_start_callbacks( mm, 
                                      core.find_module( (mod/"!")[0] ), 
                                      conf->modules[ mod ] );
      modules = replace( modules, mod,
			 (already_added[mod]=(mod/"!")[0]+"!"+
			  (conf->otomod[mm]/"#")[-1]) );
    }
    remove_call_out( core.really_save_it );
  }

  [string cf_form, int num] = initial_form( id, conf, modules );
  if( !num || id->variables["ok.x"] )
  {
    // set initial variables from form variables...
    if( num ) Roxen.parse_rxml( cf_form, id );
    foreach( modules, string mod )
     conf->call_high_start_callbacks( conf->find_module( replace(mod,"!","#") ),
				      core.find_module( (mod/"!")[0] ) );
    already_added = ([ ]);
    conf->save( ); // save it all in one go
    conf->forcibly_added = ([]);
    return Roxen.http_redirect(
      site_url(id,conf->name)+"-!-/"+modules[-1]+"/" ,
      id);
  }
  return page_base(id,"<table>"+
                   map( modules, lambda( string q ) {
                                   return "<input type='hidden' "
                                          "name='module_to_add' "
                                          "value='"+q+"' />";
                                 } )*"\n" 
                   +"<input type='hidden' name='config' "
		   "value='"+conf->name+"' />"+cf_form+"</table><p><cf-ok />");
}

mixed do_it( RequestID id )
{
  if( id->variables->encoded )
    id->variables->config = decode_site_name( id->variables->config );

  Configuration conf;
  foreach(id->variables->config/"\0", string config) {
    if (conf = core.find_configuration( id->variables->config )) {
      id->variables->config = config;
      break;
    }
  }

  if (!conf) {
    return sprintf("Configuration %O not found.",
		   id->variables->config);
  }

  if( !conf->inited )
    conf->enable_all_modules();

  array modules = (id->variables->module_to_add/"\0")-({""});
  if( !sizeof( modules ) )
    return Roxen.http_redirect( site_url(id,conf->name ), id );
  return do_it_pass_2( modules, conf, id );
}

mixed parse( RequestID id )
{
  if( !config_perm( "Add Module" ) )
    return "Permission denied";

  if( id->variables->module_to_add &&
      id->variables->config )
    return do_it( id );

  Configuration conf;
  foreach(id->variables->config/"\0", string config) {
    if (conf = core.find_configuration( id->variables->config )) {
      id->variables->config = config;
      break;
    }
  }

  if( !config_perm( "Site:"+conf->name ) )
    return "Permission denied";

  if( !conf->inited )
    conf->enable_all_modules();

  return this["page_"+replace(config_setting( "addmodulemethod" )," ","_")]( id );
}
