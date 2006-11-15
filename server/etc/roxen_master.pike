object mm=(object)"/master";
inherit "/master": master;

mixed sql_query( string q, mixed ... e )
{
  return connect_to_my_mysql( 0, "local" )->query( q, @e );
}

/*
 * Roxen's customized master.
 */

constant cvs_version = "$Id: roxen_master.pike,v 1.144 2006/11/15 09:56:08 mast Exp $";

// Disable the precompiled file is out of date warning.
constant out_of_date_warning = 0;

#if !constant(PIKE_MODULE_RELOC)
#define relocate_module(x) (x)
#define unrelocate_module(x) (x)
#endif

#define SECURITY_DEBUG 1

#include <security.h>


#ifdef SECURITY
#if constant(thread_local)
static object chroot_dir = thread_local();
#else
static string chroot_dir = "";
#endif

static void low_set_chroot_dir( string to )
{
#if constant(thread_local)
  chroot_dir->set( to );
#else
  chroot_dir = to;
#endif
}

static string low_get_chroot_dir( )
{
#if constant(thread_local)
  return chroot_dir->get( );
#else
  return chroot_dir;
#endif
}

class ChrootKey( string old_dir )
{
  void destroy( )
  {
    low_set_chroot_dir( old_dir );
  }
}

ChrootKey chroot( string to )
{
  CHECK_SECURITY_BIT( SECURITY );
  ChrootKey key = ChrootKey( low_get_chroot_dir() );
  low_set_chroot_dir( to );
  return key;
}
  

class UID
{
  inherit Creds;

  static string _name;
  static string _rname;
  static int _uid, _gid;
  static int _data_bits, _allow_bits;
  static int io_bits = BIT_IO_CHROOT | BIT_IO_CAN_READ | BIT_IO_CAN_WRITE | BIT_IO_CAN_CREATE;
  static string always_chroot;
  
  constant modetobits = (["read":2, "write":4,   ]);

  UID set_io_bits( int to )
  {
    CHECK_SECURITY_BIT( SECURITY );
    io_bits = to;
    return this_object();
  }

  string chroot( string dir )
  {
    always_chroot = dir;
    if( dir )
      io_bits |= BIT_IO_CHROOT; // enforced chroot
    else
      io_bits &= BIT_IO_CHROOT; // enforced not chroot
  }
  
  int gid()   { return _gid; }
  int uid()   { return _uid; }

  /* Callback functions */
  int valid_open( string dir,
		  object current_object,
		  string file,
		  string mode,
		  int access )
  {
    string chroot_dir;
    file = combine_path( getcwd(), file );
#ifdef SECURITY_DEBUG
    werror("Security: valid_open( %O, %O, %o ) from %O\n", file, mode, access, current_object );
#endif
    if( (io_bits & BIT_IO_CHROOT) &&
	((chroot_dir=always_chroot) || (chroot_dir=low_get_chroot_dir()))
	&& search( file, chroot_dir ) )
    {
#ifdef SECURITY_DEBUG
      werror("Security error: Chroot set, but this file is not in it\n");
#endif
      return 3;
    }
    
    if( !(io_bits & modetobits[ dir ] ) )
    {
#ifdef SECURITY_DEBUG
      werror("Security error: Lacks bit for %O\n", dir );
#endif
      return 3;
    }

    mixed stat;

    if( !(io_bits & BIT_IO_CAN_CREATE) && !(stat = file_stat( file ) ) )
    {
#ifdef SECURITY_DEBUG
      werror("Security error: File does not exist, and user lacks permisson for create\n");
#endif
      return 0; // No such file
    }
    else  if( !stat )
      stat = file_stat( file );
#ifndef __NT__
    if( stat )
    {
      if( (io_bits & BIT_IO_ONLY_OWNED) && (stat->uid != _uid) )
      {
#ifdef SECURITY_DEBUG
	werror("Security error: ONLY_OWNED but file not owned\n");
#endif
	return 3;
      }
      if( (io_bits & BIT_IO_OWNED_AND_GROUP) && (stat->uid != _uid) && (stat->gid != _gid) )
      {
#ifdef SECURITY_DEBUG
	werror("Security error: ONLY_GROUP_AND_OWNED but file not owned/nor group\n");
#endif
	return 3;
      }
    }
    if( !(io_bits & BIT_IO_USER_OK) )
    {
      if( !stat )
      {
	dir = "create";
	stat = file_stat( dirname( file ) );
      }
      if(!stat)
      {
#ifdef SECURITY_DEBUG
	werror("Security error: File and directory both missing.\n");
#endif 
	return 2; // Not possible...
      }
      // check permission for the operation here, using more or less
      // normal unix semantics.
    }
#endif
#ifdef SECURITY_DEBUG
    werror("Security: Open of %O ok\n", file );
#endif 
    return 2;
  }

