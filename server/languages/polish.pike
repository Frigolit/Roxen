/* Bugs by: Mak */
#charset iso-8859-2
constant required_charset = "iso-8859-2";
/*
 * name = "Polish language plugin ";
 * doc = "Handles the conversion of numbers and dates to polish. You have to restart the server for updates to take effect.";
 *
 * Piotr Klaban <makler@man.torun.pl>
 *
 * Character encoding: ISO-8859-2
 */

inherit "abstract.pike";

constant cvs_version = "$Id: polish.pike,v 1.6 2000/07/11 10:55:01 grubba Exp $";
constant _id = ({ "pl", "polish", "" });
constant _aliases = ({ "pl", "po", "pol", "polish" });

constant months = ({
  "Stycze�", "Luty", "Marzec", "Kwiecie�", "Maj",
  "Czerwiec", "Lipiec", "Sierpie�", "Wrzesie�", "Pa�dziernik",
  "Listopad", "Grudzie�" });

constant days = ({
  "Niedziela","Poniedzia�ek","Wtorek","�roda",
  "Czwartek","Pi�tek","Sobota" });

string ordered(int i)
{
  switch(i)
  {
   case 0:
    return "b��d";
   default:
    return i+".";
  }
}

string date(int timestamp, mapping|void m)
{
  mapping t1=localtime(timestamp);
  mapping t2=localtime(time(0));

  if(!m) m=([]);

  if(!(m["full"] || m["date"] || m["time"]))
  {
    if(t1["yday"] == t2["yday"] && t1["year"] == t2["year"])
      return "dzi�, "+ ctime(timestamp)[11..15];

    if(t1["yday"]+1 == t2["yday"] && t1["year"] == t2["year"])
      return "wczoraj, "+ ctime(timestamp)[11..15];

    if(t1["yday"]-1 == t2["yday"] && t1["year"] == t2["year"])
      return "jutro, "+ ctime(timestamp)[11..15];

    if(t1["year"] != t2["year"])
      return (month(t1["mon"]+1) + " " + (t1["year"]+1900));
    return (ordered(t1["mday"]) + " " + month(t1["mon"]+1));
  }
  if(m["full"])
    return ctime(timestamp)[11..15]+", "+
	   ordered(t1["mday"]) + " " +
           month(t1["mon"]+1) + " " +
           (t2["year"]+1900);
  if(m["date"])
    return (ordered(t1["mday"]) + " " + month(t1["mon"]+1) + " " +
       (t2["year"]+1900));
  if(m["time"])
    return ctime(timestamp)[11..15];
}


string number(int num)
{
  int tmp;

  if(num<0)
    return "minus "+number(-num);
  switch(num)
  {
   case 0:  return "";
   case 1:  return "jeden";
   case 2:  return "dwa";
   case 3:  return "trzy";
   case 4:  return "cztery";
   case 5:  return "pi��";
   case 6:  return "sze��";
   case 7:  return "siedem";
   case 8:  return "osiem";
   case 9:  return "dziewi��";
   case 10: return "dziesi��";
   case 11: return "jedena�cie";
   case 12: return "dwana�cie";
   case 13: return "trzyna�cie";
   case 14: return "czterna�cie";
   case 15: return "pi�tna�cie";
   case 16: return "szesna�cie";
   case 17: return "siedemna�cie";
   case 18: return "osiemna�cie";
   case 19: return "dziewi�tna�cie";
   case 20: return "dwadzie�cia";
   case 30: return "trzydzie�ci";
   case 40: return "czterdzie�ci";
   case 60: case 70: case 80: case 90:
     return number(num/10)+"dziesi�t";
   case 21..29: case 31..39:
   case 51..59: case 61..69: case 71..79:
   case 81..89: case 91..99: case 41..49:
     return number((num/10)*10)+" "+number(num%10);
   case 100: return "sto";
   case 200: return "dwie�cie";
   case 300: return "trzysta";
   case 400: return "czterysta";
   case 500: case 600: case 700: case 800: case 900:
     return number(num/100)+"set";
   case 101..199: case 201..299: case 301..399: case 401..499:
   case 501..599: case 601..699: case 701..799: case 801..899:
   case 901..999:
     return number(num-(num%100))+" "+number(num%100);
   case 1000..1999: return "tysi�c "+number(num%1000);
   case 2000..4999: return number(num/1000)+" tysi�ce "+number(num%1000);
   case 5000..999999: return number(num/1000)+" tysi�cy "+number(num%1000);
   case 1000001..1999999:
     return number(num/1000000)+" milion "+number(num%1000000);
   case 2000000..999999999:
     tmp = (num/1000000) - ((num/10000000)*10000000);
     switch (tmp)
     {
	case 2: case 3: case 4:
	     return number(num/1000000)+" miliony "+number(num%1000000);
	default:
	     return number(num/1000000)+" milion�w "+number(num%1000000);
     }
   default:
    return "wiele";
  }
}
