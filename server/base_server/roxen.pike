/*
 * $Id: roxen.pike,v 1.311 1999/07/31 18:43:37 js Exp $
 *
 * The Roxen Challenger main program.
 *
 * Per Hedbor, Henrik Grubbstr�m, Pontus Hagland, David Hedbor and others.
 */

// ABS and suicide systems contributed freely by Francesco Chemolli
constant cvs_version="$Id: roxen.pike,v 1.311 1999/07/31 18:43:37 js Exp $";

object backend_thread;
object argcache;

// Some headerfiles
#define IN_ROXEN
#include <roxen.h>
#include <config.h>
#include <module.h>
#include <variables.h>

// Inherits
inherit "read_config";
inherit "hosts";
inherit "module_support";
inherit "socket";
inherit "disk_cache";
inherit "language";


/*
 * Version information
 */
constant __roxen_version__ = "1.4";
constant __roxen_build__ = "37";

#ifdef __NT__
constant real_version = "Roxen Challenger/"+__roxen_version__+"."+__roxen_build__+" NT";
#else
constant real_version = "Roxen Challenger/"+__roxen_version__+"."+__roxen_build__;
#endif


// Prototypes for other parts of roxen.
class RequestID 
{
  object conf; // Really Configuration, but that's sort of recursive.
  int time;
  string raw_url;
  int do_not_disconnect;
  mapping (string:string) variables;
  mapping (string:mixed) misc;
  mapping (string:string) cookies;
  mapping (string:string) request_headers;
  multiset(string) prestate;
  multiset(string) config;
  multiset(string) supports;
  multiset(string) pragma;
  array(string) client;
  array(string) referer;

  Stdio.File my_fd;
  string prot;
  string clientprot;
  string method;
  
  string realfile;
  string virtfile;
  string rest_query;
  string raw;
  string query;
  string not_query;
  string extra_extension;
  string data;
  string leftovers;
  array (int|string) auth;
  string rawauth;
  string realauth;
  string since;
  string remoteaddr;
  string host;

  void create(object|void master_request_id);
  void send(string|object what, int|void len);
  string scan_for_query( string in );
  void end(string|void s, int|void keepit);
  void ready_to_receive();
  void send_result(mapping|void result);
  RequestID clone_me();
};


constant pipe = (program)"smartpipe";

/*
 * The privilege changer.
 *
 * Based on privs.pike,v 1.36.
 */

// Some variables used by Privs
#ifdef THREADS
// This mutex is used by Privs
object euid_egid_lock = Thread.Mutex();
#endif /* THREADS */

int privs_level;

static class Privs {
#if efun(seteuid)

  int saved_uid;
  int saved_gid;

  int new_uid;
  int new_gid;

#define LOGP (variables && variables->audit && GLOBVAR(audit))

#if constant(geteuid) && constant(getegid) && constant(seteuid) && constant(setegid)
#define HAVE_EFFECTIVE_USER
#endif

  static private string _getcwd()
  {
    if (catch{return(getcwd());}) {
      return("Unknown directory (no x-bit on current directory?)");
    }
  }

  static private string dbt(array t)
  {
    if(!arrayp(t) || (sizeof(t)<2)) return "";
    return (((t[0]||"Unknown program")-(_getcwd()+"/"))-"base_server/")+":"+t[1]+"\n";
  }

#ifdef THREADS
  static mixed mutex_key;	// Only one thread may modify the euid/egid at a time.
  static object threads_disabled;
#endif /* THREADS */

  int p_level;

