#include <module.h>

constant modules = ({});

constant silent_modules = ({}); 
//! Silent modules does not get their initial variables shown.

object load_modules(Configuration conf)
{
#ifdef THREADS
  Thread.MutexKey enable_modules_lock = conf->enable_modules_mutex->lock();
#else
  object enable_modules_lock;
#endif
  
  // The stuff below ought to be in configuration.pike and not here;
  // we have to meddle with locks and stuff that should be internal.

  foreach( modules, string mod )
  {
    RoxenModule module;

    // Enable the module but do not call start or save in the
    // configuration. Call start manually.
    if( !conf->find_module( mod ) &&
	(module = conf->enable_module( mod, 0, 0, 1, 1 )))
    {
      conf->call_low_start_callbacks( module, 
				      core.find_module( mod ), 
				      conf->modules[ mod ] );
    }
  }
  return enable_modules_lock;
}

void init_modules(Configuration conf, RequestID id)
{
}

string initial_form( Configuration conf, RequestID id, int setonly )
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
      if(moo->getvar( v )->check_visibility(id, 1, 0, 0, 1, 1))
      {
        num++;
        res += "<tr><td colspan='3'><h2>Initial variables for "+
	  Roxen.html_encode_string(mi->get_name())+"</h2></td></tr>"
        "<emit source='module-variables' "
	  " configuration=\""+conf->name+"\""
	  " module=\""+mod+#"\"/>";
	if( !setonly )
	  res += 
        "<emit noset='1' source='module-variables' "
	  " configuration=\""+conf->name+"\""
        " module=\""+mod+#"\">
 <tr>
 <td width='150' valign='top' colspan='2'><b>&_.name;</b></td>
 <td valign='top'><eval>&_.form:none;</eval></td></tr>
 <tr>
<td width='30'><img src='/$/unit' width=50 height=1 alt='' /></td>
  <td colspan=2>&_.doc:none;</td></tr>
 <tr><td colspan='3'><img src='/$/unit' height='18' /></td></tr>
</emit>";
        break;
      }
    }
  }
  return res;
}

int form_is_ok( RequestID id )
{
  Configuration conf = id->misc->new_configuration;
  foreach( modules, string mod )
  {
    ModuleInfo mi = core.find_module( mod );
    if( mi )
    {
      RoxenModule moo = conf->find_module( mod );
      if( moo )
      {
        foreach( indices(moo->query()), string v )
        {
          Variable.Variable va = moo->getvar( v );
          if( va->get_warnings() )
            return 0;
        }
      }
    }
  }
  foreach( indices( conf->query() ), string v )
  {
    Variable.Variable va = conf->getvar( v );
    if( va->get_warnings() )
      return 0;
  }
  return 1;
}

mixed parse( RequestID id, mapping|void opt )
{
  Configuration conf = id->misc->new_configuration;
  id->misc->do_not_goto = 1;  

  // Load initial modules
  object enable_modules_lock = load_modules(conf);
  
  string cf_form = 
    "<emit noset='1' source=config-variables configuration='"+conf->name+"'>"
    "  <tr><td colspan=2 valign=top width=20%><b>&_.name;</b></td>"
    "      <td valign=top><eval>&_.form:none;</eval></td></tr>"
    "  <tr><td></td><td colspan=2>&_.doc:none;<p>&_.type_hint;</td></tr>"
    "  <tr><td colspan='3'><img src='/$/unit' height='18' /></td></tr>"
    "</emit>";
  
  // set initial variables from form variables...
  Roxen.parse_rxml("<emit source=config-variables configuration='"+
		   conf->name+"'/>", id );
  Roxen.parse_rxml( initial_form( conf, id, 1 ), id );
  
  if( id->variables["ok.x"] && form_is_ok( id ) )
  {
    conf->set( "MyWorldLocation", Roxen.get_world(conf->query("URLs"))||"");
    foreach( modules, string mod )
    {
      RoxenModule module = conf->find_module( mod );
      if(module)
	conf->call_start_callbacks( module,
				    core.find_module( mod ),
				    conf->modules[ mod ] );
    }
    
    foreach( silent_modules, string mod )
    {
      ModuleInfo module = core.find_module(mod);
      conf->enable_module( mod );
    }

    init_modules( conf, id );

    conf->fix_no_delayed_load_flag();
    conf->save (1); // Call start callbacks and save it all in one go.
    conf->low_init (1); // Handle the init hooks.
    conf->forcibly_added = ([]);
    return "<done/>";
  }
  return
    "<h2>Initial variables for the site</h2>"
    "<table>" + cf_form + initial_form( conf, id, 0 ) + 
         ((opt||([]))->no_end_table?"":"</table><p>")+
         ((opt||([]))->no_ok?"":"<p align=right><cf-ok /></p>");
}
