/*
 * $Id: pathinfo.pike,v 1.6 1999/10/10 19:16:37 per Exp $
 *
 * PATH_INFO support for Roxen.
 *
 * Henrik Grubbstr�m 1998-10-01
 */

#include <module.h>
#include <stat.h>

inherit "module";

constant cvs_version = "$Id: pathinfo.pike,v 1.6 1999/10/10 19:16:37 per Exp $";
constant thread_safe = 1;

// #define PATHINFO_DEBUG

array register_module()
{
  return ({ MODULE_LAST, "PATH_INFO support",
	    "Support for PATH_INFO style URLs.",
	    0, 1 });
}

mapping|int last_resort(object id)
{
#ifdef PATHINFO_DEBUG
  roxen_perror(sprintf("PATHINFO: Checking %O...\n", id->not_query));
#endif /* PATHINFO_DEBUG */
  if (id->misc->path_info) {
    // Already been here...
#ifdef PATHINFO_DEBUG
    roxen_perror(sprintf("PATHINFO: Been here, done that.\n"));
#endif /* PATHINFO_DEBUG */
    return 0;
  }

  string query = id->not_query;
  string pi = "";
  while( (search( query[1..], "/" ) != -1) && strlen( query ) > 0 )
  {
    query = reverse(query);
    string add_path_info;
    sscanf( query, "%[^/]/%s", add_path_info, query );
    query = reverse( query );
    if( strlen( pi ) )
      pi = "/"+reverse( add_path_info )+pi;
    else
      pi = "/"+add_path_info;
    id->misc->path_info = pi;
#ifdef PATHINFO_DEBUG
    roxen_perror("PATHINFO: Trying: %O (%O)\n", query, pi);
#endif 
    array st = id->conf->stat_file( query, id );
    if( st && (st[ ST_SIZE ] > 0))
    {
      id->not_query = query;
#ifdef PATHINFO_DEBUG
      roxen_perror("PATHINFO: Found: %O:%O\n",
                   id->not_query, id->misc->path_info);
#endif 
      return 1;
    }
  }
  return 0;
}
