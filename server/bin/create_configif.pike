/*
 * $Id: create_configif.pike,v 1.38 2002/03/20 12:54:38 grubba Exp $
 *
 * Create an initial administration interface server.
 */

int mkdirhier(string from)
{
  string a, b;
  array f;

  f=(from/"/");
  b="";

  foreach(f[0..sizeof(f)-2], a)
  {
    mkdir(b+a);
    b+=a+"/";
  }
}

class Readline
{
  inherit Stdio.Readline;

  void trap_signal(int n)
  {
    werror("Interrupted, exit.\r\n");
    destruct(this_object());
    exit(1);
  }

  void destroy()
  {
    get_input_controller()->dumb = 0;
    ::destroy();
    signal(signum("SIGINT"));
  }

    private string safe_value(string r)
    {
	if(!r)
	{
	    /* C-d? */
	    werror("\nTerminal closed, exit.\n");
	    destruct(this_object());
	    exit(1);
	}
	
	return r;
    }
    
  string read(mixed ... args)
  {
    return safe_value(::read(@args));
  }

  string edit(mixed ... args)
  {
    return safe_value(::edit(@args));
  }
  
  void create(mixed ... args)
  {
    signal(signum("SIGINT"), trap_signal);
    ::create(@args);
  }
}

string read_string(Readline rl, string prompt, string|void def,
		   string|void batch)
{
  string res = batch || rl->edit(def || "", prompt+" ", ({ "bold" }));
  if( def && !strlen(res-" ") )
    res = def;
  return res;
}