  int valid_io( string operation, string dir, mixed ... args )
  {
#ifdef SECURITY_DEBUG
    werror("valid_io( "+operation+", "+dir+" )\n" );
#endif
    if( !(io_bits & modetobits[ dir ] ) )
    {
#ifdef SECURITY_DEBUG
      werror("Security error: Lacks bit for %O\n", dir );
#endif
      return 0;
    }
    
//     switch( operation )
//     {
//       // ...
//     }
#ifdef SECURITY_DEBUG
    werror("Security: IO ok\n" );
#endif 
    return 2;
  }


  Creds own( mixed what, int|void bits )
  {
    Creds creds;
    if( !zero_type(bits) && (bits != get_data_bits()) )
      creds = Creds( this_object(), get_allow_bits(), bits );
    else
      creds = this_object();
    creds->apply( what );
    return creds;
  }

  mixed call( function what, mixed  ... args )
  {
    return call_with_creds( this_object(), what, @args );
  }

  mixed call_with_bits( function what, int bits, mixed ... args )
  {
    return call_with_creds( Creds( this_object(), bits, get_data_bits() ), what, @args );
  }

  Creds get_new_creds( int allow_bits, int data_bits )
  {
    return Creds( this_object(), allow_bits, data_bits );
  }
  
  void create( string name, string rname,
	       int uid, int gid, 
	       int allow_bits,
	       int data_bits )
  {
    _name = name;
    _rname = rname;
    _uid = uid;
    _gid = gid;
    ::create( this_object(), allow_bits, data_bits );
  }

  static string _sprintf( )
  {
    return sprintf("UID( %s (%s) )",_name,_rname);
  }
}

void init_security()
{
  werror("Initializing security system...");
  add_constant( "chroot", chroot );
  root->own( this_object() );
//   root->call(   Stdio.File, "/tmp/foo", "wct");
  werror("Done\n");
}

// There are three bit groups.
//   may_always bits
//   data bits        (overridden by may_always of current user)
//   io bits          (used in valid_io and valid_open)


// The root user can do everything. But objects owned by it cannot be
// destructed by anyone but the root user.
UID root   = UID( "root", "Supersture",0,0, ~0, ~BIT_DESTRUCT );


// The nobody user cannot do anything, basically (it can read/stat files, though)
UID nobody = UID( "nobody", "Nobody", 65535,65535,  BIT_CONDITIONAL_IO, ~0 )
             ->set_io_bits( BIT_IO_CHROOT | BIT_IO_CAN_READ );

// Default roxen user. Basically the same as the root user, but the IO bits apply.
// More specifically, the chroot() function works.
UID roxen = UID( "roxen", "Roxen internal user", getuid(), getgid(),
		 ~BIT_SECURITY, ~BIT_DESTRUCT );

// Like nobody, but cannot read files either.
UID luser = UID( "luser", "total luser", 65535, 65535, 0, 0 );
#else


void init_security()
{
  add_constant( "chroot", lambda(string new){ return class{}(); } );
}
#endif

mapping dump_constants = ([]), dump_constants_rev = ([]);

// These reverse mapping are not only for speed; we use mapping
// lookups to avoid calling the clever `== that objects might contain.
// E.g. Image.Color.black thinks it's equal to 0, which means that
// search (all_constants(), Image.Color.black) == "UNDEFINED".
static mapping(mixed:string) all_constants_rev = ([]);
static mapping(program:string) all_constants_object_program_rev = ([]);
static mapping(mixed:string) __builtin_rev =
  mkmapping (values (__builtin), indices (__builtin));
static mapping(mixed:string) _static_modules_rev =
  mkmapping (values (_static_modules), indices (_static_modules));

mixed add_dump_constant( string f, mixed what )
{
  if(!what) return 0;
  dump_constants_rev[ dump_constants[ f ] = what ] = f;
  catch(dump_constants_rev[ (program)what ] = f);
  return what;
}

