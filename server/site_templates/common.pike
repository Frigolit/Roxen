#include <module.h>
#include <roxen.h>
//<locale-token project="roxen_config">LOCALE</locale-token>
#define LOCALE(X,Y)	_STR_LOCALE("roxen_config",X,Y)

constant modules = ({});

constant silent_modules = ({}); 
//! Silent modules does not get their initial variables shown.

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
    ModuleInfo mi = roxen.find_module( (mod/"!")[0] );
    RoxenModule moo = conf->find_module( replace(mod,"!","#") );
    foreach( indices(moo->query()), string v )
    {
      if( moo->getvar( v )->get_flags() & VAR_INITIAL )
      {
        num++;
        res += "<tr><td colspan='3'><h2>"
        +LOCALE(1,"Initial variables for ")+
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
<td width='30'><img src='/internal-roxen-unit' width=50 height=1 alt='' /></td>
  <td colspan=2>&_.doc:none;</td></tr>
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
    ModuleInfo mi = roxen.find_module( mod );
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

#ifdef THREADS
  Thread.MutexKey enable_modules_lock = conf->enable_modules_mutex->lock();
#endif
  // The stuff below ought to be in configuration.pike and not here;
  // we have to meddle with locks and stuff that should be internal.

  foreach( modules, string mod )
  {
    RoxenModule module;
    
    if( !conf->find_module( mod ) && (module = conf->enable_module( mod, 0, 0, 1 )))
    {
      conf->call_low_start_callbacks( module, 
				      roxen.find_module( mod ), 
				      conf->modules[ mod ] );
    }
    remove_call_out( roxen.really_save_it );
  }

  string cf_form = 
    "<emit noset='1' source=config-variables configuration='"+conf->name+"'>"
    "  <tr><td colspan=2 valign=top width=20%><b>&_.name;</b></td>"
    "      <td valign=top><eval>&_.form:none;</eval></td></tr>"
    "  <tr><td></td><td colspan=2>&_.doc:none;<p>&_.type_hint;</td></tr>"
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
				    roxen.find_module( mod ),
				    conf->modules[ mod ] );
    }
    
    foreach( silent_modules, string mod )
      conf->enable_module( mod );

    init_modules( conf, id );

    conf->fix_no_delayed_load_flag();
    conf->save (1); // Call start callbacks and save it all in one go.
    conf->low_init (1); // Handle the init hooks.
    return "<done/>";
  }
  return
    "<h2>"+LOCALE(190,"Initial variables for the site")+"</h2>"
    "<table>" + cf_form + initial_form( conf, id, 0 ) + 
         ((opt||([]))->no_end_table?"":"</table><p>")+
         ((opt||([]))->no_ok?"":"<p align=right><cf-ok /></p>");
}
