string module_global_page( RequestID id, Configuration conf )
{
  switch( id->variables->action )
  {
   default:
     return "<insert file=global_module_page.inc nocache>\n";
   case "add_module":
     return "<insert file=add_module.inc nocache>\n";
   case "delete_module":
     return "<insert file=add_module.inc nocache>\n";
  }
}

string module_page( RequestID id, string conf, string module )
{
//   if( id->variables->section )
//   {
//     werror("hmm\n");
return #"<formoutput quote=\"�\">
<input type=hidden name=section value=\"�section�\">
<table>
  <configif-output source=module-variables configuration=\""+
   conf+"\" section=\"�section:quote=dtag�\" module=\""+module+#"\">
    <tr><td width=20%><b>#name#</b></td><td>#form:quote=none#</td></tr>
    <tr><td colspan=2>#doc:quote=none#<p>#type_hint#</td></tr>
   </configif-output>
  </table>
  <input type=submit value=\" Apply \" name=action>
</formoutput>";
    
//   } else {
    
//   }
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


  return sprintf( "Path info: %O\n", path );
}