void unregister(program p)
{
  m_delete (all_constants_object_program_rev, p);
  ::unregister (p);
}

#if defined (DUMP_DEBUG_LOG) && !defined (DUMP_DEBUG)
#define DUMP_DEBUG
#endif

#ifdef DUMP_DEBUG
int dump_debug_indent = 0;

#ifdef DUMP_DEBUG_LOG
#define DD_MSG(X...) werror (({X}) * "")
#else
#define DD_MSG(X...) log->add (X)
#endif

#define DUMP_DEBUG_ENTER(X...) do {					\
    DD_MSG ("  " * dump_debug_indent++, sprintf (X));			\
  } while (0)
#define DUMP_DEBUG_MSG(X...) do {					\
    DD_MSG ("  " * dump_debug_indent, sprintf (X));			\
  } while (0)
#define DUMP_DEBUG_RETURN(val) do {					\
    mixed _v__ = (val);							\
    DD_MSG ("  " * --dump_debug_indent,					\
	    "returned ",						\
	    zero_type (_v__) ? "UNDEFINED" : sprintf ("%O", _v__),	\
	    "\n");							\
    return _v__;							\
  } while (0)
#else
#define DUMP_DEBUG_ENTER(X...) do {} while (0)
#define DUMP_DEBUG_MSG(X...) do {} while (0)
#define DUMP_DEBUG_RETURN(val) do return (val); while (0)
#endif

class MyCodec
{
  program p;
#ifdef DUMP_DEBUG
  mixed last_failed;
  String.Buffer log = String.Buffer();
#endif

  static mapping(program:string) nameof_program_cache = ([]);
  static string nameof_program(program prog)
  {
    string res;
    DUMP_DEBUG_ENTER("nameof_program(%O)\n", prog);
    if (prog == p) DUMP_DEBUG_RETURN(UNDEFINED);
    if (res = nameof_program_cache[prog]) DUMP_DEBUG_RETURN(res);
    res = sprintf("%O", prog);
    if (prog == resolv(res)) {
      DUMP_DEBUG_RETURN("resolv:" + res);
    }
    if (res == "master().dirnode") error("Encoding dirnode program.\n");
#if constant(function_program)
    program parent = function_program(prog);
#else /* !constant(function_program) */
    object parent_obj = functionp(prog) && function_object(prog);
    program parent = parent_obj && object_program(parent_obj);
#endif /* constant(function_program) */
    DUMP_DEBUG_MSG("parent:%O\n", parent);
    if (parent && (parent != p)) {
      string name = function_name(prog);
      DUMP_DEBUG_MSG("name:%O\n", name);
      if (name) {
	if (res = all_constants_object_program_rev[parent]) {
	  res = "efun:" + res + "\0" + name;
	  nameof_program_cache[prog] = res;
	  DUMP_DEBUG_RETURN(res);
	}
	  
	if ((objects[parent]) && (res = nameof(objects[parent]))) {
	  res += "\0" + name;
	  nameof_program_cache[prog] = res;
	  DUMP_DEBUG_RETURN(res); 
	}
	
	if ((prog == parent[name]) && (res = nameof_program(parent))) {
	  if (programs[res]) {
	    res += "\0" + name;
	  } else {
	    res += "\0" + name;
	  }
	  nameof_program_cache[prog] = res;
	  DUMP_DEBUG_RETURN(res); 
	}
      }
    }
    if(string tmp = programs_reverse_lookup (prog)) {
      nameof_program_cache[prog] = tmp;
      DUMP_DEBUG_RETURN(tmp);
    }
    DUMP_DEBUG_RETURN(UNDEFINED);
  }