int main(int argc, array argv)
{
  Readline rl = Readline();
  string name, user, password, configdir, port;
  string passwd2;
  mapping(string:string) batch = ([]);

#if constant( SSL )
  string def_port = "https://*:"+(random(20000)+10000)+"/";
#else
  string def_port = "http://*:"+(random(20000)+10000)+"/";
#endif

  //werror("Argv: ({%{%O, %}})\n", argv);

  if(has_value(argv, "--help")) {
    write(#"
Creates and initializes a Roxen WebServer configuration
interface. Arguments:

 -d dir   The location of the configuration interface.
          Defaults to \"../configurations\".
 -a       Only create a new administration user.
          Useful when the administration password is
          lost.
 --help   Displays this text.
 --batch  Create a configuration interface in batch mode.
          The --batch argument should be followed by a
          list of value pairs, each pair representing the
          name of a question field and the value to be
          filled into it. Available fields:
      server_name    The name of the server. Defaults to
                     \"Administration Interface\".
      server_url     The server url, e.g.
                     \"http://*:1234/\".
      user           The name of the administrator.
                     Defaults to \"administrator\".
      password       The administrator password.
      ok             Disable user confirmation of the
                     above information with the value
                     pair \"ok y\".
      update         Enable update system (y/n).
      community_user The name of the community user that
                     should be used when downloading
                     updates.
      community_password  The password for the above
                     community user.
      community_proxy  Use proxy when connecting to the
                     community site.
      proxy_host     The proxy host.
      proxy_port     The proxy port.

Example of a batch installation:

 ./create_configinterface --help server_name Admin server_url
 http://*:8080/ ok y user admin update n

");
    return 0;
  }

  configdir =
   Getopt.find_option(argv, "d",({"config-dir","configuration-directory" }),
  	              ({ "ROXEN_CONFIGDIR", "CONFIGURATIONS" }),
                      "../configurations");
  int admin = has_value(argv, "-a");

//    werror("Admin mode: %O\n"
//  	 "Argv: ({%{%O, %}})\n", admin, argv);

  int batch_args = search(argv, "--batch");
  if(batch_args>=0)
    batch = mkmapping(@Array.transpose(argv[batch_args+1..]/2));

  foreach( get_dir( configdir )||({}), string cf )
    catch 
    {
      if( cf[-1]!='~' &&
	  search( Stdio.read_file( configdir+"/"+cf ), 
                  "'config_filesystem#0'" ) != -1 )
      {
	string server_version = Stdio.read_file("VERSION");
	if(server_version)
	  Stdio.write_file(configdir+"/server_version","server-"+server_version);
        werror("   There is already an administration interface present in "
               "this\n   server. A new one will not be created.\n");
        if(!admin++) exit( 0 );
      }
    };
  if(admin==1)
    werror("   No administration interface was found. A new one will be created.\n");
  if(configdir[-1] != '/')
    configdir+="/";
  if(admin)
    write( "   Creating an administrator user.\n\n" );
  else
    write( "   Creating an administration interface server in\n"+
	   "   "+combine_path(getcwd(), configdir)+".\n");

  do
  {
    password = passwd2 = 0;
    
    if(!admin) 
    {
      write("\n");
      name = read_string(rl, "Server name:", "Administration Interface",
			 batch->server_name);

      int port_ok;
      while( !port_ok )
      {
        string protocol, host, path;

        port = read_string(rl, "Port URL:", def_port, batch->server_url);
	m_delete(batch, "server_url");
        if( port == def_port )
          ;
        else if( (int)port )
        {
          int ok;
          while( !ok )
          {
            switch( protocol = lower_case(read_string(rl, "Protocol:", "http")))
            {
             case "":
               protocol = "http";
             case "http":
             case "https":
               port = protocol+"://*:"+port+"/";
               ok=1;
               break;
             default:
               write("\n   Only http and https are supported for the "
                     "configuration interface.\n");
               break;
            }
          }
        }

        if( sscanf( port, "%[^:]://%[^/]%s", protocol, host, path ) == 3)
        {
          if( path == "" )
            path = "/";
          switch( lower_case(protocol) )
          {
           case "http":
           case "https":
             // Verify hostname here...
             port = lower_case( protocol )+"://"+host+path;
             port_ok = 1;
             break;
           default:
             write("\n   Only http and https are supported for the "
                   "configuration interface.\n\n");
             break;
          }
        }
      }
    }

    do
    {
      user = read_string(rl, "Administrator user name:", "administrator",
			 batch->user);
      m_delete(batch, "user");
    } while(((search(user, "/") != -1) || (search(user, "\\") != -1)) &&
            write("User name may not contain slashes.\n"));

    do
    {
      if(passwd2 && password)
	write("\n   Please select a password with one or more characters. "
	      "You will\n   be asked to type the password twice for "
	      "verification.\n\n");
      rl->get_input_controller()->dumb=1;
      password = read_string(rl, "Administrator password:", 0, batch->password);
      passwd2 = read_string(rl, "Administrator password (again):", 0, batch->password);
      rl->get_input_controller()->dumb=0;
      if(batch->password)
	m_delete(batch, "password");
      else
	write("\n");
    } while(!strlen(password) || (password != passwd2));
    write("\n");
  } while( strlen( passwd2 = read_string(rl, "Are the settings above correct [Y/n]?", "", batch->ok ) ) && passwd2[0]=='n' );

  if( !admin )
  {
    string community_user, community_password, proxy_host="", proxy_port="80";
    string community_userpassword="";
    int use_update_system=0;
  
    if(!batch->update) {
      write("\n   Roxen has a built-in update system. If enabled it will periodically\n");
      write("   contact update servers at Roxen Internet Software over the Internet.\n\n");
    }
    if(!(strlen( passwd2 = read_string(rl, "Do you want to enable this [Y/n]?", "", batch->update ) ) && passwd2[0]=='n' ))
    {
      use_update_system=1;
      if(!batch->community_user) {
	write("\n   If you have a registered user identity at Roxen Community\n");
	write("   (http://community.roxen.com), you may be able to access additional\n");
	write("   material through the update system.\n\n");
	write("   Press enter to skip this.\n\n");
      }
      community_user=read_string(rl, "Roxen Community identity (your e-mail):",
				 0, batch->community_user);
      if(sizeof(community_user))
      {
        do
        {
	  if(passwd2 && community_password)
	    write("\n   Please type a password with one or more characters. "
		  "You will\n   be asked to type the password twice for "
		  "verification.\n\n");
          rl->get_input_controller()->dumb=1;
          community_password = read_string(rl, "Roxen Community password:", 0,
					   batch->community_password);
          passwd2 = read_string(rl, "Roxen Community password (again):", 0,
				batch->community_password);
          rl->get_input_controller()->dumb=0;
	  if(batch->community_password)
	    m_delete(batch, "community_password");
	  else
	    write("\n");
          community_userpassword=community_user+":"+community_password;
        } while(!strlen(community_password) || (community_password != passwd2));
      }
      
      if((strlen( passwd2 = read_string(rl, "Do you want to access the update "
					"server through an HTTP proxy [y/N]?",
					"", batch->community_proxy))
	  && lower_case(passwd2[0..0])!="n" ))
      {
	proxy_host=read_string(rl, "Proxy host:", 0, batch->proxy_host);
	if(sizeof(proxy_host))
	  proxy_port=read_string(rl, "Proxy port:", "80", batch->proxy_port);
	if(!sizeof(proxy_port))
	  proxy_port="80";
      }
    }
    mkdirhier( configdir );
    string server_version = Stdio.read_file("VERSION");
    if(server_version)
      Stdio.write_file(configdir+"/server_version", "server-"+server_version);
    Stdio.write_file( configdir+replace( name, " ", "_" ),
                      replace(
#"
<!-- -*- html -*- -->
<?XML version=\"1.0\"?>

<region name='EnabledModules'>
  <var name='config_filesystem#0'> <int>1</int>  </var> <!-- Configration Filesystem -->
</region>

<region name='pikescript#0'>
  <var name='trusted'><int>1</int></var>
</region>

<region name='graphic_text#0'>
  <var name='colorparse'>        <int>1</int> </var>
</region>

<region name='update#0'>
  <var name='do_external_updates'> <int>$USE_UPDATE_SYSTEM$</int> </var>
  <var name='proxyport'>         <int>$PROXY_PORT$</int> </var>
  <var name='proxyserver'>       <str>$PROXY_HOST</str> </var>
  <var name='userpassword'>      <str>$COMMUNITY_USERPASSWORD$</str> </var>
</region>

<region name='contenttypes#0'>
  <var name='_priority'>         <int>0</int> </var>
  <var name='default'>           <str>application/octet-stream</str> </var>
  <var name='exts'><str># This will include the defaults from a file.
# Feel free to add to this, but do it after the #include line if
# you want to override any defaults

#include %3cetc/extensions%3e
tag text/html
xml text/html
rad text/html
ent text/html

</str></var>
</region>

<region name='spider#0'>
  <var name='Domain'> <str></str> </var>
  <var name='MyWorldLocation'><str></str></var>
  <var name='URLs'> <a> <str>$URL$#ip=;nobind=0;</str></a> </var>

  <var name='comment'>
    <str>Automatically created by create_configuration</str>
  </var>

  <var name='name'>
    <str>$NAME$</str>
  </var>
</region>",
 ({ "$NAME$", "$URL$", "$USE_UPDATE_SYSTEM$","$PROXY_PORT$",
    "$PROXY_HOST", "$COMMUNITY_USERPASSWORD$" }),
 ({ name, port, (string)use_update_system, proxy_port,
    proxy_host, community_userpassword }) ));
    write("\n   Administration interface created.\n");
  }

  string ufile=(configdir+"_configinterface/settings/" + user + "_uid");
  mkdirhier( ufile );
  Stdio.File( ufile, "wct", 0770 )
    ->write(
string_to_utf8(#"<?XML version=\"1.0\"  encoding=\"UTF-8\"?>
<map>
  <str>permissions</str> : <a> <str>Everything</str> </a>
  <str>real_name</str>   : <str>Administration Interface Default User</str>
  <str>password</str>    : <str>" + crypt(password) + #"</str>
  <str>name</str>        : <str>" + user + "</str>\n</map>" ));

  write("\n   Administrator user \"" + user + "\" created.\n");
}
