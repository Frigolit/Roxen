#! /usr/env/bin pike
// $Id: tetris.pike,v 1.5 2002/06/04 20:05:34 nilsson Exp $
import Process;mixed a,h,Q,e=([]),q=Q=([]),c,s,I,_,j,K,x=252,m,f=((array)"H45"
"BBI65@CJ@BMED45@GM@LBFP@NBHS@BCDA5@LBB5BNCK5BMEL5@BEC5@MEN5MNFO6@BFE45MFQ65M"
"HR4B@HF5MLHG5MYD")[*]-65,n=25,io,tm;int u(){foreach(sort(indices(Q)),_)_>11&&
_<264&&Q[_]-e[_]&&io->write((_-++I||_%12<1?sprintf("\33[%d;%dH",(I=_)/12,_%12*
2+28):"")+(Q[_]-K?(K=Q[_])?"\33[7;3"+K+"m":"\33[0m":"")+"  ");Q=([263:7]);e=q+
Q;e[263]=0;}int g(int b){for(_=4;_--;Q[m=_?x+f[n+_]:x]=q[m]=b&&f[n+4]);}int G(
int b){for(_=4;_--;)if(q[_?b+f[n+_]:b])return 1;}void tick(){h-=h/3e3;call_out
(tick,h);g(0);if(G(x+12)){g(++s);for(m=j=0;++j<252;)if(q[j]?++m>9&&j%12==10:(m
=0)){for(;j%12;q[j]=Q[j--]=0);for(;--j;q[j+12]=Q[j+12]=q[j]);}n=random(7)*5;G(
x=17)&&z(1);}else x+=12;g(7);u();}void k(mixed _,string Z){g(0);foreach(values
(Z),int c){if(c=search(a,c)+1){if(c==1)G(--x)&&++x;if(c==2){n=5*f[m=n];G(x)&&(
n=m);}if(c==3)G(++x)&&--x;if(c==4)for(;!G(x+12);++s)x+=12;if(c>4)if(z(c>5))
return;}}g(7);u();}void pause(mixed foo, string Z){int i=search(values(Z),a[4]
);if(i==-1)return;io->write("\33[H\33[J\33[7m");h=m;call_out(tick,h);k(foo,Z[i
+1..]);io->set_read_callback(k);}int z(int p){io->write("\33[H\33[J\33[0m"+s+
"\n");#if constant(roxen)
catch(Q=roxen.retrieve("tetris-highscores",0)->idi);if(!Q)#endif
Q=({});if(p){io->normal();Q+=({ ({s,tm+"\n"}) });}sort(Q);j=([]);foreach(
reverse(Q),m)if(++j[m[1]]<4&&(io->write(sprintf("\t%5d by %s\r",m[0],m[1])),j[
0]++>19))break;m=h;#if constant(roxen)
roxen.store("tetris-highscores",(["idi":Q]),1,0);#endif
if(p){io->quit();remove_call_out(tick);destruct(this_object());return 1;}io->
raw();Q=q;K=0;e=([]);remove_call_out(tick);io->set_read_callback(pause);return
1;}void tetris2(string name){sscanf(name,"%[a-zA-Z0-9��������]s\n",name);if(!
strlen(name)){io->get_name(tetris2);}else{tm=name;io->raw();io->
set_read_callback(k);call_out(tick,h);for(;++_<277;)q[276-_]=(_<25||_%12<2)&&7
;io->write("\33[H\33[J");u();}}void tetris(object input){a=(array)"jkl pq";h=
0.5;io=input;input->get_name(tetris2);}class telnet{inherit Stdio.File;mixed �
;void do_get_name(mixed id, string name){�(name);}string get_name(mixed w){�=w
;write("What is your name? ");set_read_callback(do_get_name);}void create(
object f){assign(f);destruct(f);}void raw(){write("��\"��\"\1\0���\1��\3��\3")
;}void normal(){write("��\1��\"");}void quit(){destruct(this_object());}}void
create(object f){if(f)tetris(telnet(f));}class console{inherit Stdio.File;
string get_name(mixed cb){cb(getenv("LOGNAME")||popen("id -un"));}void create(
){::create("stdin");}void raw(){system("stty raw cbreak -echo stop u");}void
normal(){system("stty sane");}void quit(){exit(0);}}int main(){tetris(console(
));return -1;}