  string nameof(mixed x)
  {
#ifdef DUMP_DEBUG
#if __VERSION__ < 7.4
    if (objectp (x))
      DUMP_DEBUG_ENTER ("nameof (object %s: %O)\n",
			Program.defined (object_program (x)) || "?", x);
    else if (functionp (x))
      DUMP_DEBUG_ENTER ("nameof (function %s in object %s: %O)\n",
			Function.defined (x) || "?",
			function_object (x) &&
			Program.defined (object_program (function_object (x))) || "?",
			function_object (x));
    else if (programp (x))
      DUMP_DEBUG_ENTER ("nameof (program %s)\n",
			Program.defined (x) || "?");
    else
      DUMP_DEBUG_ENTER ("nameof (%O)\n", x);
#else /* __VERSION__ >= 7.4 */
    string type_str = "";
    if (objectp(x)) type_str="object ";
    else if (functionp(x)) type_str="function ";
    else if (programp(x)) type_str="program ";
    DUMP_DEBUG_ENTER("nameof (%s%O)\n", type_str, x);
#endif /* __VERSION__ < 7.4 */
#endif

    if(p!=x)
    {
      if( string n = dump_constants_rev[ x ] )
	DUMP_DEBUG_RETURN ("defun:"+n);

      if (sizeof (all_constants()) != sizeof (all_constants_rev)) {
	// We assume that all_constants() doesn't shrink.
	all_constants_rev =
	  mkmapping (values (all_constants()), indices (all_constants()));
	all_constants_object_program_rev = ([]);
	foreach(indices(all_constants()), string sym) {
	  mixed val = all_constants()[sym];
	  if (objectp(val)) {
	    all_constants_object_program_rev[object_program(val)] = sym;
	  }
	}
      }

      if (string name = all_constants_rev[x])
	DUMP_DEBUG_RETURN ("efun:" + name);
      if (string name = __builtin_rev[x])
	DUMP_DEBUG_RETURN ("resolv:__builtin." + name);
      if (string name = _static_modules_rev[x])
	DUMP_DEBUG_RETURN ("resolv:_static_modules." + name);

      if ( programp (x) )
      {
	mixed tmp;
	if (tmp = nameof_program(x)) {
	  DUMP_DEBUG_RETURN(tmp);
	}

	if( (program)x != x )
	  DUMP_DEBUG_RETURN (nameof( (program)x ));
#ifdef DUMP_DEBUG
	last_failed = x;
#endif
	DUMP_DEBUG_RETURN (([])[ 0 ]);
      }
    }

    if (objectp (x)) 
    {
      array(string) ids = ({});
      if(x->is_resolv_dirnode)
      {
        /* FIXME: this is a bit ad-hoc */
        string dirname=x->dirname;
        dirname-=".pmod";
        sscanf(dirname,"%*smodules/%s",dirname);
        dirname=replace(dirname,"/",".");
        if(resolv(dirname) == x)
	  DUMP_DEBUG_RETURN ("resolv:"+dirname);
      }

      while (1)
      {
	if(program p = objects_reverse_lookup (x))
	{
	  if(string pname = programs_reverse_lookup (p))
	  {
	    if (sizeof (ids)) DUMP_DEBUG_RETURN (pname + "\0" + ids * "\0");
	    else DUMP_DEBUG_RETURN (pname);
	  }
	}

	object parent;
	if (!catch (parent = function_object (object_program (x))) && parent) {
	  mapping(mixed:string) rev = mkmapping (values (parent), indices (parent));
	  // Use a mapping since objects with tricky `== can fool
	  // search(). (Objects with tricky __hash are a bit more
	  // uncommon and less prone to consider the object to be
	  // equal to a string or an integer or whatnot.)
	  if (string id = rev[x]) {
	    x = parent;
	    ids = ({id}) + ids;
	    continue;
	  }
	}
	break;
      }

      if( x == mm )
	DUMP_DEBUG_RETURN ("/master");
    }
#ifdef DUMP_DEBUG
    last_failed = x;
#endif
    DUMP_DEBUG_RETURN (([])[0]);
  }

  static mixed low_lookup(string x, void|int is_prog)
  {
    array(string) segments = x/"\0";
    string s;
    mixed part = UNDEFINED;
    x = segments[0];
    if (sscanf(x,"defun:%s",s)) {
      part = dump_constants[s];
    }
    else if (sscanf(x,"efun:%s",s)) {
      part = all_constants()[s];
    }
    else if (sscanf(x,"resolv:%s",s)) {
      part = resolv(s);
    }
    else {
      if (is_prog && sizeof(segments) == 1) {
	part = (program)x;
      } else {
	part = (object)x;
      }
    }
    foreach(segments[1..], string id) {
      if (zero_type(part = part[id]))
	error("Failed to decode symbol %O\n", segments * "\0" );
    }
    return part||UNDEFINED;
  }

  function functionof(string x)
  {
    DUMP_DEBUG_ENTER ("functionof (%O)\n", x);
    mixed res = low_lookup(x);
    if (functionp(res)) DUMP_DEBUG_RETURN(res);
    error("Failed to decode function %s:%O\n", x, res);
  }

