/*
 * $Id: flush.pike,v 1.6 2000/08/16 14:48:17 lange Exp $
 */
#include <config_interface.h>
#include <roxen.h>
//<locale-token project="admin_tasks"> LOCALE </locale-token>
#define LOCALE(X,Y)  _STR_LOCALE("admin_tasks",X,Y)

constant action = "maintenance";

string name= LOCALE(8, "Flush caches");
string doc = LOCALE(9, "Flush all memory caches.");


mixed doit()
{
  /* Flush the userdb. */
  foreach(roxen->configurations, object c)
    if(c->modules["userdb"] && c->modules["userdb"]->master)
      c->modules["userdb"]->master->read_data();

  /* Flush the memory cache. */
  cache.flush_memory_cache();

  /* Flush the dir cache. */
  foreach(roxen->configurations, object c)
    if(c->modules["directories"] && (c=c->modules["directories"]->enabled))
    {
      catch{
	c->_root->dest();
	c->_root = 0;
      };
    }

  /* Flush the module cache. */
  foreach( indices( roxen->module_cache ), string q )
    roxen->module_cache->delete( q );
  roxen->modules = ([ ]);

  gc();
}

mixed parse( RequestID id )
{
  doit();
  return LOCALE(232,"All memory caches have been flushed.") + 
         "<p><cf-ok/></p>";
}
