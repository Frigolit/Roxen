inherit "../inheritinfo.pike";

string module_global_page( RequestID id, Configuration conf )
{
  switch( id->variables->action )
  {
   default:
     return "<insert file=global_module_page.inc nocache>\n";
   case "add_module":
     return "<insert file=add_module.inc nocache>\n";
   case "delete_module":
     return "<insert file=delete_module.inc nocache>\n";
  }
}

#define translate( X ) _translate( (X), id )

string _translate( mixed what, object id )
{
  if( mappingp( what ) )
    if( what[ id->misc->cf_locale ] )
      return what[ id->misc->cf_locale ];
    else
      return what->standard;
  return what;
}

string find_module_doc( string cn, string mn, object id )
{
  object c = roxen.find_configuration( cn );

  if(!c)
    return "";

  object m = c->find_module( replace(mn,"!","#") );

  if(!m)
    return "";

  return replace( "<p><b><font size=+2>"
                  + translate(m->register_module()[1]) + "</font></b><br>"
                  + translate(m->info()) + "<p>"
                  + translate(m->status()||"") +"<p>"+
                  ( id->misc->config_settings->query( "devel_mode" ) ?
                    "<hr noshade size=1><h2>Developer information</h2>"+
                    translate(m->file_name_and_stuff())
                    + "<dl>"+
                    rec_print_tree( Program.inherit_tree( object_program(m) ) )
                    +"</dl>" : ""),
                  ({ "/image/", }), ({ "/internal-roxen-" }));
}

string module_page( RequestID id, string conf, string module )
{
  while( id->misc->orig )
    id = id->misc->orig;
  if((id->variables->section == "Information") ||
     id->variables->info_section_is_it)
    return "<blockquote>"+find_module_doc( conf, module, id )+"</blockquote>";

  return #"<formoutput quote=\"�\">
  <cf-perm perm='Edit Module Variables'>
    <submit-gbutton align=right>Save all changes</submit-gbutton>
  </cf-perm>
 <input type=hidden name=section value=\"�section�\">
<table>
  <configif-output source=module-variables configuration=\""+
   conf+"\" section=\"�section:quote=dtag�\" module=\""+module+#"\">
    <tr><td width=20%><b>#name#</b></td><td>#form:quote=none#</td></tr>
    <tr><td colspan=2>#doc:quote=none#<p>#type_hint#</td></tr>
   </configif-output>
  </table>
  <cf-perm perm='Edit Module Variables'>
    <submit-gbutton align=right>Save all changes</submit-gbutton>
  </cf-perm>
</formoutput>";
}


string parse( RequestID id )
{
  array path = ((id->misc->path_info||"")/"/")-({""});
  
  if( !sizeof( path )  )
    return "Hm?";
  
  object conf = roxen->find_configuration( path[0] );
  id->misc->current_configuration = conf;

  if( sizeof( path ) == 1 )
  {
    /* Global information for the configuration */
  } else {
    switch( path[ 1 ] )
    {
     case "settings":
       return   
#"<formoutput quote=\"�\">
<input type=hidden name=section value=\"�section�\">
<table>
  <configif-output source=config-variables configuration=\""+
path[ 0 ]+#"\" section=\"�section:quote=dtag�\">
    <tr><td width=20%><b>#name#</b></td><td>#form:quote=none#</td></tr>
    <tr><td colspan=2>#doc:quote=none#<p>#type_hint#</td></tr>
   </configif-output>
  </table>
  <input type=submit value=\" Apply \" name=action>
</formoutput>";
       break;

     case "modules":
       if( sizeof( path ) == 2 )
         return module_global_page( id, path[0] );
       else
         return module_page( id, path[0], path[2] );
    }
  }
  return "";
}