  object objectof(string x)
  {
    DUMP_DEBUG_ENTER ("objectof (%O)\n", x);
    mixed res = low_lookup(x);
    if (objectp(res)) DUMP_DEBUG_RETURN(res);
    error("Failed to decode object %s:%O\n", x, res );
  }

  program programof(string x)
  {
    DUMP_DEBUG_ENTER ("programof (%O)\n", x);
    mixed res = low_lookup(x, 1);
    if (programp(res) || objectp(res)) DUMP_DEBUG_RETURN(res);
    error("Failed to decode program %s:%O\n", x, res );
  }

  mixed encode_object(object x)
  {
    DUMP_DEBUG_ENTER ("encode_object (%s)\n",
		      objectp (x) ?
		      "object " + Program.defined (object_program (x)) :
		      sprintf ("%O", x));
    if(x->_encode) DUMP_DEBUG_RETURN (x->_encode());
    error("Cannot encode objects without _encode.\n");
  }

  void decode_object(object x, mixed data)
  {
    DUMP_DEBUG_MSG ("decode_object (%s, %O)\n",
		    objectp (x) ?
		    "object " + Program.defined (object_program (x)) :
		    sprintf ("%O", x),
		    data);
    if( x->_decode )
      x->_decode(data);
    else
      error("Cannot decode objects without _decode.\n");
  }

  void create( program|void q )
  {
    p = q;
  }
}


#ifdef __NT__
string getcwd()
{
  return replace (::getcwd(), "\\", "/");
}
#endif

mapping handled = ([]);

mapping(program:string) program_names = set_weak_flag (([]), 1);

string make_ofilename( string from )
{
  return sprintf( "%s-%x",
                  ((from/"/")[-1]/".")[0],hash(from));
}

void dump_program( string pname, program what )
{
  string index = make_ofilename( pname );
  string data;
#ifdef DUMP_DEBUG
  MyCodec cd;
  int test_decode = 0;
  int save_dump_debug_indent = dump_debug_indent;
  dump_debug_indent = 0;
  mixed err;
  if (!(err = catch (data = encode_value( what, (cd = MyCodec( what )) ) )) &&
      !(cd->log->add ("****** Encode ok, testing decode:\n"),
	test_decode = 1,
	err = catch (decode_value (data, cd))))
#else
  data = encode_value( what, MyCodec( what ) );
#endif
  {
    sql_query( "DELETE FROM precompiled_files WHERE id=%s",index );
    sql_query( "INSERT INTO precompiled_files values (%s,%s,%d)",
	       index, data, time(1) );
#ifdef DUMP_DEBUG
    werror ("Stored in sql with timestamp %d: %O\n", time(1), index);
#endif
  }
#ifdef DUMP_DEBUG
  else
  {
    array parts = pname / "/";
    if (sizeof(parts) > 3) parts = parts[sizeof(parts)-3..];
    if (test_decode)
      werror ("Couldn't decode dump of " + parts * "/" + " \n");
    else
      werror("Couldn't dump " + parts * "/" + "\n");
    werror("Codec log:\n%s", cd->log->get());
    werror("Last recursively encoded: %O\n", cd->last_failed );
    mixed w = Describer()->describe( cd->last_failed,10000 );
    if( w == "program" ) w = _typeof( cd->last_failed );
    werror( "  Type: %O\n",w);
    werror("Error: %s", describe_backtrace(err));
    werror("\n");
  }
  dump_debug_indent = save_dump_debug_indent;
#endif
}

int loaded_at( program p )
{
  return load_time[ program_name (p) ];
}

// array(string) query_precompiled_names(string fname)
// {
//   return ({ make_ofilename(fname) }) + ::query_precompiled_names(fname);
// }

#if constant(_static_modules.Builtin.mutex)
#define THREADED
// NOTE: compilation_mutex is inherited from the original master.
#endif

mapping(string:function|int) has_set_on_load = ([]);
void set_on_load( string f, function cb )
{
  has_set_on_load[ f ] = cb;
}

