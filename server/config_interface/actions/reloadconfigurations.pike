/*
 * $Id: reloadconfigurations.pike,v 1.5 2002/06/12 23:47:05 nilsson Exp $
 */

constant action = "maintenance";
constant name = "Reload configurations from disk";
constant doc  = ("Force a reload of all configuration information from "
		 "the configuration files.");

mixed parse( RequestID id )
{
  roxen->reload_all_configurations();
  return "All configurations reloaded from disk."
    "<p><cf-ok/></p>";
}
