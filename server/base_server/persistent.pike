// static private inherit "db";

/* $Id: persistent.pike,v 1.25 1997/04/26 03:34:53 per Exp $ */

/*************************************************************,
* PERSIST. An implementation of persistant objects for Pike.  *
* Variables and callouts are saved between restarts.          *
*                                                             *
* What is not saved?                                          *
* o Listening info (files.port)                               *
* o Open files (files.file)                                   *
*                                                             *
* This can be solved by specifying two new objects, like      *
* persists/port and persist/file in Pike. I leave that as an  *
* exercise for the reader.. :-)                               *
*                                                             *
* (remember to save info about seek etc.. But it is possible) *
'*************************************************************/

#define PRIVATE private static inline 

static void _nosave(){}
static function nosave = _nosave;
private static array __id;

void really_save()
{
  if(nosave()) return;
  perror("really save ("+(__id*":")+")!\n");

  object file = files.file();
  array res = ({ });
  mixed b;

  if(!__id)
  {
    mixed i = nameof(this_object());
    if(!arrayp(i)) __id=({i});
    else __id = i;
  }

  foreach(persistent_variables(object_program(this_object()), this_object()),
	  string a)
    res += ({ ({ a, this_object()[a] }) });

  open_db(__id[0])->set(__id[1], encode_value(res) );
}


/* Public methods! */
static int ___destructed = 0;

public void begone()
{
  remove_call_out(really_save);
  ___destructed=1;
  if(__id) open_db(__id[0])->delete(__id[1]);
  __id=0;
// A nicer destruct. Won't error() if no object.
  call_out(do_destruct,8,this_object());
}

void destroy()
{
  remove_call_out(really_save);
}

static void compat_persist()
{
  string _id;
  _id=(__id[0]+".class/"+__id[1]);

#define COMPAT_DIR "dbm_dir.perdbm/"
  object file = files.file();
  array var;
  mixed tmp;
  catch
  {
    if(!file->open(COMPAT_DIR+_id, "r")) return 0;
    perror("compat restore ("+ _id +")\n");
    var=decode_value(tmp=file->read(0x7ffffff));
  };

  if(var)
  {
    foreach(var, var) catch {
      this_object()[var[0]] = var[1];
    };
    if(!__id)
    {
      mixed i = nameof(this_object());
      if(!arrayp(i)) __id=({i});
      else __id = i;
    }
    
    open_db(__id[0])->set(__id[1], tmp );
    rm(COMPAT_DIR+_id);
  }
}

nomask public void persist(mixed id)
{
  object file = files.file();
  array err;
  /* No known id. This should not really happend. */
  if(!id)  error("No known id in persist.\n");
  __id = id;

// Restore
  array var;
  err = catch {
    var=decode_value(open_db(__id[0])->get(__id[1]));
    perror("decode_value ok\n");
  };
  if(err)
    report_error("Failed to restore +"(__id*":")+": "+describe_backtrace(err));
  
  if(var && sizeof(var))
  {
    foreach(var, var) if(err=catch {
      this_object()[var[0]] = var[1];
    })
      report_error(" When setting +"(var[0])+" in "+(__id*":")+": "+
		   describe_backtrace(err));
  } else
    compat_persist();

  if(functionp(this_object()->persisted))
    this_object()->persisted();
}
  

public void save()
{
  if(!___destructed)
  {
    remove_call_out(really_save);
    if(this_object()->nosave && this_object()->nosave()) return;
    call_out(really_save,60);
  }
}