program low_findprog(string pname, string ext,
		     object|void handler, void|int mkobj)
{
  program ret;
  Stat s;
  string fname=pname+ext;

#ifdef THREADED
  object key;
  // FIXME: The catch is needed, since we might be called in
  // a context when threads are disabled.
  // (compile() disables threads).
  catch {
    key=compilation_mutex->lock(2);
  };
#endif

#if constant(PIKE_MODULE_RELOC)
  fname = unrelocate_module(fname);
#endif

#if 0
  // No idea what this is supposed to accomplish, but the effect is
  // that the ErrorContainer can be stored as handler in dirnodes and
  // receive error messages long after the function that installed it
  // have checked for error messages and forgotten about it. /mast
  if( !handler ) handler = get_inhibit_compile_errors();
#endif

  if( (s=master_file_stat( relocate_module(fname) )) && s[1]>=0 )
  {
    if( load_time[ fname ] >= s[ 3 ] )
      if( !zero_type (ret = programs[fname]) )
        return ret;

    switch(ext)
    {
    case "":
    case ".pike":
      // First check in mysql.
      array q;

#ifdef DUMP_DEBUG
#define DUMP_WARNING(fname,err)                                         \
          werror("Failed to decode dumped file for %s: %s",             \
                 trim_file_name (fname), describe_error(err));
#define DDEBUG( X... ) werror( X )
#else
#define DUMP_WARNING(f,e)
#define DDEBUG( X... )
#endif

#define LOAD_DATA( DATA )                                                    \
      do {                                                                   \
        mixed err = catch                                                    \
        {                                                                    \
          load_time[ fname ] = s[3];					     \
          programs[ fname ] = 0;                                             \
          ret = programs[ fname ] = decode_value( DATA, MyCodec() );         \
          program_names[ ret ] = fname;                                      \
          m_delete(has_set_on_load, fname );                                 \
          return ret;                                                        \
        }; DUMP_WARNING(fname,err)                                           \
      } while(0)
#define LOAD_OFILE( DATA )                                                    \
      do {                                                                   \
        mixed err = catch                                                    \
        {                                                                    \
          load_time[ fname ] = s[3];                                         \
          programs[ fname ] = 0;                                             \
          ret = programs[ fname ] = decode_value( DATA, Codec() );	     \
          program_names[ ret ] = fname;                                      \
          m_delete(has_set_on_load, fname );                                 \
          return ret;                                                        \
        }; DUMP_WARNING(fname,err)                                           \
      } while(0)
      if(sizeof(q=sql_query( "SELECT data,mtime FROM precompiled_files WHERE id=%s",
			     make_ofilename( fname )))) {
	if( (int)q[0]->mtime >= s[3] ) {
	  DDEBUG ("Loading dump from sql: %O\n", make_ofilename( fname ));
	  LOAD_DATA( q[0]->data );
	}
	else
	  DDEBUG ("Ignored stale dump in sql, timestamp %d vs %d: %O\n",
		  (int)q[0]->mtime, s[3], make_ofilename( fname ));
      }

      foreach(query_precompiled_names(fname), string ofile )
        if(Stat s2=master_file_stat( ofile ))
          if(s2[1]>0 && s2[3]>=s[3])
            LOAD_OFILE( Stdio.File( ofile,"r")->read() );

      DDEBUG( "Really compile: %O\n", fname );
#ifdef DUMP_DEBUG
      int t = gethrtime();
#endif
      load_time[fname] = s[3];
#if constant (__empty_program)
      programs[fname]=ret=__empty_program(0, fname);
#endif
      if ( mixed e=catch {
	  ret=compile_file(fname, handler,
#if constant (__empty_program)
			   ret, mkobj ? (objects[ret] = __null_program()) : 0
#endif
			  );
	} )
      {
	// load_time[fname] = s[3]; not here, no.... reload breaks miserably
	//
	// Yes indeed here. How else avoid many many recompilations of
	// a module that's broken and referenced from a gazillion
	// places? This also avoids the dreaded infinite loop during
	// compilation that could occur with misspelled identifiers in
	// pike modules. /mast
	ret=programs[fname]=0;
        if(arrayp(e) && sizeof(e) &&
	   (<"Compilation failed.\n", "Cpp() failed\n">)[e[0]])
          e[1]=({});
	DDEBUG( "Compile FAILED: %O\n",fname );
	throw(e);
      }
      DDEBUG( "Compile took %dms: %O\n", (gethrtime()-t)/1000, fname );
      function f;
      if( functionp( f = has_set_on_load[ fname ] ) )
      {
        has_set_on_load[ fname ] = 1;
	call_out(f,0.1,fname, ret );
      }
      else
        has_set_on_load[ fname ] = 1;
      break;
#if constant(load_module)
    case ".so":
      ret=load_module(relocate_module(fname));
#endif
    }
    program_names[ret] = fname;
    if( !ret ) m_delete (load_time, fname);
    return programs[fname] = ret;
  }
  return 0;
}