  void create(string reason, int|string|void uid, int|string|void gid)
  {
#ifdef PRIVS_DEBUG
    werror(sprintf("Privs(%O, %O, %O)\n"
		   "privs_level: %O\n",
		   reason, uid, gid, privs_level));
#endif /* PRIVS_DEBUG */

#ifdef HAVE_EFFECTIVE_USER
    array u;

#ifdef THREADS
    if (euid_egid_lock) {
      catch { mutex_key = euid_egid_lock->lock(); };
    }
    threads_disabled = _disable_threads();
#endif /* THREADS */

    p_level = privs_level++;

    if(getuid()) return;

    /* Needs to be here since root-priviliges may be needed to
     * use getpw{uid,nam}.
     */
    saved_uid = geteuid();
    saved_gid = getegid();
    seteuid(0);

    /* A string of digits? */
    if (stringp(uid) && ((int)uid) &&
	(replace(uid, ({ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" }),
		 ({ "", "", "", "", "", "", "", "", "", "" })) == "")) {
      uid = (int)uid;
    }
    if (stringp(gid) && ((int)gid) &&
	(replace(gid, ({ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" }),
		 ({ "", "", "", "", "", "", "", "", "", "" })) == "")) {
      gid = (int)gid;
    }

    if(!stringp(uid)) {
      u = getpwuid(uid);
    } else {
      u = getpwnam(uid);
      if(u) 
	uid = u[2];
    }

    if(u && !gid) gid = u[3];
  
    if(!u) {
      if (uid && (uid != "root")) {
	if (intp(uid) && (uid >= 60000)) {
	  report_warning(sprintf("Privs: User %d is not in the password database.\n"
				 "Assuming nobody.\n", uid));
	  // Nobody.
	  gid = gid || uid;	// Fake a gid also.
	  u = ({ "fake-nobody", "x", uid, gid, "A real nobody", "/", "/sbin/sh" });
	} else {
	  error("Unknown user: "+uid+"\n");
	}
      } else {
	u = ({ "root", "x", 0, gid, "The super-user", "/", "/sbin/sh" });
      }
    }

    if(LOGP)
      report_notice(sprintf("Change to %s(%d):%d privs wanted (%s), from %s",
			    (string)u[0], (int)uid, (int)gid,
			    (string)reason,
			    (string)dbt(backtrace()[-2])));

#if efun(cleargroups)
    catch { cleargroups(); };
#endif /* cleargroups */
#if efun(initgroups)
    catch { initgroups(u[0], u[3]); };
#endif
    gid = gid || getgid();
    int err = (int)setegid(new_gid = gid);
    if (err < 0) {
      report_debug(sprintf("Privs: WARNING: Failed to set the effective group id to %d!\n"
			   "Check that your password database is correct for user %s(%d),\n"
			   "and that your group database is correct.\n",
			   gid, (string)u[0], (int)uid));
      int gid2 = gid;
#ifdef HPUX_KLUDGE
      if (gid >= 60000) {
	/* HPUX has doesn't like groups higher than 60000,
	 * but has assigned nobody to group 60001 (which isn't even
	 * in /etc/group!).
	 *
	 * HPUX's libc also insists on filling numeric fields it doesn't like
	 * with the value 60001!
	 */
	perror("Privs: WARNING: Assuming nobody-group.\n"
	       "Trying some alternatives...\n");
	// Assume we want the nobody group, and try a couple of alternatives
	foreach(({ 60001, 65534, -2 }), gid2) {
	  perror("%d... ", gid2);
	  if (initgroups(u[0], gid2) >= 0) {
	    if ((err = setegid(new_gid = gid2)) >= 0) {
	      perror("Success!\n");
	      break;
	    }
	  }
	}
      }
#endif /* HPUX_KLUDGE */
      if (err < 0) {
	perror("Privs: Failed\n");
	throw(({ sprintf("Failed to set EGID to %d\n", gid), backtrace() }));
      }
      perror("Privs: WARNING: Set egid to %d instead of %d.\n",
	     gid2, gid);
      gid = gid2;
    }
    if(getgid()!=gid) setgid(gid||getgid());
    seteuid(new_uid = uid);
#endif /* HAVE_EFFECTIVE_USER */
  }

  void destroy()
  {
#ifdef PRIVS_DEBUG
    werror(sprintf("Privs->destroy()\n"
		   "privs_level: %O\n",
		   privs_level));
#endif /* PRIVS_DEBUG */

#ifdef HAVE_EFFECTIVE_USER
    /* Check that we don't increase the privs level */
    if (p_level >= privs_level) {
      report_error(sprintf("Change back to uid#%d gid#%d from uid#%d gid#%d\n"
			   "in wrong order! Saved level:%d Current level:%d\n"
			   "Occurs in:\n%s\n",
			   saved_uid, saved_gid, new_uid, new_gid,
			   p_level, privs_level,
			   describe_backtrace(backtrace())));
      return(0);
    }
    if (p_level != privs_level-1) {
      report_error(sprintf("Change back to uid#%d gid#%d from uid#%d gid#%d\n"
			   "Skips privs level. Saved level:%d Current level:%d\n"
			   "Occurs in:\n%s\n",
			   saved_uid, saved_gid, new_uid, new_gid,
			   p_level, privs_level,
			   describe_backtrace(backtrace())));
    }
    privs_level = p_level;

    if(LOGP) {
      catch {
	array bt = backtrace();
	if (sizeof(bt) >= 2) {
	  report_notice(sprintf("Change back to uid#%d gid#%d, from %s\n",
				saved_uid, saved_gid, dbt(bt[-2])));
	} else {
	  report_notice(sprintf("Change back to uid#%d gid#%d, from backend\n",
				saved_uid, saved_gid));
	}
      };
    }

    if(getuid()) return;

#ifdef DEBUG
    int uid = geteuid();
    if (uid != new_uid) {
      report_warning(sprintf("Privs: UID #%d differs from expected #%d\n"
			     "%s\n",
			     uid, new_uid, describe_backtrace(backtrace())));
    }
    int gid = getegid();
    if (gid != new_gid) {
      report_warning(sprintf("Privs: GID #%d differs from expected #%d\n"
			     "%s\n",
			     gid, new_gid, describe_backtrace(backtrace())));
    }
#endif /* DEBUG */

    seteuid(0);
    array u = getpwuid(saved_uid);
#if efun(cleargroups)
    catch { cleargroups(); };
#endif /* cleargroups */
    if(u && (sizeof(u) > 3)) {
      catch { initgroups(u[0], u[3]); };
    }
    setegid(saved_gid);
    seteuid(saved_uid);
#endif /* HAVE_EFFECTIVE_USER */
  }
#endif /* efun(seteuid) */
};

/* Used by read_config.pike, since there seems to be problems with
 * overloading otherwise.
 */
static object PRIVS(string r, int|string|void u, int|string|void g)
{
  return Privs(r, u, g);
}


#if _DEBUG_HTTP_OBJECTS
mapping httpobjects = ([]);
static int idcount;
int new_id(){ return idcount++; }
#endif

#ifdef MODULE_DEBUG
#define MD_PERROR(X)	perror X;
#else
#define MD_PERROR(X)
#endif /* MODULE_DEBUG */

// pids of the start-script and ourselves.
int startpid, roxenpid;

class container
{
  mixed value;
  mixed set(mixed to)
  {
    return value=to;
  }
  mixed get()
  {
    return value;
  }
}

// Locale support
object(Locale.Roxen.standard) default_locale=Locale.Roxen.standard /* nihongo */;
object fonts;
#ifdef THREADS
object locale = thread_local();
#else
object locale = container(); 
#endif /* THREADS */
#define LOCALE	LOW_LOCALE->base_server

program Configuration;	/*set in create*/

array configurations = ({});
object main_configuration_port;
mapping allmodules, somemodules=([]);

// A mapping from ports (objects, that is) to an array of information
// about that port.  This will hopefully be moved to objects cloned
// from the configuration object in the future.
mapping portno=([]);

// Function pointer and the root of the configuration interface
// object.
function build_root;
object root;

int die_die_die;

void stop_all_modules()
{
  foreach(configurations, object conf)
    conf->stop();
}

// Function that actually shuts down Roxen. (see low_shutdown).
private static void really_low_shutdown(int exit_code)
{
  // Die nicely.
#ifdef THREADS
  catch( stop_handler_threads() );
#endif /* THREADS */
  exit(exit_code);		// Now we die...
}

// Shutdown Roxen
//  exit_code = 0	True shutdown
//  exit_code = -1	Restart
private static void low_shutdown(int exit_code)
{
  catch( stop_all_modules() );
  
  int pid;
  if (exit_code) {
    roxen_perror("Restarting Roxen.\n");
  } else {
    roxen_perror("Shutting down Roxen.\n");
    _exit(0);
  }
  call_out(really_low_shutdown, 0.1, exit_code);
}

// Perhaps somewhat misnamed, really...  This function will close all
// listen ports and then quit.  The 'start' script should then start a
// new copy of roxen automatically.
mapping restart() 
{ 
  low_shutdown(-1);
  return ([ "data": replace(Stdio.read_bytes("etc/restart.html"),
			    ({"$docurl", "$PWD"}), ({docurl, getcwd()})),
		  "type":"text/html" ]);
} 

mapping shutdown() 
{
  low_shutdown(0);
  return ([ "data":replace(Stdio.read_bytes("etc/shutdown.html"),
			   ({"$docurl", "$PWD"}), ({docurl, getcwd()})),
	    "type":"text/html" ]);
} 

// This is called for each incoming connection.
private static void accept_callback( object port )
{
  object file;
  int q=QUERY(NumAccept);
  array pn=portno[port];
  
#ifdef DEBUG
  if(!pn)
  {
    destruct(port->accept());
    perror("$&$$& Garbage Collector bug!!\n");
    return;
  }
#endif
  while(q--)
  {
    catch { file = port->accept(); };
#ifdef SOCKET_DEBUG
    if(!pn[-1])
    {
      report_error("In accept: Illegal protocol handler for port.\n");
      if(file) destruct(file);
      return;
    }
    perror(sprintf("SOCKETS: accept_callback(CONF(%s))\n", 
		   pn[1]&&pn[1]->name||"Configuration"));
#endif
    if(!file)
    {
      switch(port->errno())
      {
       case 0:
#if constant(system.EAGAIN)
      case system.EAGAIN:
#endif /* constant(system.EAGAIN) */
	return;

#if constant(system.EMFILE)
      case system.EMFILE:
#endif /* constant(system.EMFILE) */
#if constant(system.EBADF)
      case system.EBADF:
#endif /* constant(system.EBADF) */
	report_fatal(LOCALE->out_of_sockets());
	low_shutdown(-1);
	return;

      default:
#ifdef DEBUG
	perror("Accept failed.\n");
#if constant(real_perror)
	real_perror();
#endif
#endif /* DEBUG */
 	return;
      }
    }
#ifdef FD_DEBUG
    mark_fd( file->query_fd(),
	     LOCALE->out_of_sockets(file->query_address()));
#endif
    pn[-1](file,pn[1],pn);
#ifdef SOCKET_DEBUG
    perror(sprintf("SOCKETS:   Ok. Connect on %O:%O from %O\n", 
		   pn[2], pn[0], file->query_address()));
#endif
  }
}

/*
 * handle() stuff
 */

// handle function used when THREADS is not enabled.
void unthreaded_handle(function f, mixed ... args)
{
  f(@args);
}

function handle = unthreaded_handle;

/*
 * THREADS code starts here
 */
#ifdef THREADS
// #define THREAD_DEBUG

object do_thread_create(string id, function f, mixed ... args)
{
  object t = thread_create(f, @args);
  catch(t->set_name( id ));
  roxen_perror(id+" started\n");
  return t;
}

// Queue of things to handle.
// An entry consists of an array(function fp, array args)
static object (Thread.Queue) handle_queue = Thread.Queue();

// Number of handler threads that are alive.
static int thread_reap_cnt;

void handler_thread(int id)
{
  array (mixed) h, q;
  while(!die_die_die)
  {
    if(q=catch {
      do {
#ifdef THREAD_DEBUG
	werror("Handle thread ["+id+"] waiting for next event\n");
#endif /* THREAD_DEBUG */
	if((h=handle_queue->read()) && h[0]) {
#ifdef THREAD_DEBUG
	  werror(sprintf("Handle thread [%O] calling %O(@%O)...\n",
			 id, h[0], h[1..]));
#endif /* THREAD_DEBUG */
	  SET_LOCALE(default_locale);
	  h[0](@h[1]);
	  h=0;
	} else if(!h) {
	  // Roxen is shutting down.
	  werror("Handle thread ["+id+"] stopped\n");
	  thread_reap_cnt--;
	  return;
	}
      } while(1);
    }) {
      report_error(/* LOCALE->uncaught_error(*/describe_backtrace(q)/*)*/);
      if (q = catch {h = 0;}) {
	report_error(LOCALE->
		     uncaught_error(describe_backtrace(q)));
      }
    }
  }
}

void threaded_handle(function f, mixed ... args)
{
  handle_queue->write(({f, args }));
}

int number_of_threads;
void start_handler_threads()
{
  if (QUERY(numthreads) <= 1) {
    QUERY(numthreads) = 1;
    perror("Starting 1 thread to handle requests.\n");
  } else {
    perror("Starting "+QUERY(numthreads)+" threads to handle requests.\n");
  }
  for(; number_of_threads < QUERY(numthreads); number_of_threads++)
    do_thread_create( "Handle thread ["+number_of_threads+"]",
		   handler_thread, number_of_threads );
  if(number_of_threads > 0)
    handle = threaded_handle;
}

void stop_handler_threads()
{
  int timeout=30;
  perror("Stopping all request handler threads.\n");
  while(number_of_threads>0) {
    number_of_threads--;
    handle_queue->write(0);
    thread_reap_cnt++;
  }
  while(thread_reap_cnt) {
    if(--timeout<=0) {
      perror("Giving up waiting on threads!\n");
      return;
    }
    sleep(0.1);
  }
}

mapping accept_threads = ([]);
void accept_thread(object port,array pn)
{
  accept_threads[port] = this_thread();
  program port_program = pn[-1];
  mixed foo = pn[1];
  array err;
  object o;
  while(!die_die_die)
  {
    o = port->accept();
    err = catch {
      if(o) port_program(o,foo);
    };
    if(err)
      perror("Error in accept_thread: %O\n",describe_backtrace(err));
  }
}

#endif /* THREADS */



// Listen to a port, connected to the configuration 'conf', binding
// only to the netinterface 'ether', using 'requestprogram' as a
// protocol handled.

// If you think that the argument order is quite unintuitive and odd,
// you are right, the order is the same as the implementation order.

// Old spinners only listened to a port number, then the
// configurations came, then the need to bind to a specific
// ethernetinterface, and then the need to have more than one concurrent
// protocol (http, ftp, ssl, etc.)

object create_listen_socket(mixed port_no, object conf,
			    string|void ether, program requestprogram,
			    array prt)
{
  object port;
#ifdef SOCKET_DEBUG
  perror(sprintf("SOCKETS: create_listen_socket(%d,CONF(%s),%s)\n",
		 port_no, conf?conf->name:"Configuration port", ether));
#endif
  if(!requestprogram)
    error("No request handling module passed to create_listen_socket()\n");

  if(!port_no)
  {
    port = Stdio.Port( "stdin", accept_callback );
    port->set_id(port);
    if(port->errno()) {
      report_error(LOCALE->stdin_is_quiet(port->errno()));
    }
  } else {
    port = Stdio.Port();
    port->set_id(port);
    if(!stringp(ether) || (lower_case(ether) == "any"))
      ether=0;
    if(ether)
      sscanf(ether, "addr:%s", ether);
#if defined(THREADS) && 0
    if(!port->bind(port_no, 0, ether))
#else
    if(!port->bind(port_no, accept_callback, ether))
#endif
    {
#ifdef SOCKET_DEBUG
      perror("SOCKETS:    -> Failed.\n");
#endif
      report_warning(LOCALE->
		     socket_already_bound_retry(ether, port_no,
						port->errno()));
      sleep(1);
#if defined(THREADS) && 0
      if(!port->bind(port_no, 0, ether))
#else
      if(!port->bind(port_no, accept_callback, ether))
#endif
      {
	report_warning(LOCALE->
		       socket_already_bound(ether, port_no, port->errno()));
	return 0;
      }
    }
  }
  portno[port]=({ port_no, conf, ether||"Any", 0, requestprogram });
#if defined(THREADS) && 0
  call_out(do_thread_create,0,"Accept thread ["+port_no+":"+(ether||"ANY]"),
	   accept_thread, port,portno[port]);
#endif
#ifdef SOCKET_DEBUG
  perror("SOCKETS:    -> Ok.\n");
#endif
  return port;
}


/*
 * Port DB stuff.
 */

// ([ "prot" : ([ "ip" : ([ port : protocol_handler, ]), ]), ])
static mapping(string:mapping(string:mapping(int:object))) handler_db = ([]);

// ([ "prot" : protocol_program, ])
static mapping(string:program) port_db = ([]);

// Is there a handler for this port?
object low_find_handler(string prot, string ip, int port)
{
  mixed res;
  return((res = handler_db[prot]) && (res = res[ip]) && res[port]);
}

// Register a handler for a port.
void register_handler(string prot, string ip, int port, object handler)
{
  mapping m;
  if (m = handler_db[prot]) {
    mapping mm;
    if (mm = m[ip]) {
      // FIXME: What if mm[port] already exists?
      mm[port] = handler;
    } else {
      m[ip] = ([ port : handler ]);
    }
  } else {
    handler_db[prot] = ([ ip : ([ port : handler ]) ]);
  }
}

object find_handler(string prot, string ip, int port)
{
  object handler = low_find_handler(prot, ip, port);

  if (!handler) {
    program prog = port_db[prot];
    if (!prog) {
      return 0;
    }
    mixed err = catch {
      handler = prog(prot, ip, port);
    };
    if (err) {
      report_error(LOCALE->failed_to_open_port("?",
					       sprintf("%s://%s:%d/",
						       prot, ip, port),
					       describe_backtrace(err)));
    } else {
      register_handler(prot, ip, port, handler);
    }
  }
  return handler;
}

// The configuration interface is loaded dynamically for faster
// startup-time, and easier coding in the configuration interface (the
// Roxen environment is already finished when it is loaded)
object configuration_interface_obj;
int loading_config_interface;
int enabling_configurations;

object configuration_interface()
{
  if(enabling_configurations)
    return 0;
  if(loading_config_interface)
    perror("Recursive calls to configuration_interface()\n"
	   + describe_backtrace(backtrace())+"\n");
  
  if(!configuration_interface_obj)
  {
    perror("Loading configuration interface.\n");
    loading_config_interface = 1;
    array err = catch {
      configuration_interface_obj=((program)"mainconfig")();
      root = configuration_interface_obj->root;
      build_root = configuration_interface_obj->build_root;
    };
    loading_config_interface = 0;
    if(!configuration_interface_obj) {
      report_error(LOCALE->
		   configuration_interface_failed(describe_backtrace(err)));
    }
  }
  return configuration_interface_obj;
}

// Unload the configuration interface
void unload_configuration_interface()
{
  report_notice(LOCALE->unload_configuration_interface());

  configuration_interface_obj = 0;
  loading_config_interface = 0;
  enabling_configurations = 0;
  build_root = 0;
  catch{root->dest();};
  root = 0;
}


// Create a new configuration from scratch.

// 'type' is as in the form. 'none' for a empty configuration.
int add_new_configuration(string name, string type)
{
  return configuration_interface()->low_enable_configuration(name, type);
}

// Call the configuration interface function. This is more or less
// equivalent to a virtual configuration with the configurationinterface
// mounted on '/'. This will probably be the case in future versions
#ifdef THREADS
object configuration_lock = Thread.Mutex();
#endif

mixed configuration_parse(mixed ... args)
{
#ifdef THREADS
  object key;
  catch(key = configuration_lock->lock());
#endif
  if(args)
    return configuration_interface()->configuration_parse(@args);
}

mapping(string:array(int)) error_log=([]);

string last_error="";

// Write a string to the configuration interface error log and to stderr.
void nwrite(string s, int|void perr, int|void type)
{
  last_error = s;
  if (!error_log[type+","+s]) {
    error_log[type+","+s] = ({ time() });
  } else {
    error_log[type+","+s] += ({ time() });
  }
  if(type>=1) roxen_perror(s);
}

// When was Roxen started?
int boot_time;
int start_time;

string version()
{
  return QUERY(default_ident)?real_version:QUERY(ident);
}

// The db for the nice '<if supports=..>' tag.
mapping (string:array (array (object|multiset))) supports;
private multiset default_supports = (< >);

private static inline array positive_supports(array from)
{
  array res = copy_value(from);
  int i;
  for(i=0; i<sizeof(res); i++)
    if(res[i][0] == '-')
      res[i] = 0;
  return res - ({ 0 });
}

private inline array negative_supports(array from)
{
  array res = copy_value(from);
  int i;
  for(i=0; i<sizeof(res); i++)
    if(res[i][0] != '-')
      res[i] = 0;
    else
      res[i] = res[i][1..];
  return res - ({ 0 });
}

private static mapping foo_defines = ([ ]);
// '#define' in the 'supports' file.
static private string current_section; // Used below.
// '#section' in the 'supports' file.

private void parse_supports_string(string what)
{
  string foo;
  
  array lines;
  int i;
  lines=replace(what, "\\\n", " ")/"\n"-({""});

  foreach(lines, foo)
  {
    array bar, gazonk;
    if(foo[0] == '#')
    {
      string file;
      string name, to;
      if(sscanf(foo, "#include <%s>", file))
      {
	if(foo=Stdio.read_bytes(file))
	  parse_supports_string(foo);
	else
	  report_error(LOCALE->supports_bad_include(file));
      } else if(sscanf(foo, "#define %[^ ] %s", name, to)) {
	name -= "\t";
	foo_defines[name] = to;
//	perror("#defining '"+name+"' to "+to+"\n");
      } else if(sscanf(foo, "#section %[^ ] {", name)) {
//	perror("Entering section "+name+"\n");
	current_section = name;
	if(!supports[name])
	  supports[name] = ({});
      } else if((foo-" ") == "#}") {
//	perror("Leaving section "+current_section+"\n");
	current_section = 0;
      } else {
//	perror("Comment: "+foo+"\n");
      }
      
    } else {
      int rec = 10;
      string q=replace(foo,",", " ");
      foo="";
      
      // Handle all defines.
      while((strlen(foo)!=strlen(q)) && --rec)
      {
	foo=q;
	q = replace(q, indices(foo_defines), values(foo_defines));
      }
      
      foo=q;
      
      if(!rec)
	perror("Too deep recursion while replacing defines.\n");
      
//    perror("Parsing supports line '"+foo+"'\n");
      bar = replace(foo, ({"\t",","}), ({" "," "}))/" " -({ "" });
      foo="";
      
      if(sizeof(bar) < 2)
	continue;
    
      if(bar[0] == "default")
	default_supports = aggregate_multiset(@bar[1..]);
      else
      {
	gazonk = bar[1..];
	mixed err;
	if (err = catch {
	  supports[current_section]
	    += ({ ({ Regexp(bar[0])->match,
		     aggregate_multiset(@positive_supports(gazonk)),
		     aggregate_multiset(@negative_supports(gazonk)),
	    })});
	}) {
	  report_error(LOCALE->supports_bad_regexp(describe_backtrace(err)));
	}
      }
    }
  }
}

public void initiate_supports()
{
  supports = ([ 0:({ }) ]);
  foo_defines = ([ ]);
  current_section = 0;
  parse_supports_string(QUERY(Supports));
  foo_defines = 0;
}

array _new_supports = ({});

void done_with_roxen_com()
{
  string new, old;
  new = _new_supports * "";
  new = (new/"\r\n\r\n")[1..]*"\r\n\r\n";
  old = Stdio.read_bytes( "etc/supports" );
  
  if(strlen(new) < strlen(old)-200) // Error in transfer?
    return;
  
  if(old != new) {
    perror("Got new supports data from www.roxen.com\n");
    perror("Replacing old file with new data.\n");
// #ifndef THREADS
//     object privs=Privs(LOCALE->replacing_supports());
// #endif
    mv("etc/supports", "etc/supports~");
    Stdio.write_file("etc/supports", new, 0660);
    old = Stdio.read_bytes( "etc/supports" );

    if(old != new)
    {
      perror("FAILED to update the supports file.\n");
      mv("etc/supports~", "etc/supports");
// #ifndef THREADS
//       privs = 0;
// #endif
    } else {
// #ifndef THREADS
//       privs = 0;
// #endif
      initiate_supports();
    }
  }
#ifdef DEBUG
  else
    perror("No change to the supports file.\n");
#endif
}

void got_data_from_roxen_com(object this, string foo)
{
  if(!foo)
    return;
  _new_supports += ({ foo });
}

void connected_to_roxen_com(object port)
{
  if(!port) 
  {
#ifdef DEBUG
    perror("Failed to connect to www.roxen.com:80.\n");
#endif
    return 0;
  }
#ifdef DEBUG
  perror("Connected to www.roxen.com.:80\n");
#endif
  _new_supports = ({});
  port->set_id(port);
  string v = version();
  if (v != real_version) {
    v = v + " (" + real_version + ")";
  }
  port->write("GET /supports HTTP/1.0\r\n"
	      "User-Agent: " + v + "\r\n"
	      "Host: www.roxen.com:80\r\n"
	      "Pragma: no-cache\r\n"
	      "\r\n");
  port->set_nonblocking(got_data_from_roxen_com,
			got_data_from_roxen_com,
			done_with_roxen_com);
}

public void update_supports_from_roxen_com()
{
  // FIXME:
  // This code has a race-condition, but it only occurs once a week...
  if(QUERY(next_supports_update) <= time())
  {
    if(QUERY(AutoUpdate))
    {
      async_connect("www.roxen.com.", 80, connected_to_roxen_com);
#ifdef DEBUG
      perror("Connecting to www.roxen.com.:80\n");
#endif
    }
    remove_call_out( update_supports_from_roxen_com );

  // Check again in one week.
    QUERY(next_supports_update)=3600*24*7 + time();
    store("Variables", variables, 0, 0);
  }
  call_out(update_supports_from_roxen_com, QUERY(next_supports_update)-time());
}

// Return a list of 'supports' values for the current connection.

public multiset find_supports(string from, void|multiset existing_sup)
{
  multiset (string) sup =  (< >);
  multiset (string) nsup = (< >);

  array (function|multiset) s;
  string v;
  array f;
  
  if(!strlen(from) || from == "unknown")
    return default_supports|existing_sup;
  if(!(sup = cache_lookup("supports", from))) {
    sup = (<>);
    foreach(indices(supports), v)
    {
      if(!v || !search(from, v))
      {
	//  perror("Section "+v+" match "+from+"\n");
	f = supports[v];
	foreach(f, s)
	  if(s[0](from))
	  {
	    sup |= s[1];
	    nsup  |= s[2];
	  }
      }
    }
    if(!sizeof(sup))
    {
      sup = default_supports;
#ifdef DEBUG
      perror("Unknown client: \""+from+"\"\n");
#endif
    }
    sup -= nsup;
    cache_set("supports", from, sup);
  }
  return sup|existing_sup;
}

public void log(mapping file, object request_id)
{
  if(!request_id->conf) return; 
  request_id->conf->log(file, request_id);
}

// Support for unique user id's 
private object current_user_id_file;
private int current_user_id_number, current_user_id_file_last_mod;

private void restore_current_user_id_number()
{
  if(!current_user_id_file)
    current_user_id_file = open(configuration_dir + "LASTUSER~", "rwc");
  if(!current_user_id_file)
  {
    call_out(restore_current_user_id_number, 2);
    return;
  } 
  current_user_id_number = (int)current_user_id_file->read(100);
  current_user_id_file_last_mod = current_user_id_file->stat()[2];
  perror("Restoring unique user ID information. (" + current_user_id_number 
	 + ")\n");
#ifdef FD_DEBUG
  mark_fd(current_user_id_file->query_fd(), LOCALE->unique_uid_logfile());
#endif
}


int increase_id()
{
  if(!current_user_id_file)
  {
    restore_current_user_id_number();
    return current_user_id_number+time();
  }
  if(current_user_id_file->stat()[2] != current_user_id_file_last_mod)
    restore_current_user_id_number();
  current_user_id_number++;
  //perror("New unique id: "+current_user_id_number+"\n");
  current_user_id_file->seek(0);
  current_user_id_file->write((string)current_user_id_number);
  current_user_id_file_last_mod = current_user_id_file->stat()[2];
  return current_user_id_number;
}

public string full_status()
{
  int tmp;
  string res="";
  array foo = ({0.0, 0.0, 0.0, 0.0, 0});
  if(!sizeof(configurations))
    return LOCALE->no_servers_enabled();
  
  foreach(configurations, object conf)
  {
    if(!conf->sent
       ||!conf->received
       ||!conf->hsent)
      continue;
    foo[0] += conf->sent->mb()/(float)(time(1)-start_time+1);
    foo[1] += conf->sent->mb();
    foo[2] += conf->hsent->mb();
    foo[3] += conf->received->mb();
    foo[4] += conf->requests;
  }

  for(tmp = 1; tmp < 4; tmp ++)
  {
    // FIXME: LOCALE?

    if(foo[tmp] < 1024.0)     
      foo[tmp] = sprintf("%.2f MB", foo[tmp]);
    else
      foo[tmp] = sprintf("%.2f GB", foo[tmp]/1024.0);
  }

  int uptime = time()-start_time;
  int days = uptime/(24*60*60);
  int hrs = uptime/(60*60);
  int min = uptime/60 - hrs*60;
  hrs -= days*24;

  tmp=(int)((foo[4]*600.0)/(uptime+1));

  return(LOCALE->full_status(real_version, boot_time, start_time-boot_time,
			     days, hrs, min, uptime%60,
			     foo[1], foo[0] * 8192.0, foo[2],
			     foo[4], (float)tmp/(float)10, foo[3]));
}


int config_ports_changed = 0;

static string MKPORTKEY(array(string) p)
{
  if (sizeof(p[3])) {
    return(sprintf("%s://%s:%s/(%s)",
		   p[1], p[2], (string)p[0],
		   replace(p[3], ({"\n", "\r"}), ({ " ", " " }))));
  } else {
    return(sprintf("%s://%s:%s/",
		   p[1], p[2], (string)p[0]));
  }
}

// Is this only used to hold the config-ports?
// Seems like it. Changed to a mapping.
private mapping(string:object) configuration_ports = ([]);

// Used by config_actions/openports.pike
array(object) get_configuration_ports()
{
  return(values(configuration_ports));
}

string docurl;

// I will remove this in a future version of roxen.
private program __p;
mapping my_loaded = ([]);
program last_loaded() { return __p; }

string last_module_name;

string filename(object|program o)
{
  if(objectp(o)) o = object_program(o);
  return my_loaded[(program)o]||last_module_name;
}

program my_compile_file(string file)
{
  return compile_file( file );
}

array compile_module( string file )
{
  array foo;
  object o;
  program p;

  MD_PERROR(("Compiling " + file + "...\n"));
  
  if (catch(p = my_compile_file(file)) || (!p)) {
    MD_PERROR((" compilation failed"));
    throw("MODULE: Compilation failed.\n");
  }
  // Set the module-filename, so that create in the
  // new object can get it.
  last_module_name = file;
  
  array err = catch(o =  p());

  last_module_name = 0;

  if (err) {
    MD_PERROR((" load failed\n"));
    throw(err);
  } else if (!o) {
    MD_PERROR((" load failed\n"));
    throw("Failed to initialize module.\n");
  } else {
    MD_PERROR((" load ok - "));
    if (!o->register_module) {
      MD_PERROR(("register_module missing"));
      throw("No registration function in module.\n");
    }
  }

  foo = o->register_module();
  if (!foo) {
    MD_PERROR(("registration failed.\n"));
    return 0;
  } else {
    MD_PERROR(("registered."));
  }
  return({ foo[1], foo[2]+"<p><i>"+
	   replace(o->file_name_and_stuff(), "0<br>", file+"<br>")
	   +"</i>", foo[0] });
}

// ([ filename:stat_array ])
mapping(string:array) module_stat_cache = ([]);
object load(string s, object conf)   // Should perhaps be renamed to 'reload'. 
{
  string cvs;
  array st;
  sscanf(s, "/cvs:%s", cvs);

//  perror("Module is "+s+"?");
  if(st=file_stat(s+".pike"))
  {
//    perror("Yes, compile "+s+"?");
    if((cvs?(__p=master()->cvs_load_file( cvs+".pike" ))
	:(__p=my_compile_file(s+".pike"))))
    {
//      perror("Yes.");
      my_loaded[__p]=s+".pike";
      module_stat_cache[s-dirname(s)]=st;
      return __p(conf);
    } else
      perror(s+".pike exists, but compilation failed.\n");
  }
#if 0
  if(st=file_stat(s+".module"))
    if(__p=load_module(s+".so"))
    {
      my_loaded[__p]=s+".so";
      module_stat_cache[s-dirname(s)]=st;
      return __p(conf);
    } else
      perror(s+".so exists, but compilation failed.\n");
#endif
  return 0; // FAILED..
}

array(string) expand_dir(string d)
{
  string nd;
  array(string) dirs=({d});

//perror("Expand dir "+d+"\n");
  catch {
    foreach((get_dir(d) || ({})) - ({"CVS"}) , nd) 
      if(file_stat(d+nd)[1]==-2)
	dirs+=expand_dir(d+nd+"/");
  }; // This catch is needed....
  return dirs;
}

array(string) last_dirs=0,last_dirs_expand;

object load_from_dirs(array dirs, string f, object conf)
{
  string dir;
  object o;

  if (dirs!=last_dirs)
  {
    last_dirs_expand=({});
    foreach(dirs, dir)
      last_dirs_expand+=expand_dir(dir);
  }

  foreach (last_dirs_expand,dir)
     if ( (o=load(dir+f, conf)) ) return o;

  return 0;
}


static int abs_started;

void restart_if_stuck (int force) 
{
  remove_call_out(restart_if_stuck);
  if (!(QUERY(abs_engage) || force))
    return;
  if(!abs_started) 
  {
    abs_started = 1;
    roxen_perror("Anti-Block System Enabled.\n");
  }
  call_out (restart_if_stuck,10);
  signal(signum("SIGALRM"),
	 lambda( int n ) {
	   werror(sprintf("**** %s: ABS engaged!\n"
			  "Trying to dump backlog: \n",
			  ctime(time()) - "\n"));
	   catch {
	     // Catch for paranoia reasons.
	     describe_all_threads();
	   };
	   werror(sprintf("**** %s: ABS exiting roxen!\n\n",
			  ctime(time())));
	   _exit(1); 	// It might now quit correctly otherwise, if it's
	   //  locked up
	 });
  alarm (60*QUERY(abs_timeout)+10);
}

void post_create () 
{
  if (QUERY(abs_engage))
    call_out (restart_if_stuck,10);
  if (QUERY(suicide_engage))
    call_out (restart,60*60*24*QUERY(suicide_timeout));
}

void create()
{
//    SET_LOCALE(default_locale);

  catch
  {
    module_stat_cache = decode_value(Stdio.read_bytes(".module_stat_cache"));
    allmodules = decode_value(Stdio.read_bytes(".allmodules"));
  };
#ifndef __NT__
  if(!getuid()) {
    add_constant("Privs", Privs);
  } else
#endif /* !__NT__ */
    add_constant("Privs", class{});

  add_constant("roxen", this_object());
  add_constant("RequestID", RequestID);
  add_constant("load",    load);

  // compatibility
  add_constant("hsv_to_rgb",  Colors.hsv_to_rgb  );
  add_constant("rgb_to_hsv",  Colors.rgb_to_hsv  );
  add_constant("parse_color", Colors.parse_color );
  add_constant("color_name",  Colors.color_name  );
  add_constant("colors",      Colors             );

  fonts = (object)"fonts.pike";
  Configuration = (program)"configuration";
  add_constant("Configuration", Configuration);
  call_out(post_create,1); //we just want to delay some things a little
}


// Get the current domain. This is not as easy as one could think.
string get_domain(int|void l)
{
  array f;
  string t, s;

//  ConfigurationURL is set by the 'install' script.
  if(!(!l && sscanf(QUERY(ConfigurationURL), "http://%s:%*s", s)))
  {
#if constant(gethostbyname) && constant(gethostname)
    f = gethostbyname(gethostname()); // First try..
    if(f)
      foreach(f, f) if (arrayp(f)) { 
	foreach(f, t) if(search(t, ".") != -1 && !(int)t)
	  if(!s || strlen(s) < strlen(t))
	    s=t;
      }
#endif
    if(!s)
    {
      // FIXME: NT support.

      t = Stdio.read_bytes("/etc/resolv.conf");
      if(t) 
      {
	if(!sscanf(t, "domain %s\n", s))
	  if(!sscanf(t, "search %s%*[ \t\n]", s))
	    s="nowhere";
      } else {
	s="nowhere";
      }
      s = "host."+s;
    }
  }
  sscanf(s, "%*s.%s", s);
  if(s && strlen(s))
  {
    if(s[-1] == '.') s=s[..strlen(s)-2];
    if(s[0] == '.') s=s[1..];
  } else {
    s="unknown"; 
  }
  return s;
}


// This is the most likely URL for a virtual server. Again, this
// should move into the actual 'configuration' object. It is not all
// that nice to have all this code lying around in here.

private string get_my_url()
{
  string s;
#if constant(gethostname)
  s = (gethostname()/".")[0] + "." + query("Domain");
#else
  s = "localhost";
#endif
  s -= "\n";
  return "http://" + s + "/";
}

// Set the uid and gid to the ones requested by the user. If the sete*
// functions are available, and the define SET_EFFECTIVE is enabled,
// the euid and egid is set. This might be a minor security hole, but
// it will enable roxen to start CGI scripts with the correct
// permissions (the ones the owner of that script have).

int set_u_and_gid()
{
#ifndef __NT__
  string u, g;
  int uid, gid;
  array pw;
  
  u=QUERY(User);
  sscanf(u, "%s:%s", u, g);
  if(strlen(u))
  {
    if(getuid())
    {
      report_error ("It is only possible to change uid and gid if the server "
		    "is running as root.\n");
    } else {
      if (g) {
#if constant(getgrnam)
	pw = getgrnam (g);
	if (!pw)
	  if (sscanf (g, "%d", gid)) pw = getgrgid (gid), g = (string) gid;
	  else report_error ("Couldn't resolve group " + g + ".\n"), g = 0;
	if (pw) g = pw[0], gid = pw[2];
#else
	if (!sscanf (g, "%d", gid))
	  report_warning ("Can't resolve " + g + " to gid on this system; "
			  "numeric gid required.\n");
#endif
      }

      pw = getpwnam (u);
      if (!pw)
	if (sscanf (u, "%d", uid)) pw = getpwuid (uid), u = (string) uid;
	else {
	  report_error ("Couldn't resolve user " + u + ".\n");
	  return 0;
	}
      if (pw) {
	u = pw[0], uid = pw[2];
	if (!g) gid = pw[3];
      }

#ifdef THREADS
      object mutex_key;
      catch { mutex_key = euid_egid_lock->lock(); };
      object threads_disabled = _disable_threads();
#endif

#if constant(seteuid)
      if (geteuid() != getuid()) seteuid (getuid());
#endif

#if constant(initgroups)
      catch {
	initgroups(pw[0], gid);
	// Doesn't always work - David.
      };
#endif

      if (QUERY(permanent_uid)) {
#if constant(setuid)
	if (g) {
#  if constant(setgid)
	  setgid(gid);
	  if (getgid() != gid) report_error ("Failed to set gid.\n"), g = 0;
#  else
	  report_warning ("Setting gid not supported on this system.\n");
	  g = 0;
#  endif
	}
	setuid(uid);
	if (getuid() != uid) report_error ("Failed to set uid.\n"), u = 0;
	if (u) report_notice(LOCALE->setting_uid_gid_permanently (uid, gid, u, g));
#else
	report_warning ("Setting uid not supported on this system.\n");
	u = g = 0;
#endif
      }
      else {
#if constant(seteuid)
	if (g) {
#  if constant(setegid)
	  setegid(gid);
	  if (getegid() != gid) report_error ("Failed to set effective gid.\n"), g = 0;
#  else
	  report_warning ("Setting effective gid not supported on this system.\n");
	  g = 0;
#  endif
	}
	seteuid(uid);
	if (geteuid() != uid) report_error ("Failed to set effective uid.\n"), u = 0;
	if (u) report_notice(LOCALE->setting_uid_gid (uid, gid, u, g));
#else
	report_warning ("Setting effective uid not supported on this system.\n");
	u = g = 0;
#endif
      }

      return !!u;
    }
  }
#endif
  return 0;
}

static mapping __vars = ([ ]);

// These two should be documented somewhere. They are to be used to
// set global, but non-persistent, variables in Roxen. By using
// these functions modules can "communicate" with one-another. This is
// not really possible otherwise.
mixed set_var(string var, mixed to)
{
  return __vars[var] = to;
}

mixed query_var(string var)
{
  return __vars[var];
}


void reload_all_configurations()
{
  object conf;
  array (object) new_confs = ({});
  mapping config_cache = ([]);
  int modified;

  report_notice(LOCALE->reloading_config_interface());
  configs = ([]);
  setvars(retrieve("Variables", 0));
  initiate_configuration_port( 0 );

  foreach(list_all_configurations(), string config)
  {
    array err, st;
    foreach(configurations, conf)
    {
      if(lower_case(conf->name) == lower_case(config))
      {
	break;
      } else
	conf = 0;
    }
    if(!(st = config_is_modified(config))) {
      if(conf) {
	config_cache[config] = config_stat_cache[config];
	new_confs += ({ conf });
      }
      continue;
    }
    modified = 1;
    config_cache[config] = st;
    if(conf) {
      // Closing ports...
      if (conf->server_ports) {
	// Roxen 1.2.26 or later
	Array.map(values(conf->server_ports), destruct);
      } else {
	Array.map(indices(conf->open_ports), destruct);
      }
      conf->stop();
      conf->invalidate_cache();
      conf->modules = ([]);
      conf->create(conf->name);
    } else {
      if(err = catch
      {
	conf = enable_configuration(config);
      }) {
	report_error(LOCALE->
		     error_enabling_configuration(config,
						  describe_backtrace(err)));
	continue;
      }
    }
    if(err = catch
    {
      conf->start();
      conf->enable_all_modules();
    }) {
      report_error(LOCALE->
		   error_enabling_configuration(config,
						describe_backtrace(err)));
      continue;
    }
    new_confs += ({ conf });
  }
    
  foreach(configurations - new_confs, conf)
  {
    modified = 1;
    report_notice(LOCALE->disabling_configuration(conf->name));
    if (conf->server_ports) {
      // Roxen 1.2.26 or later
      Array.map(values(conf->server_ports), destruct);
    } else {
      Array.map(indices(conf->open_ports), destruct);
    }
    conf->stop();
    destruct(conf);
  }
  if(modified) {
    configurations = new_confs;
    config_stat_cache = config_cache;
    unload_configuration_interface();
  }
}

object enable_configuration(string name)
{
  object cf = Configuration(name);
  configurations += ({ cf });
  report_notice(LOCALE->enabled_server(name));
  
  return cf;
}

// Enable all configurations
void enable_configurations()
{
  array err;

  enabling_configurations = 1;
  configurations = ({});
  foreach(list_all_configurations(), string config)
  {
    if(err=catch { enable_configuration(config)->start();  })
      perror("Error while loading configuration "+config+":\n"+
	     describe_backtrace(err)+"\n");
  };
  enabling_configurations = 0;
}


void enable_configurations_modules()
{
  foreach(configurations, object config)
  {
    array err;
    if(err=catch { config->enable_all_modules();  })
      perror("Error while loading modules in configuration "+config->name+":\n"+
	     describe_backtrace(err)+"\n");
  };
}

// return the URL of the configuration interface. This is not as easy
// as it sounds, unless the administrator has entered it somewhere.

public string config_url()
{
  if(strlen(QUERY(ConfigurationURL)-" "))
    return QUERY(ConfigurationURL)-" ";

  array ports = QUERY(ConfigPorts), port, tmp;

  if(!sizeof(ports)) return "CONFIG";

  int p;
  string prot;
  string host;

  foreach(ports, tmp)
    if(tmp[1][0..2]=="ssl") 
    {
      port=tmp; 
      break;
    }

  if(!port)
    foreach(ports, tmp)
      if(tmp[1]=="http") 
      {
	port=tmp; 
	break;
      }

  if(!port) port=ports[0];

  if(port[2] == "ANY")
//  host = quick_ip_to_host( port[2] );
// else
  {
#if efun(gethostname)
    host = gethostname();
#else
    host = "127.0.0.1";
#endif
  }

  switch(port[1][..2]) {
  case "ssl":
    prot = "https";
    break;
  case "ftp":
    prot = "ftp";
    break;
  default:
    prot = port[1];
    break;
  }
  p = port[0];

  return (prot+"://"+host+":"+p+"/");
}


// The following three functions are used to hide variables when they
// are not used. This makes the user-interface clearer and quite a lot
// less clobbered.
  
int cache_disabled_p() { return !QUERY(cache);         }
int syslog_disabled()  { return QUERY(LogA)!="syslog"; }
private int ident_disabled_p() { return QUERY(default_ident); }

class ImageCache
{
  string name;
  string dir;
  function draw_function;
  mapping data_cache = ([]); // not normally used.
  mapping meta_cache = ([]);


  static mapping meta_cache_insert( string i, mapping what )
  {
    return meta_cache[i] = what;
  }
  
  static string data_cache_insert( string i, string what )
  {
    return data_cache[i] = what;
  }

  static mixed frommapp( mapping what )
  {
    if( what[""] ) return what[""];
    return what;
  }

  static void draw( string name, RequestID id )
  {
    mixed args = Array.map( Array.map( name/"$", argcache->lookup, id->client ), frommapp);
    mapping meta;
    string data;
    mixed reply = draw_function( @copy_value(args), id );

    if( arrayp( args ) )
      args = args[0];


    if( objectp( reply ) || (mappingp(reply) && reply->img) )
    {
      int quant = (int)args->quant;
      string format = lower_case(args->format || "gif");
      string dither = args->dither;
      Image.Colortable ct;
      object alpha;
      int true_alpha; 

      if( args->fs  || dither == "fs" )
	dither = "floyd_steinberg";

      if(  dither == "random" )
	dither = "random_dither";

      if( format == "jpg" ) 
        format = "jpeg";

      if(mappingp(reply))
      {
        alpha = reply->alpha;
        reply = reply->img;
      }
      
      if( args->gamma )
        reply = reply->gamma( (float)args->gamma );

      if( args["true-alpha"] )
        true_alpha = 1;

      if( args["opaque-value"] )
      {
        true_alpha = 1;
        int ov = (int)(((float)args["opaque-value"])*2.55);
        if( ov < 0 )
          ov = 0;
        else if( ov > 255 )
          ov = 255;
        if( alpha )
        {
          object i = Image.image( reply->xsize(), reply->ysize(), ov,ov,ov );
          i->paste_alpha( alpha, ov );
          alpha = i;
        }
        else
        {
          alpha = Image.image( reply->xsize(), reply->ysize(), ov,ov,ov );
        }
      }

      if( args->scale )
      {
        int x, y;
        if( sscanf( args->scale, "%d,%d", x, y ) == 2)
        {
          reply = reply->scale( x, y );
          if( alpha )
            alpha = alpha->scale( x, y );
        }
        else if( (float)args->scale < 3.0)
        {
          reply = reply->scale( ((float)args->scale) );
          if( alpha )
            alpha = alpha->scale( ((float)args->scale) );
        }
      }

      if( args->maxwidth || args->maxheight )
      {
        int x = (int)args->maxwidth, y = (int)args->maxheight;
        if( x && reply->xsize() > x )
        {
          reply = reply->scale( x, 0 );
          if( alpha )
            alpha = alpha->scale( x, 0 );
        }
        if( y && reply->ysize() > y )
        {
          reply = reply->scale( 0, y );
          if( alpha )
            alpha = alpha->scale( 0, y );
        }
      }

      if( quant || (format=="gif") )
      {
        int ncols = quant||id->misc->defquant||16;
        if( ncols > 250 )
          ncols = 250;
        ct = Image.Colortable( reply, ncols );
        if( dither )
          if( ct[ dither ] )
            ct[ dither ]();
          else
            ct->ordered();
      }

      if(!Image[upper_case( format )] 
         || !Image[upper_case( format )]->encode )
        error("Image format "+format+" unknown\n");

      mapping enc_args = ([]);
      if( ct )
        enc_args->colortable = ct;
      if( alpha )
        enc_args->alpha = alpha;

      foreach( glob( "*-*", indices(args)), string n )
        if(sscanf(n, "%*[^-]-%s", string opt ) == 2)
          enc_args[opt] = (int)args[n];

      switch(format)
      {
       case "gif":
         if( alpha && true_alpha )
         {
           object ct=Image.Colortable( ({ ({ 0,0,0 }), ({ 255,255,255 }) }) );
           ct->floyd_steinberg();
           alpha = ct->map( alpha );
         }
         if( catch {
           if( alpha )
             data = Image.GIF.encode_trans( reply, ct, alpha );
           else
             data = Image.GIF.encode( reply, ct );
         })
           data = Image.GIF.encode( reply );
         break;
       case "png":
         if( ct )
           enc_args->palette = ct;
         m_delete( enc_args, "colortable" );
       default:
        data = Image[upper_case( format )]->encode( reply, enc_args );
      }

      meta = ([ 
        "xsize":reply->xsize(),
        "ysize":reply->ysize(),
        "type":"image/"+format,
      ]);
    }
    else if( mappingp(reply) ) 
    {
      meta = reply->meta;
      data = reply->data;
      if( !meta || !data )
        error("Invalid reply mapping.\n"
              "Should be ([ \"meta\": ([metadata]), \"data\":\"data\" ])\n");
    }
    store_meta( name, meta );
    store_data( name, data );
  }


  static void store_meta( string id, mapping meta )
  {
    meta_cache_insert( id, meta );

    string data = encode_value( meta );
    Stdio.File f = Stdio.File(  );
    if(!f->open(dir+id+".i", "wct" ))
    {
      report_error( "Failed to open image cache persistant cache file "+
                    dir+id+".i: "+strerror( errno() )+ "\n" );
      return;
    }
    f->write( data );
  }

  static void store_data( string id, string data )
  {
    Stdio.File f = Stdio.File(  );
    if(!f->open(dir+id+".d", "wct" ))
    {
      data_cache_insert( id, data );
      report_error( "Failed to open image cache persistant cache file "+
                    dir+id+".d: "+strerror( errno() )+ "\n" );
      return;
    }
    f->write( data );
  }


  static mapping restore_meta( string id )
  {
    Stdio.File f;
    if( meta_cache[ id ] )
      return meta_cache[ id ];
    f = Stdio.File( );
    if( !f->open(dir+id+".i", "r" ) )
      return 0;
    return meta_cache_insert( id, decode_value( f->read() ) );
  }

  static mapping restore( string id )
  {
    string|object(Stdio.File) f;
    mapping m;
    if( data_cache[ id ] )
      f = data_cache[ id ];
    else 
      f = Stdio.File( );

    if(!f->open(dir+id+".d", "r" ))
      return 0;

    m = restore_meta( id );
    
    if(!m)
      return 0;

    if( stringp( f ) )
      return http_string_answer( f, m->type||("image/gif") );
    return roxenp()->http_file_answer( f, m->type||("image/gif") );
  }


  string data( string|mapping args, RequestID id, int|void nodraw )
  {
    string na = store( args, id );
    mixed res;

    if(!( res = restore( na )) )
    {
      if(nodraw)
        return 0;
      draw( na, id );
      res = restore( na );
    }
    if( res->file )
      return res->file->read();
    return res->data;
  }

  mapping http_file_answer( string|mapping data, 
                            RequestID id, 
                            int|void nodraw )
  {
    string na = store( data,id );
    mixed res;
    if(!( res = restore( na )) )
    {
      if(nodraw)
        return 0;
      draw( na, id );
      res = restore( na );
    }
    return res;
  }

  mapping metadata( string|mapping data, RequestID id, int|void nodraw )
  {
    string na = store( data,id );
    if(!restore_meta( na ))
    {
      if(nodraw)
        return 0;
      draw( na, id );
      return restore_meta( na );
    }
    return restore_meta( na );
  }

  mapping tomapp( mixed what )
  {
    if( mappingp( what ))
      return what;
    return ([ "":what ]);
  }

  string store( array|string|mapping data, RequestID id )
  {
    string ci;
    if( mappingp( data ) )
      ci = argcache->store( data );
    else if( arrayp( data ) )
      ci = Array.map( Array.map( data, tomapp ), argcache->store )*"$";
    else
      ci = data;
    return ci;
  }

  void set_draw_function( function to )
  {
    draw_function = to;
  }

  void create( string id, function draw_func, string|void d )
  {
    if(!d) d = roxenp()->QUERY(argument_cache_dir);
    if( d[-1] != '/' )
      d+="/";
    d += id+"/";

    mkdirhier( d+"foo");

    dir = d;
    name = id;
    draw_function = draw_func;
  }
}


class ArgCache
{
  static string name;
  static string path;
  static int is_db;
  static object db;

#define CACHE_VALUE 0
#define CACHE_SKEY  1
#define CACHE_SIZE  600
#define CLEAN_SIZE  100

#ifdef THREADS
  static Thread.Mutex mutex = Thread.Mutex();
# define LOCK() object __key = mutex->lock()
#else
# define LOCK() 
#endif

  static mapping (string:mixed) cache = ([ ]);

  void setup_table()
  {
    if(catch(db->query("select id from "+name+" where id=-1")))
      if(catch(db->query("create table "+name+" ("
                         "id int auto_increment primary key, "
                         "lkey varchar(80) not null default '', "
                         "contents blob not null default '', "
                         "atime bigint not null default 0)")))
        throw("Failed to create table in database\n");
  }

  void create( string _name, 
               string _path, 
               int _is_db )
  {
    name = _name;
    path = _path;
    is_db = _is_db;

    if(is_db)
    {
      db = Sql.sql( path );
      if(!db)
        error("Failed to connect to database for argument cache\n");
      setup_table( );
    } else {
      if(path[-1] != '/' && path[-1] != '\\')
        path += "/";
      path += replace(name, "/", "_")+"/";
      mkdirhier( path + "/tmp" );
      object test = Stdio.File();
      if (!test->open (path + "/.testfile", "wc"))
	error ("Can't create files in the argument cache directory " + path + "\n");
      else {
	test->close();
	rm (path + "/.testfile");
      }
    }
  }

  static string read_args( string id )
  {
    if( is_db )
    {
      mapping res = db->query("select contents from "+name+" where id='"+id+"'");
      if( sizeof(res) )
      {
        db->query("update "+name+" set atime='"+
                  time()+"' where id='"+id+"'");
        return res[0]->contents;
      }
      return 0;
    } else {
      if( file_stat( path+id ) )
        return Stdio.read_bytes(path+"/"+id);
    }
    return 0;
  }

  static string create_key( string long_key )
  {
    if( is_db )
    {
      mapping data = db->query(sprintf("select id,contents from %s where lkey='%s'",
                                       name,long_key[..79]));
      foreach( data, mapping m )
        if( m->contents == long_key )
          return m->id;

      db->query( sprintf("insert into %s (contents,lkey,atime) values "
                         "('%s','%s','%d')", 
                         name, long_key, long_key[..79], time() ));
      return create_key( long_key );
    } else {
      string _key=MIME.encode_base64(Crypto.md5()->update(long_key)->digest(),1);
      _key = replace(_key-"=","/","=");
      string short_key = _key[0..1];

      while( file_stat( path+short_key ) )
      {
        if( Stdio.read_bytes( path+short_key ) == long_key )
          return short_key;
        short_key = _key[..strlen(short_key)];
        if( strlen(short_key) >= strlen(_key) )
          short_key += "."; // Not very likely...
      }
      object f = Stdio.File( path + short_key, "wct" );
      f->write( long_key );
      return short_key;
    }
  }


  int key_exists( string key )
  {
    LOCK();
    if( !is_db ) 
      return !!file_stat( path+key );
    return !!read_args( key );
  }

  string store( mapping args )
  {
    LOCK();
    array b = values(args), a = sort(indices(args),b);
    string data = MIME.encode_base64(encode_value(({a,b})),1);

    if( cache[ data ] )
      return cache[ data ][ CACHE_SKEY ];

    string id = create_key( data );
    cache[ data ] = ({ 0, 0 });
    cache[ data ][ CACHE_VALUE ] = copy_value( args );
    cache[ data ][ CACHE_SKEY ] = id;
    cache[ id ] = data;

    if( sizeof( cache ) > CACHE_SIZE )
    {
      array i = indices(cache);
      while( sizeof(cache) > CACHE_SIZE-CLEAN_SIZE )
        m_delete( cache, i[random(sizeof(i))] );
    }
    return id;
  }

  mapping lookup( string id, string|void client )
  {
    LOCK();
    if(cache[id])
      return cache[cache[id]][CACHE_VALUE];

    string q = read_args( id );

    if(!q) error("Key does not exist! (Thinks "+ client +")\n");
    mixed data = decode_value(MIME.decode_base64( q ));
    data = mkmapping( data[0],data[1] );

    cache[ q ] = ({0,0});
    cache[ q ][ CACHE_VALUE ] = data;
    cache[ q ][ CACHE_SKEY ] = id;
    cache[ id ] = q;
    return data;
  }

  void delete( string id )
  {
    LOCK();
    if(cache[id])
    {
      m_delete( cache, cache[id] );
      m_delete( cache, id );
    }
    if( is_db )
      db->query( "delete from "+name+" where id='"+id+"'" );
    else
      rm( path+id );
  }
}


array(int) invert_color(array color )
{
  return ({ 255-color[0], 255-color[1], 255-color[2] });
}


mapping low_decode_image(string data, void|array tocolor)
{
  Image.image i, a;
  string format;
  if(!data)
    return 0; 

#if constant(Image.GIF._decode)  
  // Use the low-level decode function to get the alpha channel.
  catch
  {
    array chunks = Image.GIF._decode( data );

    // If there is more than one render chunk, the image is probably
    // an animation. Handling animations is left as an exercise for
    // the reader. :-)
    foreach(chunks, mixed chunk)
      if(arrayp(chunk) && chunk[0] == Image.GIF.RENDER )
        [i,a] = chunk[3..4];
    format = "GIF";
  };

  if(!i) catch
  {
    i = Image.GIF.decode( data );
    format = "GIF";
  };
#endif

#if constant(Image.JPEG) && constant(Image.JPEG.decode)
  if(!i) catch
  {
    i = Image.JPEG.decode( data );
    format = "JPEG";
  };
#endif

#if constant(Image.XCF) && constant(Image.XCF._decode)
  if(!i) catch
  {
    mixed q = Image.XCF._decode( data,(["background":tocolor,]) );
    tocolor=0;
    format = "XCF Gimp file";
    i = q->image;
    a = q->alpha;
  };
#endif

#if constant(Image.PSD) && constant(Image.PSD._decode)
  if(!i) catch
  {
    mixed q = Image.PSD._decode( data, ([
      "background":tocolor,
      ]));
    tocolor=0;
    format = "PSD Photoshop file";
    i = q->image;
    a = q->alpha;
  };
#endif

#if constant(Image.PNG) && constant(Image.PNG._decode)
  if(!i) catch
  {
    mixed q = Image.PNG._decode( data );
    format = "PNG";
    i = q->image;
    a = q->alpha;
  };
#endif

#if constant(Image.BMP) && constant(Image.BMP._decode)
  if(!i) catch
  {
    mixed q = Image.BMP._decode( data );
    format = "Windows bitmap file";
    i = q->image;
    a = q->alpha;
  };
#endif

#if constant(Image.TGA) && constant(Image.TGA._decode)
  if(!i) catch
  {
    mixed q = Image.TGA._decode( data );
    format = "Targa";
    i = q->image;
    a = q->alpha;
  };
#endif

#if constant(Image.PCX) && constant(Image.PCX._decode)
  if(!i) catch
  {
    mixed q = Image.PCX._decode( data );
    format = "PCX";
    i = q->image;
    a = q->alpha;
  };
#endif

#if constant(Image.XBM) && constant(Image.XBM._decode)
  if(!i) catch
  {
    mixed q = Image.XBM._decode( data, (["bg":tocolor||({255,255,255}),
                                    "fg":invert_color(tocolor||({255,255,255})) ]));
    format = "XBM";
    i = q->image;
    a = q->alpha;
  };
#endif

#if constant(Image.XPM) && constant(Image.XPM._decode)
  if(!i) catch
  {
    mixed q = Image.XPM._decode( data );
    format = "XPM";
    i = q->image;
    a = q->alpha;
  };
#endif

#if constant(Image.TIFF) && constant(Image.TIFF._decode)
  if(!i) catch
  {
    mixed q = Image.TIFF._decode( data );
    format = "TIFF";
    i = q->image;
    a = q->alpha;
  };
#endif

#if constant(Image.ILBM) && constant(Image.ILBM._decode)
  if(!i) catch
  {
    mixed q = Image.ILBM._decode( data );
    format = "ILBM";
    i = q->image;
    a = q->alpha;
  };
#endif


#if constant(Image.PS) && constant(Image.PS._decode)
  if(!i) catch
  {
    mixed q = Image.PS._decode( data );
    format = "Postscript";
    i = q->image;
    a = q->alpha;
  };
#endif

#if constant(Image.XWD) && constant(Image.XWD.decode)
  if(!i) catch
  {
    i = Image.XWD.decode( data );
    format = "XWD";
  };
#endif

#if constant(Image.HRZ) && constant(Image.HRZ._decode)
  if(!i) catch
  {
    mixed q = Image.HRZ._decode( data );
    format = "HRZ";
    i = q->image;
    a = q->alpha;
  };
#endif

#if constant(Image.AVS) && constant(Image.AVS._decode)
  if(!i) catch
  {
    mixed q = Image.AVS._decode( data );
    format = "AVS X";
    i = q->image;
    a = q->alpha;
  };
#endif

  if(!i)
    catch{
      i = Image.PNM.decode( data );
      format = "PNM";
    };

  if(!i) // No image could be decoded at all. 
    return 0;

  if( tocolor && i && a )
  {
    object o = Image.image( i->xsize(), i->ysize(), @tocolor );
    o->paste_mask( i,a );
    i = o;
  }

  return ([
    "format":format,
    "alpha":a,
    "img":i,
  ]);
}

mapping low_load_image(string f,object id)
{
  string data;
  object file, img;
  if(id->misc->_load_image_called < 5) 
  {
    // We were recursing very badly with the demo module here...
    id->misc->_load_image_called++;
    if(!(data=id->conf->try_get_file(f, id)))
    {
      file=Stdio.File();
      if(!file->open(f,"r") || !(data=file->read()))
	return 0;
    }
  }
  id->misc->_load_image_called = 0;
  if(!data)  return 0;
  return low_decode_image( data );
}



object load_image(string f,object id)
{
  mapping q = low_load_image( f, id );
  if( q ) return q->img;
  return 0;
}


private void define_global_variables( int argc, array (string) argv )
{
  int p;

  globvar("set_cookie", 0, "Set unique user id cookies", TYPE_FLAG,
	  #"If set to Yes, all users of your server whose clients support 
cookies will get a unique 'user-id-cookie', this can then be 
used in the log and in scripts to track individual users.");

  deflocaledoc( "svenska", "set_cookie", 
		"S�tt en unik cookie f�r alla anv�ndare",
		#"Om du s�tter den h�r variabeln till 'ja', s� kommer 
alla anv�ndare att f� en unik kaka (cookie) med namnet 'RoxenUserID' satt.  Den
h�r kakan kan anv�ndas i skript f�r att sp�ra individuella anv�ndare.  Det �r
inte rekommenderat att anv�nda den h�r variabeln, m�nga anv�ndare tycker illa
om cookies");

  globvar("set_cookie_only_once",1,"Set ID cookies only once",TYPE_FLAG,
	  #"If set to Yes, Roxen will attempt to set unique user ID cookies
 only upon receiving the first request (and again after some minutes). Thus, if
the user doesn't allow the cookie to be set, she won't be bothered with
multiple requests.",0,
	  lambda() {return !QUERY(set_cookie);});

  deflocaledoc( "svenska", "set_cookie_only_once", 
		"S�tt bara kakan en g�ng per anv�ndare",
		#"Om den h�r variablen �r satt till 'ja' s� kommer roxen bara
f�rs�ka s�tta den unika anv�ndarkakan en g�ng. Det g�r att om anv�ndaren inte
till�ter att kakan s�tts, s� slipper hon eller han iallafall nya fr�gor under
n�gra minuter");

  globvar("RestoreConnLogFull", 0,
	  "Log entire file length in restored connections",
	  TYPE_TOGGLE,
	  "If this toggle is enabled log entries for restored connections "
	  "will log the amount of sent data plus the restoration location. "
	  "Ie if a user has downloaded 100 bytes of a file already, and makes "
	  "a Range request fetching the remaining 900 bytes, the log entry "
	  "will log it as if the entire 1000 bytes were downloaded. "
	  "<p>This is useful if you want to know if downloads were successful "
	  "(the user has the complete file downloaded). The drawback is that "
	  "bandwidth statistics on the log file will be incorrect. The "
	 "statistics in Roxen will continue being correct.");
	 
  deflocaledoc("svenska", "RestoreConnLogFull",
	       "Logga hela fill�ngden vid �terstartad nerladdning",
	       "N�r den h�r flaggar �r satt s� loggar Roxen hela l�ngden p� "
	       "en fil vars nerladdning �terstartas. Om en anv�ndare f�rst "
	       "laddar hem 100 bytes av en fil och sedan laddar hem de "
	       "�terst�ende 900 bytes av filen med en Range-request s� "
	       "kommer Roxen logga det som alla 1000 bytes hade laddats hem. "
	       "<p>Detta kan vara anv�ndbart om du vill se om en anv�ndare "
	       "har lyckats ladda hem hela filen. I normalfallet vill du att "
	       "ha denna flagga avslagen.");

  globvar("show_internals", 1, "Show the internals", TYPE_FLAG,
#"Show 'Internal server error' messages to the user. 
This is very useful if you are debugging your own modules 
or writing Pike scripts.");
  
  deflocaledoc( "svenska", "show_internals", "Visa interna fel",
		#"Visa interna server fel f�r anv�ndaren av servern. 
Det �r v�ldigt anv�ndbart n�r du utvecklar egna moduler eller pikeskript.");

  globvar("default_font_size", 32, 0, TYPE_INT, 0, 0, 1);
  globvar("default_font", "lucida", "Fonts: Default font", TYPE_FONT,
	  "The default font to use when modules request a font.");
  
  deflocaledoc( "svenska", "default_font", "Typsnitt: Normaltypsnitt",
		#"N�r moduler ber om en typsnitt som inte finns, eller skriver 
grafisk text utan att ange ett typsnitt, s� anv�nds det h�r typsnittet.");

  globvar("font_dirs", ({"../local/nfonts/", "nfonts/" }),
	  "Fonts: Font directories", TYPE_DIR_LIST,
	  "This is where the fonts are located.");

  deflocaledoc( "svenska", "font_dirs", "Typsnitt: Typsnittss�kv�g",
		"S�kv�g f�r typsnitt.");


  globvar("logdirprefix", "../logs/", "Log directory prefix",
	  TYPE_DIR|VAR_MORE,
	  #"This is the default file path that will be prepended to the log 
 file path in all the default modules and the virtual server.");

  deflocaledoc( "svenska", "logdirprefix", "Loggningsmappprefix",
		"Alla nya loggar som skapas f�r det h�r prefixet.");
  
  // Cache variables. The actual code recides in the file
  // 'disk_cache.pike'

  
  globvar("cache", 0, "Proxy disk cache: Enabled", TYPE_FLAG,
	  "If set to Yes, caching will be enabled.");
  deflocaledoc( "svenska", "cache", "Proxydiskcache: P�", 
		"Om ja, anv�nd cache i alla proxymoduler som hanterar det.");
  
  globvar("garb_min_garb", 1, "Proxy disk cache: Clean size", TYPE_INT,
  "Minimum number of Megabytes removed when a garbage collect is done.",
	  0, cache_disabled_p);
  deflocaledoc( "svenska", "garb_min_garb",
		"Proxydiskcache: Minimal rensningsm�ngd", 
		"Det minsta antalet Mb som tas bort vid en cacherensning.");
  

  globvar("cache_minimum_left", 5, "Proxy disk cache: Minimum "
	  "available free space and inodes (in %)", TYPE_INT,
#"If less than this amount of disk space or inodes (in %) is left, 
 the cache will remove a few files. This check may work 
 half-hearted if the diskcache is spread over several filesystems.",
	  0,
#if constant(filesystem_stat)
	  cache_disabled_p
#else
	  1
#endif /* filesystem_stat */
	  );
  deflocaledoc( "svenska", "cache_minimum_free", 
		"Proxydiskcache: Minimal fri disk", 
	"Om det �r mindre plats (i %) ledigt p� disken �n vad som "
	"anges i den h�r variabeln s� kommer en cacherensning ske.");
  
  
  globvar("cache_size", 25, "Proxy disk cache: Size", TYPE_INT,
	  "How many MB may the cache grow to before a garbage collect is done?",
	  0, cache_disabled_p);
  deflocaledoc( "svenska", "cache_size", "Proxydiskcache: Storlek", 
		"Cachens maximala storlek, i Mb.");

  globvar("cache_max_num_files", 0, "Proxy disk cache: Maximum number "
	  "of files", TYPE_INT, "How many cache files (inodes) may "
	  "be on disk before a garbage collect is done ? May be left "
	  "zero to disable this check.",
	  0, cache_disabled_p);
  deflocaledoc( "svenska", "cache_max_num_files", 
		"Proxydiskcache: Maximalt antal filer", 
		"Om det finns fler �n s� h�r m�nga filer i cachen "
		"kommer en cacherensning ske. S�tt den h�r variabeln till "
		"noll f�r att hoppa �ver det h�r testet.");
  
  globvar("bytes_per_second", 50, "Proxy disk cache: Bytes per second", 
	  TYPE_INT,
	  "How file size should be treated during garbage collect. "
	  " Each X bytes counts as a second, so that larger files will"
	  " be removed first.",
	  0, cache_disabled_p);
  deflocaledoc( "svenska", "bytes_per_second", 
		"Proxydiskcache: Bytes per sekund", 
		"Normalt s�tt s� tas de �ldsta filerna bort, men filens "
		"storlek modifierar dess '�lder' i cacherensarens �gon. "
		"Den h�r variabeln anger hur m�nga bytes som ska motsvara "
		"en sekund.");

  globvar("cachedir", "/tmp/roxen_cache/",
	  "Proxy disk cache: Base Cache Dir",
	  TYPE_DIR,
	  "This is the base directory where cached files will reside. "
	  "To avoid mishaps, 'roxen_cache/' is always prepended to this "
	  "variable.",
	  0, cache_disabled_p);
  deflocaledoc("svenska", "cachedir", "Proxydiskcache: Cachedirectory",
	       "Den h�r variabeln anger vad cachen ska sparas. "
	       "F�r att undvika fatala misstag s� adderas alltid "
	       "'roxen_cache/' till den h�r variabeln n�r den s�tts om.");

  globvar("hash_num_dirs", 500,
	  "Proxy disk cache: Number of hash directories",
	  TYPE_INT,
	  "This is the number of directories to hash the contents of the disk "
	  "cache into.  Changing this value currently invalidates the whole "
	  "cache, since the cache cannot find the old files.  In the future, "
	  " the cache will be recalculated when this value is changed.",
	  0, cache_disabled_p); 
  deflocaledoc("svenska", "hash_num_dirs", 
	       "Proxydiskcache: Antalet cachesubdirectoryn",
	       "Disk cachen lagrar datan i flera directoryn, den h�r "
	       "variabeln anger i hur m�nga olika directoryn som datan ska "
	       "lagras. Om du �ndrar p� den h�r variabeln s� blir hela den "
	       "gamla cachen invaliderad.");
  
  globvar("cache_keep_without_content_length", 1, "Proxy disk cache: "
	  "Keep without Content-Length", TYPE_FLAG, "Keep files "
	  "without Content-Length header information in the cache?",
	  0, cache_disabled_p);
  deflocaledoc("svenska", "cache_keep_without_content_length", 
	       "Proxydiskcache: Beh�ll filer utan angiven fill�ngd",
	       "Spara filer �ven om de inte har n�gon fill�ngd. "
	       "Cachen kan inneh�lla trasiga filer om den h�r "
	       "variabeln �r satt, men fler filer kan sparas");

  globvar("cache_check_last_modified", 0, "Proxy disk cache: "
	  "Refresh on Last-Modified", TYPE_FLAG,
	  "If set, refreshes files without Expire header information "
	  "when they have reached double the age they had when they got "
	  "cached. This may be useful for some regularly updated docs as "
	  "online newspapers.",
	  0, cache_disabled_p);
  deflocaledoc("svenska", "cache_check_last_modified", 
	       "Proxydiskcache: Kontrollera v�rdet at Last-Modifed headern",
#"Om den h�r variabeln �r satt s� kommer �ven filer utan Expire header att tas
bort ur cachen n�r de blir dubbelt s� gamla som de var n�r de h�mtades fr�n
k�llservern om de har en last-modified header som anger n�r de senast 
�ndrades");

  globvar("cache_last_resort", 0, "Proxy disk cache: "
	  "Last resort (in days)", TYPE_INT,
	  "How many days shall files without Expires and without "
	  "Last-Modified header information be kept?",
	  0, cache_disabled_p);
  deflocaledoc("svenska", "cache_last_resort", 
	       "Proxydiskcache: Spara filer utan datum",
	       "Hur m�nga dagar ska en fil utan b�de Expire och "
	       "Last-Modified beh�llas i cachen? Om du s�tter den "
	       "h�r variabeln till noll kommer de inte att sparas alls.");

  globvar("cache_gc_logfile",  "",
	  "Proxy disk cache: "
	  "Garbage collector logfile", TYPE_FILE,
	  "Information about garbage collector runs, removed and refreshed "
	  "files, cache and disk status goes here.",
	  0, cache_disabled_p);

  deflocaledoc("svenska", "cache_gc_logfile", 
	       "Proxydiskcache: Loggfil",
	       "Information om cacherensningsk�rningar sparas i den h�r filen"
	       ".");
  /// End of cache variables..
  
  globvar("docurl2", "http://www.roxen.com/documentation/context.pike?page=",
	  "Documentation URL", TYPE_STRING|VAR_MORE|VAR_EXPERT,
	  "The URL to prepend to all documentation urls throughout the "
	  "server. This URL should _not_ end with a '/'.");
  deflocaledoc("svenska", "docurl2", "DokumentationsURL",
	       "DokumentationsURLen anv�nds f�r att f� kontextk�nslig hj�lp");

  globvar("pidfile", "/tmp/roxen_pid_$uid", "PID file",
	  TYPE_FILE|VAR_MORE,
	  "In this file, the server will write out it's PID, and the PID "
	  "of the start script. $pid will be replaced with the pid, and "
	  "$uid with the uid of the user running the process.");
  deflocaledoc("svenska", "pidfile", "ProcessIDfil",
	       "I den h�r filen sparas roxen processid och processidt "
	       "for roxens start-skript. $uid byts ut mot anv�ndaridt f�r "
	       "den anv�ndare som k�r roxen");

  globvar("default_ident", 1, "Identify: Use default identification string",
	  TYPE_FLAG|VAR_MORE,
	  "Setting this variable to No will display the \"Identify as\" node "
	  "where you can state what Roxen should call itself when talking "
	  "to clients, otherwise it will present it self as \""+ real_version
	  +"\".<br>"
	  "It is possible to disable this so that you can enter an "
	  "identification-string that does not include the actual version of "
	  "Roxen, as recommended by the HTTP/1.0 draft 03:<p><blockquote><i>"
	  "Note: Revealing the specific software version of the server "
	  "may allow the server machine to become more vulnerable to "
	  "attacks against software that is known to contain security "
	  "holes. Server implementors are encouraged to make this field "
	  "a configurable option.</i></blockquote>");
  deflocaledoc("svenska", "default_ident", "Identitet: Anv�nd roxens normala"
	       " identitetsstr�ng",
	       "Ska roxen anv�nda sitt normala namn ("+real_version+")."
	       "Om du s�tter den h�r variabeln till 'nej' s� kommer du att "
	       "f� v�lja vad roxen ska kalla sig.");

  globvar("ident", replace(real_version," ","�"), "Identify: Identify as",
	  TYPE_STRING /* |VAR_MORE */,
	  "Enter the name that Roxen should use when talking to clients. ",
	  0, ident_disabled_p);
  deflocaledoc("svenska", "ident", "Identitet: Roxens identitet",
	       "Det h�r �r det namn som roxen kommer att anv�nda sig av.");

  globvar("DOC", 1, "Configuration interface: Help texts", TYPE_FLAG|VAR_MORE,
	  "Do you want documentation? (this is an example of documentation)");
  deflocaledoc("svenska", "DOC", "Konfigurationsinterfacet: Hj�lptexter",
	       "Vill du ha hj�lptexter (den h�r texten �r en typisk "
	       " hj�lptext)");

  globvar("NumAccept", 1, "Number of accepts to attempt",
	  TYPE_INT_LIST|VAR_MORE,
	  "You can here state the maximum number of accepts to attempt for "
	  "each read callback from the main socket. <p> Increasing this value "
	  "will make the server faster for users making many simultaneous "
	  "connections to it, or if you have a very busy server. The higher "
	  "you set this value, the less load balancing between virtual "
	  "servers. (If there are 256 more or less simultaneous "
	  "requests to server 1, and one to server 2, and this variable is "
	  "set to 256, the 256 accesses to the first server might very well "
	  "be handled before the one to the second server.)",
	  ({ 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024 }));
  deflocaledoc("svenska", "NumAccept", 
	       "Uppkopplingsmottagningsf�rs�k per varv i huvudloopen",
	       "Antalet uppkopplingsmottagningsf�rs�k per varv i huvudlopen. "
	       "Om du �kar det h�r v�rdet s� kan server svara snabbare om "
	       "v�ldigt m�nga anv�nder den, men lastbalanseringen mellan dina "
	       "virtuella servrar kommer att bli mycket s�mre (t�nk dig att "
	       "det ligger 255 uppkopplingar och v�ntar i k�n f�r en server"
	       ", och en uppkoppling i k�n till din andra server, och du  "
	       " har satt den h�r variabeln till 256. Alla de 255 "
	       "uppkopplingarna mot den f�rsta servern kan d� komma "
	       "att hanteras <b>f�re</b> den ensamma uppkopplingen till "
	       "den andra server.");

  globvar("ConfigPorts", ({ ({ 22202, "http", "ANY", "" }) }),
	  "Configuration interface: Ports",
	  TYPE_PORTS,
#"These are the ports through which you can configure the server.<br>

Note that you should at least have one open port, since otherwise you won't be
able to configure your server.");

  deflocaledoc("svenska", "ConfigPorts",
	       "Konfigurationsinterfacet: Portar",
#"Det h�r �r de portar som du kan anv�nda f�r att konfigurera
 servern. <br>

Notera att du alltid b�r ha <b>minst</b> en port �ppen, s� om du
 t.ex. ska flytta konfigurationsinterfacet fr�n en http port till en ssl3 port,
 ta inte bort den gamla porten innan du har verifierat att den nya verkligen
 fungerar. Det �r r�tt sv�rt att konfigurera roxen utan dess
 konfigurationsinterface, �ven om det g�r.");

  globvar("ModuleListType", "Original",
	  "Configuration interface: Add module page look  ",
	  TYPE_STRING_LIST,
#"This variable defines how the add module page will look like. The original
version has graphical headers and the description for each of the modules.
If you know your way around Roxen, the compact mode might be better. Then
You will get a select list which contains module names only.",
	  ({ "Original", "Compact" }));

  deflocaledoc("svenska", "ModuleListType",
	       "Konfigurationsinterfacet: Utseendet av addera-modulsidan",
#"H�r kan du st�lla in utseendet av sidan d�r du adderar nya moduler.
Standardversionen har en l�ng sida med alla moduler med modulbeskrivningar.
Den kompakta versionen inneh�ller bara en select-lista med alla moduler,
utan hj�lptexterna och g�r d�rf�r mycket snabbare att ladda.",
	       ([ "Original": "Standard",
		  "Compact" : "Kompakt" ]));


  globvar("ConfigurationURL", 
	  "",
          "Configuration interface: URL", TYPE_STRING,
	  "The URL of the configuration interface. This is used to "
	  "generate redirects now and then (when you press save, when "
	  "a module is added, etc.).");
  deflocaledoc("svenska", "ConfigurationURL",
	       "Konfigurationsinterfacet: URL",
	       #"Konfigurationsinterfacets URL. Normalt s�tt s� beh�ver du 
inte st�lla in den h�r variabeln, eftersom den automatiskt genereras fr�n
 portvariablen, men ibland kan det vara bra att kunna st�lla in den.");

  globvar("ConfigurationPassword", "", "Configuration interface: Password", 
	  TYPE_PASSWORD|VAR_EXPERT,
	  "The password you will have to enter to use the configuration "
	  "interface. Please note that changing this password in the "
	  "configuration interface will _not_ require an additional entry "
	  "of the password, so it is easy to make a typo. It is recommended "
	  "that you use the <a href=/(changepass)/Globals/>form instead</a>.");
  deflocaledoc("svenska", "ConfigurationPassword",
	       "Konfigurationsinterface: L�senord",
	       #"Den h�r variablen b�r du inte pilla p�. Men det �r l�senordet
 f�r anv�ndaren  som ska f� konfigurera roxen, krypterat med crypt(3)");

  globvar("ConfigurationUser", "", "Configuration interface: User", 
	  TYPE_STRING|VAR_EXPERT,
	  "The username you will have to enter to use the configuration "
	  "interface");
  deflocaledoc("svenska", "ConfigurationUser", 
	       "Konfigurationsinterface: Anv�ndare",
	       #"Den h�r variablen b�r du inte pilla p�. Men det �r anv�ndaren
 som ska f� konfigurera roxen");
  
  globvar("ConfigurationIPpattern","*", "Configuration interface: IP-Pattern", 
	  TYPE_STRING|VAR_MORE,
	  "Only clients running on computers with IP numbers matching "
	  "this pattern will be able to use the configuration "
	  "interface.");
  deflocaledoc("svenska", "ConfigurationIPpattern",
	       "Konfigurationsinterfacet: IPnummerm�nster",
#"Bara klienters vars datorers IP-nummer matchar det h�r m�nstret
  kan ansluta till konfigurationsinterfacet. Ett normalt m�nster �r ditt lokala
  C-n�t, t.ex. 194.52.182.*.");

  globvar("User", "", "Change uid and gid to", TYPE_STRING,
	  "When roxen is run as root, to be able to open port 80 "
	  "for listening, change to this user-id and group-id when the port "
	  " has been opened. If you specify a symbolic username, the "
	  "default group of that user will be used. "
	  "The syntax is user[:group].");
  deflocaledoc("svenska", "User", "Byt UID till",
#"N�r roxen startas som root, f�r att kunna �ppna port 80 och k�ra CGI skript
samt pike skript som den anv�ndare som �ger dem, s� kan du om du vill
specifiera ett anv�ndarnamn h�r. Roxen kommer om du g�r det att byta till den
anv�ndaren n�r s� fort den har �ppnat sina portar. Roxen kan dock fortfarande
byta tillbaka till root f�r att k�ra skript som r�tt anv�ndare om du inte
s�tter variabeln 'Byt UID och GID permanent' till ja.  Anv�ndaren kan
specifieras antingen som ett symbolisk anv�ndarnamn (t.ex. 'www') eller som ett
numeriskt anv�ndarID.  Om du vill kan du specifera vilken grupp som ska
anv�ndas genom att skriva anv�ndare:grupp. Normalt s�tt s� anv�nds anv�ndarens
normal grupper.");

  globvar("permanent_uid", 0, "Change uid and gid permanently", 
	  TYPE_FLAG,
	  "If this variable is set, roxen will set it's uid and gid "
	  "permanently. This disables the 'exec script as user' fetures "
	  "for CGI, and also access files as user in the filesystems, but "
	  "it gives better security.");
  deflocaledoc("svenska", "permanent_uid",
	       "Byt UID och GID permanent",
#"Om roxen byter UID och GID permament kommer det inte g� att konfigurera nya
  portar under 1024, det kommer inte heller g� att k�ra CGI och pike skript som
  den anv�ndare som �ger skriptet. D�remot s� kommer s�kerheten att vara h�gre,
  eftersom ingen kan f� roxen att g�ra n�got som administrat�ranv�ndaren 
  root");

  globvar("ModuleDirs", ({ "../local/modules/", "modules/" }),
	  "Module directories", TYPE_DIR_LIST,
	  "This is a list of directories where Roxen should look for "
	  "modules. Can be relative paths, from the "
	  "directory you started roxen, " + getcwd() + " this time."
	  " The directories are searched in order for modules.");
  deflocaledoc("svenska", "ModuleDirs", "Moduls�kv�g",
#"En lista av directoryn som kommer att s�kas igenom n�r en 
  modul ska laddas. Directorynamnen kan vara relativa fr�n "+getcwd()+
", och de kommer att s�kas igenom i den ordning som de st�r i listan.");

  globvar("Supports", "#include <etc/supports>\n", 
	  "Client supports regexps", TYPE_TEXT_FIELD|VAR_MORE,
	  "What do the different clients support?\n<br>"
	  "The default information is normally fetched from the file "+
	  getcwd()+"etc/supports, and the format is:<pre>"
	  //"<a href=$docurl/configuration/regexp.html>regular-expression</a>"
	  "regular-expression"
	  " feature, -feature, ...\n"
	  "</pre>"
	  "If '-' is prepended to the name of the feature, it will be removed"
	  " from the list of features of that client. All patterns that match"
	  " each given client-name are combined to form the final feature list"
	  ". See the file etc/supports for examples.");
  deflocaledoc("svenska", "Supports", 
	       "Bl�ddrarfunktionalitetsdatabas",
#"En databas �ver vilka funktioner de olika bl�ddrarna som anv�nds klarar av.
  Normalt s�tt s� h�mtas den h�r databasen fr�n filen server/etc/supports, men
  du kan om du vill specifiera fler m�nster i den h�r variabeln. Formatet ser
  ur s� h�r:<pre>
  regulj�rt uttryck som matchar b�ddrarens namn	funktion, funktion, ...
 </pre>Se filen server/etc/supports f�r en mer utf�rlig dokumentation");

  globvar("audit", 0, "Audit trail", TYPE_FLAG,
	  "If Audit trail is set to Yes, all changes of uid will be "
	  "logged in the Event log.");
  deflocaledoc("svenska", "audit", "Logga alla anv�ndaridv�xlingar",
#"Om du sl�r p� den �r funktionen s� kommer roxen logga i debugloggen (eller
systemloggen om den funktionen anv�nds) s� fort anv�ndaridt byts av n�gon
anlending.");

#if efun(syslog) 
  globvar("LogA", "file", "Logging method", TYPE_STRING_LIST|VAR_MORE, 
	  "What method to use for logging, default is file, but "
	  "syslog is also available. When using file, the output is really"
	  " sent to stdout and stderr, but this is handled by the "
	  "start script.",
	  ({ "file", "syslog" }));
  deflocaledoc("svenska", "LogA", "Loggningsmetod",
#"Hur ska roxens debug, fel, informations och varningsmeddelanden loggas?
  Normalt s�tt s� loggas de tilldebugloggen (logs/debug/defaul.1 etc), men de
  kan �ven skickas till systemloggen kan om du vill.",
		 ([ "file":"loggfil",
		    "syslog":"systemloggen"]));
  
  globvar("LogSP", 1, "Syslog: Log PID", TYPE_FLAG,
	  "If set, the PID will be included in the syslog.", 0,
	  syslog_disabled);
  deflocaledoc("svenska", "LogSP", "Systemlogg: Logga roxens processid",
		 "Ska roxens processid loggas i systemloggen?");
  globvar("LogCO", 0, "Syslog: Log to system console", TYPE_FLAG,
	  "If set and syslog is used, the error/debug message will be printed"
	  " to the system console as well as to the system log.",
	  0, syslog_disabled);
  deflocaledoc("svenska", "LogCO", "Systemlogg: Logga till konsolen",
	       "Ska roxen logga till konsolen? Om den h�r variabeln �r satt "
	       "kommer alla meddelanden som g�r till systemloggen att �ven "
	       "skickas till datorns konsol.");
  globvar("LogST", "Daemon", "Syslog: Log type", TYPE_STRING_LIST,
	  "When using SYSLOG, which log type should be used.",
	  ({ "Daemon", "Local 0", "Local 1", "Local 2", "Local 3",
	     "Local 4", "Local 5", "Local 6", "Local 7", "User" }),
	  syslog_disabled);
  deflocaledoc( "svenska", "LogST", "Systemlogg: Loggningstyp",
		"N�r systemloggen anv�nds, vilken loggningstyp ska "
		"roxen anv�nda?");
		
  globvar("LogWH", "Errors", "Syslog: Log what", TYPE_STRING_LIST,
	  "When syslog is used, how much should be sent to it?<br><hr>"
	  "Fatal:    Only messages about fatal errors<br>"+
	  "Errors:   Only error or fatal messages<br>"+
	  "Warning:  Warning messages as well<br>"+
	  "Debug:    Debug messager as well<br>"+
	  "All:      Everything<br>",
	  ({ "Fatal", "Errors",  "Warnings", "Debug", "All" }),
	  syslog_disabled);
  deflocaledoc("svenska", "LogWH", "Systemlogg: Logga vad",
	       "N�r systemlogen anv�nds, vad ska skickas till den?<br><hr>"
          "Fatala:    Bara felmeddelenaden som �r uppm�rkta som fatala<br>"+
	  "Fel:       Bara felmeddelanden och fatala fel<br>"+
	  "Varningar: Samma som ovan, men �ven alla varningsmeddelanden<br>"+
	  "Debug:     Samma som ovan, men �ven alla felmeddelanden<br>"+
          "Allt:     Allt<br>", 
	       ([ "Fatal":"Fatala", 
		  "Errors":"Fel", 
		  "Warnings":"Varningar", 
		  "Debug":"Debug", 
		  "All":"Allt" ]));

	       globvar("LogNA", "Roxen", "Syslog: Log as", TYPE_STRING,
	  "When syslog is used, this will be the identification of the "
	  "Roxen daemon. The entered value will be appended to all logs.",
	  0, syslog_disabled);
  deflocaledoc("svenska", "LogNA", 
	       "Systemlogg: Logga som",
#"N�r systemloggen anv�nds s� kommer v�rdet av den h�r variabeln anv�ndas
  f�r att identifiera den h�r roxenservern i loggarna.");
#endif

#ifdef THREADS
  globvar("numthreads", 5, "Number of threads to run", TYPE_INT,
	  "The number of simultaneous threads roxen will use.\n"
	  "<p>Please note that even if this is one, Roxen will still "
	  "be able to serve multiple requests, using a select loop based "
	  "system.\n"
	  "<i>This is quite useful if you have more than one CPU in "
	  "your machine, or if you have a lot of slow NFS accesses.</i>");
  deflocaledoc("svenska", "numthreads",
	       "Antal tr�dar",
#"Roxen har en s� kallad tr�dpool. Varje f�rfr�gan som kommer in till roxen
 hanteras av en tr�d, om alla tr�dar �r upptagna s� st�lls fr�gan i en k�.
 Det �r bara sj�lva hittandet av r�tt fil att skicka som anv�nder de h�r
 tr�darna, skickandet av svaret till klienten sker i bakgrunden, s� du beh�ver
 bara ta h�nsyn till evenetuella processorintensiva saker (som &lt;gtext&gt;)
 n�r d� st�ller in den h�r variabeln. Sk�nskv�rdet 5 r�cker f�r de allra 
 flesta servrar");
#endif
  
  globvar("AutoUpdate", 1, "Update the supports database automatically",
	  TYPE_FLAG, 
	  "If set to Yes, the etc/supports file will be updated automatically "
	  "from www.roxen.com now and then. This is recomended, since "
	  "you will then automatically get supports information for new "
	  "clients, and new versions of old ones.");
  deflocaledoc("svenska", "AutoUpdate",
	       "Uppdatera 'supports' databasen automatiskt",
#"Ska supportsdatabasen uppdateras automatiskt fr�n www.roxen.com en g�ng per
 vecka? Om den h�r optionen �r p�slagen s� kommer roxen att f�rs�ka ladda ner
  en ny version av filen etc/supports fr�n http://www.roxen.com/supports en 
  g�ng per vecka. Det �r rekommenderat att du l�ter den vara p�, eftersom det
  kommer nya versioner av bl�ddrare hela tiden, som kan hantera nya saker.");

  globvar("next_supports_update", time()+3600, "", TYPE_INT,"",0,1);

  globvar("abs_engage", 0, "Anti-Block-System: Enable", TYPE_FLAG|VAR_MORE,
#"If set, the anti-block-system will be enabled.
  This will restart the server after a configurable number of minutes if it 
  locks up. If you are running in a single threaded environment heavy 
  calculations will also halt the server. In multi-threaded mode bugs such as 
  eternal loops will not cause the server to reboot, since only one thread is
  blocked. In general there is no harm in having this option enabled. ");

  deflocaledoc("svenska", "abs_engage",
	       "AntiBlockSystem: Sl� p� AntiBlockSystemet",
#"Ska antil�ssystemet vara ig�ng? Om det �r det s� kommer roxen automatiskt
  att starta om om den har h�ngt sig mer �n n�gra minuter. Oftast s� beror
  h�ngningar p� buggar i antingen operativsystemet eller i en modul. Den 
  senare typen av h�ngningar p�verkar inte en tr�dad roxen, medans den f�rsta
  typen g�r det.");

  globvar("abs_timeout", 5, "Anti-Block-System: Timeout", 
	  TYPE_INT_LIST|VAR_MORE,
#"If the server is unable to accept connection for this many 
  minutes, it will be restarted. You need to find a balance: 
  if set too low, the server will be restarted even if it's doing 
  legal things (like generating many images), if set too high you might 
  get a long downtime if the server for some reason locks up.",
  ({1,2,3,4,5,10,15}),
  lambda() {return !QUERY(abs_engage);});

  deflocaledoc("svenska", "abs_timeout",
	       "AntiBlockSystem: Tidsbegr�nsning",
#"Om servern inte svarar p� n�gra fr�gor under s� h�r m�nga 
 minuter s� kommer roxen startas om automatiskt.  Om du 
 har en v�ldigt l�ngsam dator kan en minut vara f�r 
 kort tid f�r en del saker, t.ex. diagramritning kan ta 
 ett bra tag.");


  globvar("locale", "standard", "Language", TYPE_STRING_LIST,
	  "Locale, used to localise all messages in roxen.\n"
#"Standard means using the default locale, which varies according to the 
value of the 'LANG' environment variable.", sort(indices(Locale.Roxen) -
						 ({ "Modules" })));
  deflocaledoc("svenska", "locale", "Spr�k",
	       "Den h�r variablen anger vilket spr�k roxen ska anv�nda. "
	       "'standard' betyder att spr�ket s�tts automatiskt fr�n "
	       "v�rdet av omgivningsvariabeln LANG.");

  globvar("suicide_engage",
	  0,
	  "Automatic Restart: Enable",
	  TYPE_FLAG|VAR_MORE,
#"If set, Roxen will automatically restart after a configurable number of
days. Since Roxen uses a monolith, non-forking server model the process tends
to grow in size over time. This is mainly due to heap fragmentation but also
because of memory leaks."
	  );
  deflocaledoc("svenska", "suicide_engage",
	       "Automatisk omstart: Starta om automatiskt",
#"Roxen har st�d f�r att starta automatiskt d� ock d�. Eftersom roxen �r en
monolitisk icke-forkande server (en enda l�nglivad process) s� tenderar
processen att v�xa med tiden.  Det beror mest p� minnesfragmentation, men �ven
p� att en del minnesl�ckor fortfarande finns kvar. Ett s�tt att �tervinna minne
�r att starta om servern lite d� och d�, vilket roxen kommer att g�ra om du
sl�r p� den h�r funktionen. Notera att det tar ett litet tag att starta om
 servern.");

globvar("suicide_timeout",
	  7,
	  "Automatic Restart: Timeout",
	  TYPE_INT_LIST|VAR_MORE,
	  "Automatically restart the server after this many days.",
	  ({1,2,3,4,5,6,7,14,30}),
	  lambda(){return !QUERY(suicide_engage);});
  deflocaledoc("svenska", "suicide_timeout",
	       "Automatisk omstart: Tidsbegr�nsning (i dagar)",
#"Om roxen �r inst�lld till att starta om automatiskt, starta om
s� h�r ofta. Tiden �r angiven i dagar");


  globvar("argument_cache_in_db", 0, 
         "Argument Cache: Store the argument cache in a mysql database",
         TYPE_FLAG|VAR_MORE,
         "If set, store the argument cache in a mysql "
         "database. This is very useful for load balancing using multiple "
         "roxen servers, since the mysql database will handle "
          " synchronization"); 

  globvar( "argument_cache_db_path", "mysql://localhost/roxen", 
          "Argument Cache: Database URL to use",
          TYPE_STRING|VAR_MORE,
          "The database to use to store the argument cache",
          0,
          lambda(){ return !QUERY(argument_cache_in_db); });

  globvar( "argument_cache_dir", "../argument_cache/", 
          "Argument Cache: Cache directory",
          TYPE_DIR|VAR_MORE,
          "The cache directory to use to store the argument cache."
          " Please note that load balancing is not available for most modules "
          " (such as gtext, diagram etc) unless you use a mysql database to "
          "store the argument caches",
          0,
          lambda(){ return QUERY(argument_cache_in_db); });




  setvars(retrieve("Variables", 0));

  for(p = 1; p < argc; p++)
  {
    string c, v;
    if(sscanf(argv[p],"%s=%s", c, v) == 2)
    {
      sscanf(c, "%*[-]%s", c);
      if(variables[c])
      {
        if(catch{
          mixed res = compile_string( "mixed f(){ return "+v+";}")()->f();
          if(sprintf("%t", res) != sprintf("%t", variables[c][VAR_VALUE]) &&
             res != 0 && variables[c][VAR_VALUE] != 0)
            werror("Warning: Setting variable "+c+"\n"
                   "to a value of a different type than the default value.\n"
                   "Default was "+sprintf("%t", variables[c][VAR_VALUE])+
                   " new is "+sprintf("%t", res)+"\n");
          variables[c][VAR_VALUE]=res;
        })
        {
          werror("Warning: Asuming '"+v+"' should be taken "
                 "as a string value.\n");
          if(!stringp(variables[c][VAR_VALUE]))
            werror("Warning: Old value was not a string.\n");
          variables[c][VAR_VALUE]=v;
        }
      }
      else
	perror("Unknown variable: "+c+"\n");
    }
  }
  docurl=QUERY(docurl2);

}


// Somewhat misnamed, since there can be more then one
// configuration-interface port nowdays. But, anyway, this function
// opens and listens to all configuration interface ports.
void initiate_configuration_port( int|void first )
{
  object o;
  array port;

  // Hm.
  if(!first && !config_ports_changed )
    return 0;
  
  config_ports_changed = 0;

  // First find out if we have any new ports.
  mapping(string:array(string)) new_ports = ([]);
  foreach(QUERY(ConfigPorts), port) {
    if ((< "ssl", "ssleay", "ssl3" >)[port[1]]) {
      // Obsolete versions of the SSL protocol.
      report_warning(LOCALE->obsolete_ssl(port[1]));
      port[1] = "https";
    } else if ((< "ftp2" >)[port[1]]) {
      // ftp2.pike has replaced ftp.pike entirely.
      report_warning(LOCALE->obsolete_ftp(port[1]));
      port[1] = "ftp";
    }
    string key = MKPORTKEY(port);
    if (!configuration_ports[key]) {
      report_notice(LOCALE->new_config_port(key));
      new_ports[key] = port;
    } else {
      // This is needed not to delete old unchanged ports.
      new_ports[key] = 0;
    }
  }

  // Then disable the old ones that are no more.
  foreach(indices(configuration_ports), string key) {
    if (zero_type(new_ports[key])) {
      report_notice(LOCALE->disable_config_port(key));
      object o = configuration_ports[key];
      if (main_configuration_port == o) {
	main_configuration_port = 0;
      }
      m_delete(configuration_ports, key);
      mixed err;
      if (err = catch{
	destruct(o);
      }) {
	report_warning(LOCALE->
		       error_disabling_config_port(key,
						   describe_backtrace(err)));
      }
      o = 0;	// Be sure that there are no references left...
    }
  }

  // Now we can create the new ports.
  foreach(indices(new_ports), string key)
  {
    port = new_ports[key];
    if (port) {
      array old = port;
      mixed erro;
      erro = catch {
	program requestprogram = (program)(getcwd()+"/protocols/"+port[1]);
	function rp;
	array tmp;
	if(!requestprogram) {
	  report_error(LOCALE->no_request_program(port[1]));
	  continue;
	}
	if(rp = requestprogram()->real_port)
	  if(tmp = rp(port, 0))
	    port = tmp;

	// FIXME: For SSL3 we might need to be root to read our
	// secret files.
	object privs;
	if(port[0] < 1024)
	  privs = Privs(LOCALE->opening_low_port());
	if(o=create_listen_socket(port[0],0,port[2],requestprogram,port)) {
	  report_notice(LOCALE->opening_config_port(key));
	  if (!main_configuration_port) {
	    main_configuration_port = o;
	  }
	  configuration_ports[key] = o;
	} else {
	  report_error(LOCALE->could_not_open_config_port(key));
	}
      };
      if (erro) {
	report_error(LOCALE->open_config_port_failed(key,
			     (stringp(erro)?erro:describe_backtrace(erro))));
      }
    }
  }
  if(!main_configuration_port)
  {
    if (sizeof(configuration_ports)) {
      // This case happens when you delete the main config port,
      // but still have others left.
      main_configuration_port = values(configuration_ports)[0];
    } else {
      report_error(LOCALE->no_config_port());
      if(first)
	exit( -1 );	// Restart.
    }
  }
}
#include <stat.h>
// Find all modules, so a list of them can be presented to the
// user. This is not needed when the server is started.
void scan_module_dir(string d)
{
  if(sscanf(d, "%*s.pmod")!=0) return;
  MD_PERROR(("\n\nLooking for modules in "+d+" "));

  string file,path=d;
  mixed err;
  array q  = (get_dir( d )||({})) - ({".","..","CVS","RCS" });
  if(!sizeof(q)) {
    MD_PERROR(("No modules in here. Continuing elsewhere\n"));
    return;
  }
  if(search(q, ".no_modules")!=-1) {
    MD_PERROR(("No modules in here. Continuing elsewhere\n"));
    return;
  }
  MD_PERROR(("There are "+language("en","number")(sizeof(q))+" files.\n"));

  foreach( q, file )
  {
    object e = ErrorContainer();
    master()->set_inhibit_compile_errors(e->got_error);
    if ( file[0]!='.' && !backup_extension(file) && (file[-1]!='z'))
    {
      array stat = file_stat(path+file);
      if(!stat || (stat[ST_SIZE] < 0))
      {
	if(err = catch ( scan_module_dir(path+file+"/") ))
	  MD_PERROR((sprintf("Error in module rescanning directory code:"
			     " %s\n",describe_backtrace(err))));
      } else {
	MD_PERROR(("Considering "+file+" - "));
	if((module_stat_cache[path+file] &&
	    module_stat_cache[path+file][ST_MTIME])==stat[ST_MTIME])
	{
	  MD_PERROR(("Already tried this one.\n"));
	  continue;
	}
	module_stat_cache[path+file]=stat;
	
	switch(extension(file))
	{
	case "pike":
	case "lpc":
	  if(catch{
	    if((open(path+file,"r")->read(4))=="#!NO") {
	      MD_PERROR(("Not a module\n"));
	      file=0;
	    }
	  }) {
	    MD_PERROR(("Couldn't open file\n"));
	    file=0;
	  }
	  if(!file) break;
	case "mod":
	case "so":
	  string *module_info;
	  if (!(err = catch( module_info = compile_module(path + file)))) {
	    // Load OK
	    if (module_info) {
	      // Module load OK.
	      allmodules[ file-("."+extension(file)) ] = module_info;
	    } else {
	      // Disabled module.
	      report_notice(LOCALE->disabled_module(path+file));
	    }
	  } else {
	    // Load failed.
	    module_stat_cache[path+file]=0;
	    e->errors += "\n";
// 	    if (arrayp(err)) {
// 	      e->errors += path + file + ":" +describe_backtrace(err) + "\n";
// 	    } else {
// 	      _master->errors += path + file + ": " + err;
// 	    }
	  }
	}
	MD_PERROR(("\n"));
      }
    }
    master()->set_inhibit_compile_errors(0);
    if(strlen(e->get())) {
      report_debug(LOCALE->module_compilation_errors(d, e->get()));
    }
  }
}

void rescan_modules()
{
  string file, path;
  mixed err;
  report_notice(LOCALE->scanning_for_modules());
  if (!allmodules) {
    allmodules=copy_value(somemodules);
  }

  foreach(QUERY(ModuleDirs), path)
  {
    array err;
    err = catch(scan_module_dir( path ));
    if(err) {
      report_error(LOCALE->module_scan_error(path, describe_backtrace(err)));
    }
  }
  catch {
    rm(".module_stat_cache");
    rm(".allmodules");
    Stdio.write_file(".module_stat_cache", encode_value(module_stat_cache));
    Stdio.write_file(".allmodules", encode_value(allmodules));
  };
  report_notice(LOCALE->module_scan_done(sizeof(allmodules)));
}

// do the chroot() call. This is not currently recommended, since
// roxen dynamically loads modules, all module files must be
// available at the new location.

private void fix_root(string to)
{
#ifndef __NT__
  if(getuid())
  {
    perror("It is impossible to chroot() if the server is not run as root.\n");
    return;
  }

  if(!chroot(to))
  {
    perror("Roxen: Cannot chroot to "+to+": ");
#if efun(real_perror)
    real_perror();
#endif
    return;
  }
  perror("Root is now "+to+".\n");
#endif
}

void create_pid_file(string where)
{
#ifndef __NT__
  if(!where) return;
  where = replace(where, ({ "$pid", "$uid" }), 
		  ({ (string)getpid(), (string)getuid() }));

  rm(where);
  if(catch(Stdio.write_file(where, sprintf("%d\n%d", getpid(), getppid()))))
    perror("I cannot create the pid file ("+where+").\n");
#endif
}


object shuffle(object from, object to,
	       object|void to2, function(:void)|void callback)
{
#if efun(spider.shuffle)
  if(!to2)
  {
    object p = pipe();
    p->input(from);
    p->set_done_callback(callback);
    p->output(to);
    return p;
  } else {
#endif
    // 'smartpipe' does not support multiple outputs.
    object p = Pipe.pipe();
    if (callback) p->set_done_callback(callback);
    p->output(to);
    if(to2) p->output(to2);
    p->input(from);
    return p;
#if efun(spider.shuffle)
  }
#endif
}


static private int _recurse;
// FIXME: Ought to use the shutdown code.
void exit_when_done()
{
  object o;
  int i;
  roxen_perror("Interrupt request received. Exiting,\n");
  die_die_die=1;
//   trace(9);
  if(++_recurse > 4)
  {
    roxen_perror("Exiting roxen (spurious signals received).\n");
    stop_all_modules();
#ifdef THREADS
    stop_handler_threads();
#endif /* THREADS */
    exit(-1);	// Restart.
  }

  // First kill off all listening sockets.. 
  foreach(indices(portno)||({}), o)
  {
#ifdef THREADS
    object fd = Stdio.File();
    fd->connect( portno[o][2]!="Any"?portno[o][2]:"127.0.0.1", portno[o][0] );
    destruct(fd);
#endif
    destruct(o);
  }
  
  // Then wait for all sockets, but maximum 10 minutes.. 
  call_out(lambda() { 
    call_out(Simulate.this_function(), 5);
    if(!_pipe_debug()[0])
    {
      roxen_perror("Exiting roxen (all connections closed).\n");
      stop_all_modules();
#ifdef THREADS
      stop_handler_threads();
#endif /* THREADS */
      add_constant("roxen", 0);	// Paranoia...
      exit(-1);	// Restart.
      roxen_perror("Odd. I am not dead yet.\n");
    }
  }, 0.1);
  call_out(lambda(){
    roxen_perror("Exiting roxen (timeout).\n");
    stop_all_modules();
#ifdef THREADS
    stop_handler_threads();
#endif /* THREADS */
    add_constant("roxen", 0);	// Paranoia...
    exit(-1); // Restart.
  }, 600, 0); // Slow buggers..
}

void exit_it()
{
  perror("Recursive signals.\n");
  exit(-1);	// Restart.
}

void set_locale( string to )
{
  if( to == "standard" )
    SET_LOCALE( default_locale );
  SET_LOCALE( Locale.Roxen[ to ] || default_locale );
}


// Dump all threads to the debug log.
void describe_all_threads()
{
  array(mixed) all_backtraces;
#if constant(all_threads)
  all_backtraces = all_threads()->backtrace();
#else /* !constant(all_threads) */
  all_backtraces = ({ backtrace() });
#endif /* constant(all_threads) */

  werror("Describing all threads:\n");
  int i;
  for(i=0; i < sizeof(all_backtraces); i++) {
    werror(sprintf("Thread %d:\n"
		   "%s\n",
		   i+1,
		   describe_backtrace(all_backtraces[i])));
  }
}

// And then we have the main function, this is the oldest function in
// Roxen :) It has not changed all that much since Spider 2.0.
int main(int|void argc, array (string)|void argv)
{
  if(getenv("LANG")=="sv")
    default_locale = ( Locale.Roxen.svenska );
//   else
//     SET_LOCALE( Locale.Roxen.standard );
  SET_LOCALE(default_locale);
  initiate_languages();
  mixed tmp;

  start_time = boot_time = time();

  add_constant("write", perror);

  
  mark_fd(0, "Stdin");
  mark_fd(1, "Stdout");
  mark_fd(2, "Stderr");

  configuration_dir =
    Getopt.find_option(argv, "d",({"config-dir","configuration-directory" }),
	     ({ "ROXEN_CONFIGDIR", "CONFIGURATIONS" }), "../configurations");

  if(configuration_dir[-1] != '/')
    configuration_dir += "/";


  startpid = getppid();
  roxenpid = getpid();

  // Dangerous...
  if(tmp = Getopt.find_option(argv, "r", "root")) fix_root(tmp);

  argv -= ({ 0 });
  argc = sizeof(argv);

  roxen_perror("Restart initiated at "+ctime(time())); 

  define_global_variables(argc, argv);
  object o;
  if(QUERY(locale) != "standard" && (o = Locale.Roxen[QUERY(locale)]))
  {
    default_locale = o;
    SET_LOCALE(default_locale);
  }
  report_notice(LOCALE->starting_roxen());
  
#if efun(syslog)
  init_logger();
#endif

  init_garber();
  initiate_supports();
  
  initiate_configuration_port( 1 );
  enable_configurations();

  set_u_and_gid();		// Running with the right uid:gid from this point on.

  create_pid_file(Getopt.find_option(argv, "p", "pid-file", "ROXEN_PID_FILE")
		  || QUERY(pidfile));

  roxen_perror("Initiating argument cache ... ");

  int id;
  string cp = QUERY(argument_cache_dir), na = "args";
  if( QUERY(argument_cache_in_db) )
  {
    id = 1;
    cp = QUERY(argument_cache_db_path);
    na = "argumentcache";
  }
  mixed e;
  e = catch( argcache = ArgCache(na,cp,id) );
  if( e )
  {
    report_error( "Failed to initialize the global argument cache:\n"
                  + (describe_backtrace( e )/"\n")[0]+"\n");
    werror( describe_backtrace( e ) );
  }
  roxen_perror( "\n" );

  enable_configurations_modules();

  
// Rebuild the configuration interface tree if the interface was
// loaded before the configurations was enabled (a configuration is a
// virtual server, perhaps the name should be changed internally as
// well.. :-)
  if(root)
  {
    destruct(configuration_interface());
    configuration_interface()->build_root(root);
  }
  
  call_out(update_supports_from_roxen_com,
	   QUERY(next_supports_update)-time());
  
#ifdef THREADS
  start_handler_threads();
  catch( this_thread()->set_name("Backend") );
  backend_thread = this_thread();
#if efun(thread_set_concurrency)
  thread_set_concurrency(QUERY(numthreads)+1);
#endif

#endif /* THREADS */

  // Signals which cause a restart (exitcode != 0)
  foreach( ({ "SIGTERM" }), string sig) {
    catch { signal(signum(sig), exit_when_done); };
  }
  catch { signal(signum("SIGHUP"), reload_all_configurations); };
  // Signals which cause a shutdown (exitcode == 0)
  foreach( ({ "SIGINT" }), string sig) {
    catch { signal(signum(sig), shutdown); };
  }
  // Signals which cause Roxen to dump the thread state
  foreach( ({ "SIGUSR1", "SIGUSR2", "SIGTRAP" }), string sig) {
    catch { signal(signum(sig), describe_all_threads); };
  }

  report_notice(LOCALE->roxen_started(time()-start_time));
#ifdef __RUN_TRACE
  trace(1);
#endif
  start_time=time();		// Used by the "uptime" info later on.
  return -1;
}

string diagnose_error(array from)
{

}

// Called from the configuration interface.
string check_variable(string name, mixed value)
{
  switch(name)
  {
   case "ConfigPorts":
    config_ports_changed = 1;
    break;
   case "cachedir":
    if(!sscanf(value, "%*s/roxen_cache"))
    {
      // FIXME: LOCALE?
      object node;
      node = (configuration_interface()->root->descend("Globals", 1)->
	      descend("Proxy disk cache: Base Cache Dir", 1));
      if(node && !node->changed) node->change(1);
      mkdirhier(value+"roxen_cache/foo");
      call_out(set, 0, "cachedir", value+"roxen_cache/");
    }
    break;

   case "ConfigurationURL":
   case "MyWorldLocation":
    if(strlen(value)<7 || value[-1] != '/' ||
       !(sscanf(value,"%*s://%*s/")==2))
      return(LOCALE->url_format());
    break;

   case "abs_engage":
    if (value)
      restart_if_stuck(1);
    else 
      remove_call_out(restart_if_stuck);
    break;

   case "suicide_engage":
    if (value) 
      call_out(restart,60*60*24*QUERY(suicide_timeout));
    else
      remove_call_out(restart);
    break;
   case "locale":
     object o;
     if(value != "standard" && (o = Locale.Roxen[value]))
     {
       default_locale = o;
       SET_LOCALE(default_locale);
       if(root)
       {
//       destruct(root);
// 	 configuration_interface()->root = configuration_interface()->Node();
	 configuration_interface()->
	   build_root(configuration_interface()->root);
       }
     }
     break;
  }
}





mapping config_cache = ([ ]);
mapping host_accuracy_cache = ([]);
int is_ip(string s)
{
  return(replace(s,
		 ({ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "." }),
		 ({ "","","","","","","","","","","" })) == "");
}

object find_server_for(object id, string host, string|void port)
{
  object old_conf = id->conf;
  int portno = ((int)port);

#ifdef REQUEST_DEBUG
  werror(sprintf("ROXEN: find_server_for(%O, %O, %O)\n", id, host, port));
#endif /* REQUEST_DEBUG */

  if(portno!=0 && portno!=21 && portno!=80 && portno!=443)
    // Not likely to be anything else than the current virtual server.
    return id->conf;

  host = lower_case(host);
  if(config_cache[host]) {
    id->conf=config_cache[host];
  } else {
    if (is_ip(host)) {
      // Not likely to be anything else than the current virtual server.
      config_cache[host] = id->conf;
      return (id->conf);
    }

    int best;
    object c;
    string hn;
#if !constant(String.fuzzymatch) && constant(Array.diff_longest_sequence)
    array a = host/"";
#endif /* !String.fuzzymatch && Array.diff_longest_sequence */

    foreach(configurations, object s) {
      string h = lower_case(s->query("MyWorldLocation"));

      // Remove http:// et al here...
      // Would get interresting correlation problems with the "http" otherwise.
      int i = search(h, "://");
      if (i != -1) {
	h = h[i+3..];
      }
      if ((i = search(h, "/")) != -1) {
	h = h[..i-1];
      }

#if constant(String.fuzzymatch)
      int corr = String.fuzzymatch(host, h);
#elif constant(Array.diff_longest_sequence)
      int corr = sizeof(Array.diff_longest_sequence(a, h/""));
#endif /* constant(Array.diff_longest_sequence) */

      /* The idea of the algorithm is to find the server-url with the longest
       * common sequence of characters with the host-string, and among those
       * with the same correlation take the one which is shortest (ie least
       * amount to throw away).
       */
      if ((corr > best) ||
	  ((corr == best) && hn && (sizeof(hn) > sizeof(h)))) {
	/* Either better correlation,
	 * or the same, but a shorter hostname.
	 */
	best = corr;
	c = s;
	hn = h;
      }
    }

#if !constant(String.fuzzymatch) && constant(Array.diff_longest_sequence)
    // Minmatch should be counted in percent
    best=best*100/strlen(host);
#endif /* !String.fuzzymatch && Array.diff_longest_sequence */

    if(best >= 50 /* QUERY(minmatch) */)
      id->conf = config_cache[host] = (c || id->conf);
    else
      config_cache[host] = id->conf;
    host_accuracy_cache[host] = best;
  }

  if (id->conf != old_conf) 
  {
    /* Need to re-authenticate with the new server */

    if (id->rawauth) {
      array(string) y = id->rawauth / " ";

      id->realauth = 0;
      id->auth = 0;

      if (sizeof(y) >= 2) {
	y[1] = MIME.decode_base64(y[1]);
	id->realauth = y[1];
	if (id->conf && id->conf->auth_module) {
	  y = id->conf->auth_module->auth(y, id);
	}
	id->auth = y;
      }
    }
  }
  return id->conf;
}

object find_site_for( object id )
{
  if(id->misc->host) 
    return find_server_for(id,@lower_case(id->misc->host)/":");
  else
    return id->conf;
}
