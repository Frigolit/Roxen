#include <module.h>

string cvs_version = "$Id: servlet.pike,v 1.3 1999/05/31 22:19:32 js Exp $";
int thread_safe=1;

inherit "module";
static inherit "http";

#if constant(Java)

object servlet;

string status_info="";

array register_module()
{
  return ({
    MODULE_LOCATION, "Java Servlet bridge",
    "An interface to Java <a href=\"http://jserv.javasoft.com/"
    "products/java-server/servlets/index.html\">Servlets</a>.",
    0
  });
}

void stop()
{
  if(servlet) {
    destruct(servlet);
    servlet = 0;
  }
}

static mapping(string:string) make_initparam_mapping()
{
  mapping(string:string) p = ([]);
  string n, v;
  foreach(QUERY(parameters)/"\n", string s)
    if(2==sscanf(s, "%[^=]=%s", n, v))
      p[n]=v;
  return p;
}

void start(int x, object conf)
{
  if(x == 2)
    stop();
  else if(x != 0)
    return;

  mixed exc = catch(servlet = Servlet.servlet(QUERY(classname),
					      QUERY(codebase)));
  status_info="";
  if(exc)
  {
    werror(exc[0]);
    status_info=sprintf("<pre>%s</pre>",exc[0]);
  }
  else
    if(servlet)
      servlet->init(Servlet.conf_context(conf), make_initparam_mapping());
}

string status()
{
  return (servlet?
	  servlet->info() || "<i>No servlet information available</i>" :
	  "<font color=red>Servlet not loaded</font>"+"<br>"+
	  status_info);
}

string query_location()
{
  return QUERY(mountpoint);
}

string query_name()
{
  return sprintf("<i>%s</i> mounted on <i>%s</i>", query("classname"),
		 query("mountpoint"));
}

void create()
{
  defvar("mountpoint", "/servlet/NONE", "Servlet location", TYPE_LOCATION,
	 "This is where the servlet will be inserted in the "
	 "namespace of your server.");

  defvar("codebase", "servlets", "Code directory", TYPE_DIR,
	 "This is the base directory for the servlet class files.");

  defvar("classname", "NONE", "Class name", TYPE_STRING,
	 "The name of the servlet class to use.");

  defvar("parameters", "", "Parameters", TYPE_TEXT,
	 "Parameters for the servlet on the form "
	 "<tt><i>name</i>=<i>value</i></tt>, one per line.");

}


mixed find_file( string f, object id )
{
  if(!servlet)
  {
    string res = sprintf("<h1>Servlet loading failed</h1>%s",status_info);
    return http_string_answer(res);
  }
  id->my_fd->set_read_callback(0);
  id->my_fd->set_close_callback(0);
  id->my_fd->set_blocking();
  id->misc->path_info = f;
  id->misc->mountpoint = QUERY(mountpoint);
  servlet->service(id);

  return http_pipe_in_progress();
}

#endif