program handle_inherit (string pname, string current_file, object|void handler)
{
  if (has_prefix (pname, "roxen-module://")) {
    pname = pname[sizeof ("roxen-module://")..];
    if (object modinfo = roxenp()->find_module (pname))
      if (program ret = cast_to_program (modinfo->filename, current_file, handler))
	return ret;
    return 0;
  }
  return ::handle_inherit (pname, current_file, handler);
}

void handle_error(array(mixed)|object trace)
{
  catch {
    if (arrayp (trace) && sizeof (trace) == 2 &&
	arrayp (trace[1]) && !sizeof (trace[1]))
      // Don't report the special compilation errors thrown above. Pike
      // calls this if resolv() or similar throws.
      return;
  };
  ::handle_error (trace);
}

void clear_compilation_failures()
{
  foreach (indices (programs), string fname)
    if (!programs[fname]) m_delete (programs, fname);
}

int refresh( program p, int|void force )
{
  string fname = program_name( p );
  if(!fname)
  {
    return 1; /*  Not loaded.. */
  }

  if( force )
  {
    m_delete( programs, fname );
    m_delete( load_time, fname );
    sql_query( "DELETE FROM precompiled_files WHERE id=%s",
	       make_ofilename(fname) );
    return 1;
  }

  Stat s=master_file_stat( fname );

  if( s && s[1]>=0 )
  {
    if( load_time[ fname ] >= s[ 3 ] )
      return 0;
  }
  else
    return -1; /* No such file... */

  m_delete( programs, fname );
  m_delete( load_time, fname );
  sql_query( "DELETE FROM precompiled_files WHERE id=%s",
	     make_ofilename(fname));
  return 1;
}

int recursively_check_inherit_time(program root, array up, mapping done)
{
  catch
  {
    int res;
    if( done[ root ]++ )
      return 0;

    foreach( Program.inherit_list( root ), program p )
      res+=recursively_check_inherit_time( p, up+({root}), done );

    if( !res && (refresh( root )>0 ))
    {
      res++;
      map( up+({root}), refresh, 1 );
    }

    return res;
  };
}

int refresh_inherit( program what )
{
  int ret = recursively_check_inherit_time( what, ({}), ([]) );;
  return ret;
}


string program_name(program p)
{
  return program_names[p];
}

void name_program( program p, string name )
{
  if (programs[name]) {
    if (programs[name] == p) return;
    if (rev_programs && (rev_programs[programs[name]] == name)) {
      m_delete(rev_programs, programs[name]);
    }
    m_delete(programs, name);
  }
  string t = programs_reverse_lookup(p);
  load_time[name] = t?load_time[t]:time(1);
  programs[name] = p;
}

class Describer
{
  inherit master::Describer;

  string describe_string (string m, int maxlen)
  {
    canclip++;
    if(sizeof(m) < 40)
      return  sprintf("%O", m);;
    clipped++;
    return sprintf("%O+[%d]+%O",m[..15],sizeof(m)-(32),m[sizeof(m)-16..]);
  }

  string describe_array (array m, int maxlen)
  {
    if(!sizeof(m)) return "({})";
    return "({" + describe_comma_list(m,maxlen-2) +"})";
  }
}

constant bt_max_string_len = 99999999;
int long_file_names;

string describe_backtrace(mixed trace, void|int linewidth)
{
  return predef::describe_backtrace(trace, 999999);
}


void create()
{
  object o = this_object();
  /* Copy variables from the original master */
  foreach(indices(mm), string varname) {
    catch(o[varname] = mm[varname]);
    /* Ignore errors when copying functions */
  }

  init_security();
    
  foreach( indices(programs), string f )
    load_time[f] = load_time[f] || time(1);

  programs["/master"] = object_program(o);
  program_names[object_program(o)] = "/master";
  objects[ object_program(o) ] = o;
  /* Move the old efuns to the new object. */

  add_constant("add_dump_constant", add_dump_constant);
  foreach(master_efuns, string e)
    add_constant(e, o[e]);
}
